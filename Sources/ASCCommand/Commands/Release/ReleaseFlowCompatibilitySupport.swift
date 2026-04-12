import Domain
import Foundation

struct CompatibilityCheck: Codable, Equatable {
    let name: String
    let status: String
    let detail: String
}

struct FlowPlanStep: Codable, Equatable {
    let name: String
    let status: String
    let detail: String
}

struct PreflightReport: Codable, Equatable, Identifiable {
    let id: String
    let appId: String
    let version: String
    let versionId: String
    let platform: AppStorePlatform
    let eligible: Bool
    let blockingIssues: [String]
    let warnings: [String]
    let checks: [CompatibilityCheck]
}

struct ValidateAppReport: Codable, Equatable, Identifiable {
    let id: String
    let appId: String
    let version: String
    let versionId: String
    let platform: AppStorePlatform
    let ok: Bool
    let blockers: [String]
    let warnings: [String]
    let checks: [CompatibilityCheck]
}

struct SubmitCreateResult: Codable, Equatable, Identifiable {
    let id: String
    let submissionId: String
    let appId: String
    let versionId: String
    let version: String
    let buildId: String
    let state: ReviewSubmissionState
}

struct ReleaseStageReport: Codable, Equatable, Identifiable {
    let id: String
    let appId: String
    let version: String
    let metadataDir: String?
    let copyMetadataFrom: String?
    let confirmed: Bool
    let mode: String
    let actions: [FlowPlanStep]
}

struct ReleaseRunReport: Codable, Equatable, Identifiable {
    let id: String
    let appId: String
    let version: String
    let validate: Bool
    let submit: Bool
    let publish: Bool
    let dryRun: Bool
    let mode: String
    let steps: [FlowPlanStep]
}

struct PublishTestFlightReport: Codable, Equatable, Identifiable {
    let id: String
    let appId: String
    let ipa: String
    let group: String
    let wait: Bool
    let confirmed: Bool
    let mode: String
    let actions: [FlowPlanStep]
}

struct PublishAppStoreReport: Codable, Equatable, Identifiable {
    let id: String
    let appId: String
    let ipa: String
    let version: String
    let wait: Bool
    let submit: Bool
    let confirmed: Bool
    let mode: String
    let actions: [FlowPlanStep]
}

struct SubmittedVersionResolution {
    let appId: String
    let version: AppStoreVersion
    let build: Build
}

enum ReleaseFlowCompatibilitySupport {
    static func render<T: Encodable>(
        _ items: [T],
        formatter: OutputFormatter,
        headers: [String],
        rowMapper: (T) -> [String]
    ) throws -> String {
        switch formatter.format {
        case .json:
            return try formatter.format(DataResponse(data: items))
        case .table:
            return try formatter.formatItems(items, headers: headers, rowMapper: rowMapper)
        case .markdown:
            return try formatter.formatItems(items, headers: headers, rowMapper: rowMapper)
        }
    }

    static func renderSingle<T: Encodable>(
        _ item: T,
        formatter: OutputFormatter
    ) throws -> String {
        switch formatter.format {
        case .json:
            return try formatter.format(SingleDataResponse(data: item))
        case .table:
            return "\(item)"
        case .markdown:
            return "\(item)"
        }
    }

    static func loadVersion(
        appId: String,
        versionString: String,
        platform: AppStorePlatform?,
        versionRepo: any VersionRepository
    ) async throws -> AppStoreVersion {
        let versions = try await versionRepo.listVersions(appId: appId)
        let candidates = versions.filter { candidate in
            candidate.versionString == versionString && (platform == nil || candidate.platform == platform)
        }
        if let exact = candidates.first {
            return exact
        }
        if let platform {
            throw ValidationError("No \(platform.displayName) version \(versionString) found for app \(appId).")
        }
        throw ValidationError("No version \(versionString) found for app \(appId).")
    }

    static func loadVersionAndBuild(
        appId: String,
        versionString: String,
        buildId: String,
        versionRepo: any VersionRepository,
        buildRepo: any BuildRepository
    ) async throws -> SubmittedVersionResolution {
        let build = try await buildRepo.getBuild(id: buildId)
        let version = try await loadVersion(
            appId: appId,
            versionString: versionString,
            platform: build.platform?.appStorePlatform,
            versionRepo: versionRepo
        )
        guard version.platform == .iOS || version.platform == .macOS || version.platform == .tvOS || version.platform == .watchOS || version.platform == .visionOS else {
            throw ValidationError("Unsupported version platform.")
        }
        guard build.version == versionString else {
            throw ValidationError("Build \(buildId) belongs to version \(build.version), not \(versionString).")
        }
        return SubmittedVersionResolution(appId: appId, version: version, build: build)
    }

