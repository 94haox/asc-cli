import ArgumentParser
import Domain
import Foundation

struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Canonical App Store submission readiness report",
        subcommands: [ValidateIAPCommand.self, ValidateSubscriptionsCommand.self]
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App Store Connect app ID")
    var app: String

    @Option(name: .long, help: "App Store version string")
    var version: String?

    @Option(name: .long, help: "App Store version ID")
    var versionId: String?

    @Option(name: .long, help: "Platform: IOS, MAC_OS, TV_OS, VISION_OS")
    var platform: String?

    func run() throws {
        print(try execute())
    }

    func execute() throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(ValidateEnvelope(
            command: "validate",
            appId: app,
            version: version,
            versionId: versionId,
            platform: platform,
            status: "not_implemented_yet",
            checks: [
                "metadata",
                "reviewDetails",
                "buildAttachment",
                "pricingAvailability",
            ]
        ))
    }
}

struct ValidateIAPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iap",
        abstract: "Validate IAP review readiness"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App Store Connect app ID")
    var app: String

    func run() throws {
        print(try execute())
    }

    func execute() throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(ValidateCategoryEnvelope(command: "validate iap", category: "iap", appId: app, status: "not_implemented_yet"))
    }
}

struct ValidateSubscriptionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscriptions",
        abstract: "Validate subscription review readiness"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App Store Connect app ID")
    var app: String

    func run() throws {
        print(try execute())
    }

    func execute() throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.format(ValidateCategoryEnvelope(command: "validate subscriptions", category: "subscriptions", appId: app, status: "not_implemented_yet"))
    }
}

private struct ValidateEnvelope: Encodable {
    let command: String
    let appId: String
    let version: String?
    let versionId: String?
    let platform: String?
    let status: String
    let checks: [String]
}

private struct ValidateCategoryEnvelope: Encodable {
    let command: String
    let category: String
    let appId: String
    let status: String
}
