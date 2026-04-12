import ArgumentParser
import Domain

struct XcodeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcode",
        abstract: "Compatibility commands for Xcode-related workflows",
        subcommands: [XcodeVersionCommand.self]
    )
}

struct XcodeVersionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Inspect Xcode Cloud workflow versions",
        subcommands: [XcodeVersionList.self],
        defaultSubcommand: XcodeVersionList.self
    )
}

struct XcodeVersionList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List workflows through the xcode version compatibility layer"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Xcode Cloud product ID")
    var productId: String?

    func run() async throws {
        let repo = try ClientProvider.makeXcodeCloudWorkflowRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any XcodeCloudWorkflowRepository) async throws -> String {
        let workflows = try await fetchWorkflows(repo: repo)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems(
            workflows,
            headers: ["ID", "Product ID", "Name", "Enabled", "Locked"],
            rowMapper: { workflow in
                [
                    workflow.id,
                    workflow.productId,
                    workflow.name,
                    workflow.isEnabled ? "Yes" : "No",
                    workflow.isLockedForEditing ? "Yes" : "No",
                ]
            }
        )
    }

    private func fetchWorkflows(repo: any XcodeCloudWorkflowRepository) async throws -> [XcodeCloudWorkflow] {
        guard let productId else { return [] }
        return try await repo.listWorkflows(productId: productId)
    }
}
