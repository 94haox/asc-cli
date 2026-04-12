import ArgumentParser
import Domain

struct AppsView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View a single app"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App ID")
    var id: String

    func run() async throws {
        let repo = try ClientProvider.makeAppRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any AppRepository, affordanceMode: AffordanceMode = .cli) async throws -> String {
        let app = try await repo.getApp(id: id)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems([app], affordanceMode: affordanceMode)
    }
}