    static func assess(
        appId: String,
        version: AppStoreVersion,
        build: Build?,
        appRepo: any AppRepository,
        buildRepo: any BuildRepository,
        reviewDetailRepo: any ReviewDetailRepository,
        localizationRepo: any VersionLocalizationRepository,
        screenshotRepo: any ScreenshotRepository,
        pricingRepo: any PricingRepository
    ) async throws -> (blockers: [String], warnings: [String], checks: [CompatibilityCheck]) {
        let _ = try await appRepo.getApp(id: appId)

        var blockers: [String] = []
        var warnings: [String] = []
        var checks: [CompatibilityCheck] = []

        if version.isEditable {
            checks.append(.init(name: "state", status: "pass", detail: "Version is editable"))
        } else {
            let issue = "Version state \(version.state.rawValue) is not editable"
            blockers.append(issue)
            checks.append(.init(name: "state", status: "fail", detail: issue))
        }

        if let build {
            let buildLabel = build.buildNumber ?? build.id
            if build.isUsable {
                checks.append(.init(name: "build", status: "pass", detail: "Build \(buildLabel) is linked and valid"))
            } else {
                let issue = "Build \(build.id) is not valid"
                blockers.append(issue)
                checks.append(.init(name: "build", status: "fail", detail: issue))
            }
        } else if let buildId = version.buildId {
            let actualBuild = try await buildRepo.getBuild(id: buildId)
            let buildLabel = actualBuild.buildNumber ?? actualBuild.id
            if actualBuild.isUsable {
                checks.append(.init(name: "build", status: "pass", detail: "Build \(buildLabel) is linked and valid"))
            } else {
                let issue = "Build \(actualBuild.id) is not valid"
                blockers.append(issue)
                checks.append(.init(name: "build", status: "fail", detail: issue))
            }
        } else {
            let issue = "No build linked to this version"
            blockers.append(issue)
            checks.append(.init(name: "build", status: "fail", detail: issue))
        }

        if try await pricingRepo.hasPricing(appId: appId) {
            checks.append(.init(name: "pricing", status: "pass", detail: "Pricing is configured"))
        } else {
            let issue = "No price schedule configured for this app"
            blockers.append(issue)
            checks.append(.init(name: "pricing", status: "fail", detail: issue))
        }

        let reviewDetail = try await reviewDetailRepo.getReviewDetail(versionId: version.id)
        if reviewDetail.hasContact {
            checks.append(.init(name: "review-contact", status: "pass", detail: "Review contact is set"))
        } else {
            let issue = "No contact email or phone is set"
            warnings.append(issue)
            checks.append(.init(name: "review-contact", status: "warn", detail: issue))
        }

        let localizations = try await localizationRepo.listLocalizations(versionId: version.id)
        if localizations.isEmpty {
            let issue = "No localizations exist for this version"
            warnings.append(issue)
            checks.append(.init(name: "localization", status: "warn", detail: issue))
        } else {
            let screenshotSets = try await localizations.asyncMap { localization in
                try await screenshotRepo.listScreenshotSets(localizationId: localization.id)
            }
            let totalScreenshotSets = screenshotSets.flatMap { $0 }.count
            if totalScreenshotSets > 0 {
                checks.append(.init(name: "localization", status: "pass", detail: "Localization and screenshots are ready"))
            } else {
                let issue = "No screenshot sets found for any localization"
                warnings.append(issue)
                checks.append(.init(name: "localization", status: "warn", detail: issue))
            }
        }

        return (blockers, warnings, checks)
    }

    static func summarizePlan(
        appId: String,
        version: String,
        mode: String,
        actions: [FlowPlanStep]
    ) -> String {
        [appId, version, mode].joined(separator: ":")
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            results.append(try await transform(element))
        }
        return results
    }
}

private extension BuildUploadPlatform {
    var appStorePlatform: AppStorePlatform {
        switch self {
        case .iOS: return .iOS
        case .macOS: return .macOS
        case .tvOS: return .tvOS
        case .visionOS: return .visionOS
        }
    }
}
