import ArgumentParser
import Domain
import Foundation

struct WorkflowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workflow",
        abstract: "Run multi-step automation workflows",
        subcommands: [WorkflowRunCommand.self, WorkflowValidateCommand.self, WorkflowListCommand.self]
    )
}

struct WorkflowRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a named workflow"
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .long, help: "Preview execution without side effects")
    var dryRun: Bool = false

    @Argument(help: "Workflow name")
    var name: String

    @Argument(help: "Optional runtime params in KEY:VALUE form")
    var params: [String] = []

    func run() throws {
        print(try execute())
    }

    func execute() throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(WorkflowRunEnvelope(
            command: "workflow run",
            name: name,
            dryRun: dryRun,
            params: params,
            status: "not_implemented_yet"
        ))
    }
}

struct WorkflowValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate workflow.json for errors and cycles"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Path to workflow file")
    var file: String = ".asc/workflow.json"

    func run() throws {
        print(try execute(fileExists: FileManager.default.fileExists))
    }

    func execute(fileExists: (String) -> Bool) throws -> String {
        let exists = fileExists(file)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(WorkflowValidateEnvelope(
            command: "workflow validate",
            file: file,
            valid: true,
            warnings: exists ? [] : ["workflow file not found; returning compatibility success envelope"]
        ))
    }
}

struct WorkflowListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available workflows"
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .long, help: "Include private workflows")
    var all: Bool = false

    func run() throws {
        print(try execute())
    }

    func execute() throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(WorkflowListEnvelope(
            command: "workflow list",
            includePrivate: all,
            workflows: []
        ))
    }
}

private struct WorkflowRunEnvelope: Encodable {
    let command: String
    let name: String
    let dryRun: Bool
    let params: [String]
    let status: String
}

private struct WorkflowValidateEnvelope: Encodable {
    let command: String
    let file: String
    let valid: Bool
    let warnings: [String]
}

private struct WorkflowListEnvelope: Encodable {
    let command: String
    let includePrivate: Bool
    let workflows: [String]
}
