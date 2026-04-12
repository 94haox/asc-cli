import ArgumentParser
import Domain

struct VersionsView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View a single App Store version"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App Store version ID")
    var versionId: String

    func run() async throws {
        let repo = try ClientProvider.makeVersionRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any VersionRepository, affordanceMode: AffordanceMode = .cli) async throws -> String {
        let version = try await repo.getVersion(id: versionId)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems([version], affordanceMode: affordanceMode)
    }
}
