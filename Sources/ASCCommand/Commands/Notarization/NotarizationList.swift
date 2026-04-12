import ArgumentParser

import Domain

struct NotarizationList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List notarization submissions in the local manifest"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Maximum number of submissions")
    var limit: Int?

    func run() async throws {
        let repo = try ClientProvider.makeNotarizationRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any NotarizationRepository) async throws -> String {
        let items = try await repo.listNotarizations(limit: limit)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        if globals.outputFormat == .json {
            return try formatter.format(DataResponse(data: items))
        }
        return try formatter.formatItems(
            items,
            headers: ["ID", "Status"],
            rowMapper: { [$0.id, $0.status.rawValue] }
        )
    }
}
