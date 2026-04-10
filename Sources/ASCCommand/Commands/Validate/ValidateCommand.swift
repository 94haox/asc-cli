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
        let service = SubmissionReadinessService()
        let result = try await service.resolveAndBuild(
            app: app,
            version: version,
            versionId: versionId,
            platform: platform,
            versionRepo: versionRepo,
            appRepo: appRepo,
            buildRepo: buildRepo,
            reviewDetailRepo: reviewDetailRepo,
            localizationRepo: localizationRepo,
            screenshotRepo: screenshotRepo,
            pricingRepo: pricingRepo,
            projectStorage: projectStorage
        )

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(ValidateEnvelope(
            command: "validate",
            appId: result.readiness.appId,
            requestedVersion: version,
            requestedVersionId: versionId,
            requestedPlatform: platform,
            resolvedVersionId: result.version.id,
            status: result.readiness.isReadyToSubmit ? "ready" : "not_ready",
            readiness: result.readiness
        ))
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
