import ArgumentParser
import Domain
import Foundation

struct MetadataPull: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "pull", abstract: "Export metadata into a file-backed workspace")

    @Option(name: .long, help: "App ID")
    var app: String

    @Option(name: .long, help: "Version string")
    var version: String

    @Option(name: .long, help: "Output directory")
    var dir: String = ".asc/metadata"

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        let appRepo = try ClientProvider.makeAppRepository()
        let versionRepo = try ClientProvider.makeVersionRepository()
        let versionLocalizationRepo = try ClientProvider.makeVersionLocalizationRepository()
        let appInfoRepo = try ClientProvider.makeAppInfoRepository()
        print(try await execute(appRepo: appRepo, versionRepo: versionRepo, versionLocalizationRepo: versionLocalizationRepo, appInfoRepo: appInfoRepo))
    }

    func execute(
        appRepo: any AppRepository,
        versionRepo: any VersionRepository,
        versionLocalizationRepo: any VersionLocalizationRepository,
        appInfoRepo: any AppInfoRepository
    ) async throws -> String {
        _ = try await appRepo.getApp(id: app)
        let summary = try await MetadataWorkflowSupport.exportMetadata(
            appId: app,
            version: version,
            outputDir: dir,
            versionRepo: versionRepo,
            versionLocalizationRepo: versionLocalizationRepo,
            appInfoRepo: appInfoRepo
        )
        return try OutputFormatter(format: globals.outputFormat, pretty: globals.pretty).format(summary)
    }
}

struct MetadataPush: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "push", abstract: "Import metadata from a file-backed workspace")

    @Option(name: .long, help: "App ID")
    var app: String

    @Option(name: .long, help: "Version string")
    var version: String

    @Option(name: .long, help: "Input directory")
    var dir: String = ".asc/metadata"

    @Flag(name: .long, help: "Only validate and plan changes")
    var dryRun: Bool = false

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        let versionRepo = try ClientProvider.makeVersionRepository()
        let versionLocalizationRepo = try ClientProvider.makeVersionLocalizationRepository()
        let appInfoRepo = try ClientProvider.makeAppInfoRepository()
        print(try await execute(versionRepo: versionRepo, versionLocalizationRepo: versionLocalizationRepo, appInfoRepo: appInfoRepo))
    }

    func execute(
        versionRepo: any VersionRepository,
        versionLocalizationRepo: any VersionLocalizationRepository,
        appInfoRepo: any AppInfoRepository
    ) async throws -> String {
        let summary = try await MetadataWorkflowSupport.syncMetadata(
            appId: app,
            version: version,
            root: dir,
            apply: !dryRun,
            versionRepo: versionRepo,
            versionLocalizationRepo: versionLocalizationRepo,
            appInfoRepo: appInfoRepo
        )
        return try OutputFormatter(format: globals.outputFormat, pretty: globals.pretty).format(summary)
    }
}

struct MetadataValidate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "validate", abstract: "Validate a metadata workspace")

    @Option(name: .long, help: "Input directory")
    var dir: String = ".asc/metadata"

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        print(try await execute())
    }

    func execute() async throws -> String {
        let report = MetadataWorkflowSupport.validateMetadata(root: dir)
        return try OutputFormatter(format: globals.outputFormat, pretty: globals.pretty).format(report)
    }
}
