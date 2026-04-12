import ArgumentParser
import Domain
import Foundation

struct MigrateExport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "export", abstract: "Export metadata into a migration workspace")

    @Option(name: .long, help: "App ID")
    var app: String

    @Option(name: .long, help: "Version string")
    var version: String

    @Option(name: .long, help: "Output directory")
    var outputDir: String = "./fastlane/metadata"

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
            outputDir: outputDir,
            versionRepo: versionRepo,
            versionLocalizationRepo: versionLocalizationRepo,
            appInfoRepo: appInfoRepo
        )
        return try OutputFormatter(format: globals.outputFormat, pretty: globals.pretty).format(summary)
    }
}

struct MigrateValidate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "validate", abstract: "Validate a migration workspace")

    @Option(name: .long, help: "Fastlane metadata directory")
    var fastlaneDir: String = "./fastlane/metadata"

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        print(try await execute())
    }

    func execute() async throws -> String {
        let report = MetadataWorkflowSupport.validateMetadata(root: fastlaneDir)
        return try OutputFormatter(format: globals.outputFormat, pretty: globals.pretty).format(report)
    }
}

struct MigrateImport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "import", abstract: "Import migration workspace data into ASC")

    @Option(name: .long, help: "App ID")
    var app: String

    @Option(name: .long, help: "Version string")
    var version: String

    @Option(name: .long, help: "Fastlane metadata directory")
    var fastlaneDir: String = "./fastlane/metadata"

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
            root: fastlaneDir,
            apply: !dryRun,
            versionRepo: versionRepo,
            versionLocalizationRepo: versionLocalizationRepo,
            appInfoRepo: appInfoRepo
        )
        return try OutputFormatter(format: globals.outputFormat, pretty: globals.pretty).format(summary)
    }
}
