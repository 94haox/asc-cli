import ArgumentParser
import Domain

struct NotarizationStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Get local notarization status details by submission ID"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Submission ID")
    var id: String

    func run() async throws {
        let repo = try ClientProvider.makeNotarizationRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any NotarizationRepository) async throws -> String {
        let status = try await repo.getNotarizationStatus(id: id)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        if globals.outputFormat == .json {
            return try formatter.format(DataResponse(data: [status]))
        }
        return try formatter.formatItems(
            [status],
            headers: ["ID", "Eligible", "Status", "Started At", "Updated At", "Failure Reason"],
            rowMapper: {
                [
                    $0.id,
                    $0.eligible ? "true" : "false",
                    $0.status.rawValue,
                    $0.startedAt ?? "-",
                    $0.updatedAt ?? "-",
                    $0.failureReason ?? "-",
                ]
            }
        )
    }
}
