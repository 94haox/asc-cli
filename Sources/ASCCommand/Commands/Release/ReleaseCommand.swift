import ArgumentParser
import Domain
import Foundation

struct ReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Run high-level App Store release workflows",
        subcommands: [ReleaseStageCommand.self, ReleaseRunCommand.self]
    )
}

struct ReleaseStageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stage",
        abstract: "Prepare a version without submitting"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App Store Connect app ID")
    var app: String

    @Option(name: .long, help: "Version string")
    var version: String

    @Option(name: .long, help: "Build ID")
    var build: String

    @Flag(name: .long, help: "Preview execution without side effects")
    var dryRun: Bool = false

    func run() throws {
        print(try execute())
    }

    func execute() throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(ReleaseEnvelope(
            command: "release stage",
            appId: app,
            version: version,
            buildId: build,
            dryRun: dryRun,
            submit: false,
            steps: ["ensureVersion", "applyMetadata", "attachBuild", "validateReadiness"],
            status: "not_implemented_yet"
        ))
    }
}

struct ReleaseRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run end-to-end release flow"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App Store Connect app ID")
    var app: String

    @Option(name: .long, help: "Version string")
    var version: String

    @Option(name: .long, help: "Build ID")
    var build: String

    @Flag(name: .long, help: "Submit after staging")
    var submit: Bool = false

    @Flag(name: .long, help: "Required when mutating remote state")
    var confirm: Bool = false

    @Flag(name: .long, help: "Preview execution without side effects")
    var dryRun: Bool = false

    func run() throws {
        print(try execute())
    }

    func execute() throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        let status: String = if dryRun { "dry_run" } else if submit, !confirm { "missing_confirm" } else { "not_implemented_yet" }

        return try formatter.format(ReleaseEnvelope(
            command: "release run",
            appId: app,
            version: version,
            buildId: build,
            dryRun: dryRun,
            submit: submit,
            steps: ["ensureVersion", "applyMetadata", "attachBuild", "validateReadiness", "submitReview"],
            status: status
        ))
    }
}

private struct ReleaseEnvelope: Encodable {
    let command: String
    let appId: String
    let version: String
    let buildId: String
    let dryRun: Bool
    let submit: Bool
    let steps: [String]
    let status: String
}
