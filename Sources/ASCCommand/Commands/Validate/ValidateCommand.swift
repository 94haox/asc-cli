import ArgumentParser
import Domain
import Foundation
import Infrastructure

struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Canonical App Store submission readiness report",
        subcommands: [ValidateIAPCommand.self, ValidateSubscriptionsCommand.self]
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App Store Connect app ID")
    var app: String?

    @Option(name: .long, help: "App Store version string")
    var version: String?

    @Option(name: .long, help: "App Store version ID")
    var versionId: String?

    @Option(name: .long, help: "Platform: IOS, MAC_OS, TV_OS, WATCH_OS, VISION_OS")
    var platform: String?

    func run() async throws {
        let versionRepo = try ClientProvider.makeVersionRepository()
        let appRepo = try ClientProvider.makeAppRepository()
        let buildRepo = try ClientProvider.makeBuildRepository()
        let reviewDetailRepo = try ClientProvider.makeReviewDetailRepository()
        let localizationRepo = try ClientProvider.makeVersionLocalizationRepository()
        let screenshotRepo = try ClientProvider.makeScreenshotRepository()
        let pricingRepo = try ClientProvider.makePricingRepository()
        let projectStorage = FileProjectConfigStorage()

        print(try await execute(
            versionRepo: versionRepo,
            appRepo: appRepo,
            buildRepo: buildRepo,
            reviewDetailRepo: reviewDetailRepo,
            localizationRepo: localizationRepo,
            screenshotRepo: screenshotRepo,
            pricingRepo: pricingRepo,
            projectStorage: projectStorage
        ))
    }

    func execute(
        versionRepo: any VersionRepository,
        appRepo: any AppRepository,
        buildRepo: any BuildRepository,
        reviewDetailRepo: any ReviewDetailRepository,
        localizationRepo: any VersionLocalizationRepository,
        screenshotRepo: any ScreenshotRepository,
        pricingRepo: any PricingRepository,
        projectStorage: any ProjectConfigStorage
    ) async throws -> String {
        let resolved = try await resolveVersion(
            versionRepo: versionRepo,
            projectStorage: projectStorage
        )

        let readiness = try await buildReadiness(
            version: resolved,
            appRepo: appRepo,
            buildRepo: buildRepo,
            reviewDetailRepo: reviewDetailRepo,
            localizationRepo: localizationRepo,
            screenshotRepo: screenshotRepo,
            pricingRepo: pricingRepo
        )

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(ValidateEnvelope(
            command: "validate",
            appId: readiness.appId,
            requestedVersion: version,
            requestedVersionId: versionId,
            requestedPlatform: platform,
            resolvedVersionId: readiness.id,
            status: readiness.isReadyToSubmit ? "ready" : "not_ready",
            readiness: readiness
        ))
    }

    private func resolveVersion(
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

struct ValidateIAPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iap",
        abstract: "Validate IAP review readiness"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App Store Connect app ID")
    var app: String

    func run() throws {
        print(try execute())
    }

    func execute() throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(ValidateCategoryEnvelope(command: "validate iap", category: "iap", appId: app, status: "not_implemented_yet"))
    }
}

struct ValidateSubscriptionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscriptions",
        abstract: "Validate subscription review readiness"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App Store Connect app ID")
    var app: String

    func run() throws {
        print(try execute())
    }

    func execute() throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(ValidateCategoryEnvelope(command: "validate subscriptions", category: "subscriptions", appId: app, status: "not_implemented_yet"))
    }
}

private struct ValidateEnvelope: Encodable {
    let command: String
    let appId: String
    let requestedVersion: String?
    let requestedVersionId: String?
    let requestedPlatform: String?
    let resolvedVersionId: String
    let status: String
    let readiness: VersionReadiness
}

private struct ValidateCategoryEnvelope: Encodable {
    let command: String
    let category: String
    let appId: String
    let status: String
}
