import ArgumentParser
import Domain
import Foundation

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
    @Option(name: .long, help: "App Store Connect app ID") var app: String
    @Option(name: .long, help: "App Store version string") var version: String?
    @Option(name: .long, help: "Platform") var platform: String?

    func run() throws {
        print(try execute())
    }

    func execute() throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(SubmitEnvelope(command: "submit preflight", appId: app, versionId: nil, submissionId: nil, version: version, platform: platform, status: "not_implemented_yet"))
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
        return try formatter.format(SubmitEnvelope(command: "submit create", appId: app, versionId: nil, submissionId: nil, version: version, platform: nil, status: confirm ? "accepted_not_implemented" : "missing_confirm"))
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
        return try formatter.format(SubmitEnvelope(command: "submit status", appId: nil, versionId: versionId, submissionId: id, version: nil, platform: nil, status: "not_implemented_yet"))
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
        return try formatter.format(SubmitEnvelope(command: "submit cancel", appId: nil, versionId: versionId, submissionId: id, version: nil, platform: nil, status: confirm ? "accepted_not_implemented" : "missing_confirm"))
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
}
