import ArgumentParser
import Domain
import Foundation
import Infrastructure

struct ReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Run high-level App Store release workflows",
        subcommands: [ReleaseStageCommand.self, ReleaseRunCommand.self]
    )
}

struct ReleaseStageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stage",
        abstract: "Prepare a version without submitting"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App Store Connect app ID")
    var app: String

    @Option(name: .long, help: "Version string")
    var version: String

    @Option(name: .long, help: "Build ID")
    var build: String

    @Option(name: .long, help: "Platform")
    var platform: String?

    @Flag(name: .long, help: "Preview execution without side effects")
    var dryRun: Bool = false

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
            versionId: nil,
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

        let status: String
        if !result.readiness.isReadyToSubmit {
            status = "blocked_not_ready"
        } else if dryRun {
            status = "dry_run"
        } else {
            status = "staged_not_implemented"
        }

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(ReleaseEnvelope(
            command: "release stage",
            appId: app,
            version: version,
            buildId: build,
            dryRun: dryRun,
            submit: false,
            steps: ["ensureVersion", "applyMetadata", "attachBuild", "validateReadiness"],
            status: status,
            resolvedVersionId: result.version.id,
            readinessStatus: result.readiness.isReadyToSubmit ? "ready" : "not_ready"
        ))
    }
}

struct ReleaseRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run end-to-end release flow"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App Store Connect app ID")
    var app: String

    @Option(name: .long, help: "Version string")
    var version: String

    @Option(name: .long, help: "Build ID")
    var build: String

    @Option(name: .long, help: "Platform")
    var platform: String?

    @Flag(name: .long, help: "Submit after staging")
    var submit: Bool = false

    @Flag(name: .long, help: "Required when mutating remote state")
    var confirm: Bool = false

    @Flag(name: .long, help: "Preview execution without side effects")
    var dryRun: Bool = false

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
            versionId: nil,
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

        let status: String
        if !result.readiness.isReadyToSubmit {
            status = "blocked_not_ready"
        } else if dryRun {
            status = "dry_run"
        } else if submit, !confirm {
            status = "missing_confirm"
        } else if submit, confirm {
            status = "accepted_not_implemented"
        } else {
            status = "staged_not_implemented"
        }

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(ReleaseEnvelope(
            command: "release run",
            appId: app,
            version: version,
            buildId: build,
            dryRun: dryRun,
            submit: submit,
            steps: ["ensureVersion", "applyMetadata", "attachBuild", "validateReadiness", "submitReview"],
            status: status,
            resolvedVersionId: result.version.id,
            readinessStatus: result.readiness.isReadyToSubmit ? "ready" : "not_ready"
        ))
    }
}

private struct ReleaseEnvelope: Encodable {
    let command: String
    let appId: String
    let version: String
    let buildId: String
    let dryRun: Bool
    let submit: Bool
    let steps: [String]
    let status: String
    let resolvedVersionId: String?
    let readinessStatus: String?
}
