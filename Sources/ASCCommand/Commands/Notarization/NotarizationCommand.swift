import ArgumentParser
import Domain

struct NotarizationCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notarization",
        abstract: "Manage local notarization submissions",
        subcommands: [
            NotarizationSubmit.self,
            NotarizationList.self,
            NotarizationLogCommand.self,
            NotarizationStatusCommand.self,
        ]
    )
}
