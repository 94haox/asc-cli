import ArgumentParser
import Domain
import Foundation

struct SubmissionReadinessResult {
    let version: AppStoreVersion
    let readiness: VersionReadiness
}

struct SubmissionReadinessService {
    func resolveAndBuild(
        app: String?,
        version: String?,
        versionId: String?,
        platform: String?,
        versionRepo: any VersionRepository,
        appRepo: any AppRepository,
        buildRepo: any BuildRepository,
        reviewDetailRepo: any ReviewDetailRepository,
        localizationRepo: any VersionLocalizationRepository,
        screenshotRepo: any ScreenshotRepository,
        pricingRepo: any PricingRepository,
        projectStorage: any ProjectConfigStorage
    ) async throws -> SubmissionReadinessResult {
        let resolvedVersion = try await resolveVersion(
            app: app,
            version: version,
            versionId: versionId,
            platform: platform,
            versionRepo: versionRepo,
            projectStorage: projectStorage
        )

        let readiness = try await buildReadiness(
            version: resolvedVersion,
            appRepo: appRepo,
            buildRepo: buildRepo,
            reviewDetailRepo: reviewDetailRepo,
            localizationRepo: localizationRepo,
            screenshotRepo: screenshotRepo,
            pricingRepo: pricingRepo
        )

        return SubmissionReadinessResult(version: resolvedVersion, readiness: readiness)
    }

    private func resolveVersion(
        app: String?,
        version: String?,
        versionId: String?,
        platform: String?,
        versionRepo: any VersionRepository,
        projectStorage: any ProjectConfigStorage
    ) async throws -> AppStoreVersion {
        if let versionId {
            return try await versionRepo.getVersion(id: versionId)
        }

        guard let version else {
            throw ValidationError("Provide --version-id, or provide --version (plus --app or .asc/project.json)")
        }

        let appId: String
        if let app {
            appId = app
        } else if let config = try projectStorage.load() {
            appId = config.appId
        } else {
            throw ValidationError("Missing app context. Pass --app or run `asc init` first.")
        }

        let versions = try await versionRepo.listVersions(appId: appId)
        var matches = versions.filter { $0.versionString == version }

        if let platform {
            let parsedPlatform = try parsePlatform(platform)
            matches = matches.filter { $0.platform == parsedPlatform }
        }

        guard !matches.isEmpty else {
            throw ValidationError("No version found for app \(appId), version \(version)\(platform.map { ", platform \($0)" } ?? "")")
        }

        if matches.count > 1 {
            let ids = matches.map(\.id).joined(separator: ", ")
            throw ValidationError("Multiple matching versions found: \(ids). Pass --version-id or --platform.")
        }

        return matches[0]
    }

    private func parsePlatform(_ raw: String) throws -> AppStorePlatform {
        if let platform = AppStorePlatform(cliArgument: raw) {
            return platform
        }
        if let platform = AppStorePlatform(rawValue: raw.uppercased()) {
            return platform
        }
        if let platform = AppStorePlatform(rawValue: raw) {
            return platform
        }
        let choices = AppStorePlatform.allCases.map(\.rawValue).joined(separator: ", ")
        throw ValidationError("Invalid --platform '\(raw)'. Supported values: \(choices)")
    }

    private func buildReadiness(
        version: AppStoreVersion,
        appRepo: any AppRepository,
        buildRepo: any BuildRepository,
        reviewDetailRepo: any ReviewDetailRepository,
        localizationRepo: any VersionLocalizationRepository,
        screenshotRepo: any ScreenshotRepository,
        pricingRepo: any PricingRepository
    ) async throws -> VersionReadiness {
        let stateCheck: ReadinessCheck = version.isEditable
            ? .pass()
            : .fail("Version state '\(version.state.rawValue)' is not editable")

        let buildCheck: BuildReadinessCheck
        if let buildId = version.buildId {
            let build = try await buildRepo.getBuild(id: buildId)
            let buildVersion: String
            if let num = build.buildNumber {
                buildVersion = "\(build.version) (\(num))"
            } else {
                buildVersion = build.version
            }
            buildCheck = BuildReadinessCheck(
                linked: true,
                valid: build.processingState == .valid,
                notExpired: !build.expired,
                buildVersion: buildVersion
            )
        } else {
            buildCheck = BuildReadinessCheck(linked: false, valid: false, notExpired: false)
        }

        let hasPricing = try await pricingRepo.hasPricing(appId: version.appId)
        let pricingCheck: ReadinessCheck = hasPricing
            ? .pass()
            : .fail("No price schedule configured for this app")

        let reviewDetail = try await reviewDetailRepo.getReviewDetail(versionId: version.id)
        let reviewContactCheck: ReadinessCheck = reviewDetail.hasContact
            ? .pass()
            : .fail("No contact email or phone set in App Store review information")

        let app = try await appRepo.getApp(id: version.appId)
        let primaryLocale = app.primaryLocale
        let localizations = try await localizationRepo.listLocalizations(versionId: version.id)

        var localizationReadiness: [LocalizationReadiness] = []
        for loc in localizations {
            let sets = try await screenshotRepo.listScreenshotSets(localizationId: loc.id)
            let screenshotSetCount = sets.filter { $0.screenshotsCount > 0 }.count
            let isPrimary = primaryLocale != nil
                ? loc.locale == primaryLocale
                : localizations.first?.id == loc.id

            localizationReadiness.append(LocalizationReadiness(
                locale: loc.locale,
                isPrimary: isPrimary,
                hasDescription: loc.description != nil,
                hasKeywords: loc.keywords != nil,
                hasSupportUrl: loc.supportUrl != nil,
                hasWhatsNew: loc.whatsNew != nil,
                screenshotSetCount: screenshotSetCount
            ))
        }

        let localizationCheck = LocalizationReadinessCheck(localizations: localizationReadiness)
        let isReadyToSubmit = stateCheck.pass && buildCheck.pass && pricingCheck.pass && localizationCheck.pass

        return VersionReadiness(
            id: version.id,
            appId: version.appId,
            versionString: version.versionString,
            state: version.state,
            isReadyToSubmit: isReadyToSubmit,
            stateCheck: stateCheck,
            buildCheck: buildCheck,
            pricingCheck: pricingCheck,
            localizationCheck: localizationCheck,
            reviewContactCheck: reviewContactCheck
        )
    }
}
