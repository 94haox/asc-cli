import ArgumentParser
import Domain
import Foundation
import Infrastructure

struct SubmitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submit",
        abstract: "Submission lifecycle tools",
        subcommands: [SubmitPreflightCommand.self, SubmitCreateCommand.self, SubmitStatusCommand.self, SubmitCancelCommand.self]
    )
}

struct SubmitPreflightCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preflight",
        abstract: "Compatibility preflight entrypoint"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "App Store Connect app ID") var app: String?
    @Option(name: .long, help: "App Store version string") var version: String?
    @Option(name: .long, help: "App Store version ID") var versionId: String?
    @Option(name: .long, help: "Platform") var platform: String?

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
        return try formatter.format(SubmitEnvelope(
            command: "submit preflight",
            appId: result.readiness.appId,
            versionId: result.version.id,
            submissionId: nil,
            version: result.version.versionString,
            platform: result.version.platform.rawValue,
            status: result.readiness.isReadyToSubmit ? "ready" : "not_ready",
            resolvedVersionId: result.version.id,
            readinessStatus: result.readiness.isReadyToSubmit ? "ready" : "not_ready",
            isReadyToSubmit: result.readiness.isReadyToSubmit
        ))
    }
}

struct SubmitCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create an App Store review submission"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "App Store Connect app ID") var app: String
    @Option(name: .long, help: "App Store version string") var version: String
    @Option(name: .long, help: "Build ID") var build: String
    @Flag(name: .long, help: "Required for mutating operation") var confirm: Bool = false

    func run() throws {
        print(try execute())
    }

    func execute() throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(SubmitEnvelope(command: "submit create", appId: app, versionId: nil, submissionId: nil, version: version, platform: nil, status: confirm ? "accepted_not_implemented" : "missing_confirm", resolvedVersionId: nil, readinessStatus: nil, isReadyToSubmit: nil))
    }
}

struct SubmitStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check submission status"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "Submission ID") var id: String?
    @Option(name: .long, help: "Version ID") var versionId: String?

    func run() throws {
        print(try execute())
    }

    func execute() throws -> String {
        guard id != nil || versionId != nil else {
            throw ValidationError("Provide --id or --version-id")
        }
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(SubmitEnvelope(command: "submit status", appId: nil, versionId: versionId, submissionId: id, version: nil, platform: nil, status: "not_implemented_yet", resolvedVersionId: nil, readinessStatus: nil, isReadyToSubmit: nil))
    }
}

struct SubmitCancelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cancel",
        abstract: "Cancel a submission"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "Submission ID") var id: String?
    @Option(name: .long, help: "Version ID") var versionId: String?
    @Flag(name: .long, help: "Required for mutating operation") var confirm: Bool = false

    func run() throws {
        print(try execute())
    }

    func execute() throws -> String {
        guard id != nil || versionId != nil else {
            throw ValidationError("Provide --id or --version-id")
        }
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(SubmitEnvelope(command: "submit cancel", appId: nil, versionId: versionId, submissionId: id, version: nil, platform: nil, status: confirm ? "accepted_not_implemented" : "missing_confirm", resolvedVersionId: nil, readinessStatus: nil, isReadyToSubmit: nil))
    }
}

private struct SubmitEnvelope: Encodable {
    let command: String
    let appId: String?
    let versionId: String?
    let submissionId: String?
    let version: String?
    let platform: String?
    let status: String
    let resolvedVersionId: String?
    let readinessStatus: String?
    let isReadyToSubmit: Bool?
}
