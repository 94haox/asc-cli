import ArgumentParser
import Domain

struct NotarizationLogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "Get local notarization logs by submission ID"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Submission ID")
    var id: String

    func run() async throws {
        let repo = try ClientProvider.makeNotarizationRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any NotarizationRepository) async throws -> String {
        let log = try await repo.getNotarizationLog(id: id)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        if globals.outputFormat == .json {
            return try formatter.format(DataResponse(data: [log]))
        }
        return try formatter.formatItems(
            [log],
            headers: ["ID", "Log"],
            rowMapper: { [$0.id, $0.text] }
        )
    }
}
