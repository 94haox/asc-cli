import ArgumentParser
import Domain

struct SigningSyncPush: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "push",
        abstract: "Capture local signing data into a workspace manifest"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Whether to preview the local manifest update (defaults to true)")
    var dryRun: Bool?

    @Flag(name: .long, help: "Apply the workspace snapshot instead of dry run.")
    var confirm: Bool = false

    func run() async throws {
        let repo = try ClientProvider.makeSigningSyncRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any SigningSyncRepository) async throws -> String {
        let result = try await repo.sync(
            direction: .push,
            dryRun: confirm ? false : (dryRun ?? true),
            confirm: confirm
        )
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        if globals.outputFormat == .json {
            return try formatter.format(DataResponse(data: [result]))
        }
        return try formatter.formatItems(
            [result],
            headers: ["Direction", "Mode", "Items", "Confirm"],
            rowMapper: {
                [
                    $0.direction.rawValue,
                    $0.dryRun ? "dry-run" : "apply",
                    "\($0.itemCount)",
                    $0.confirm ? "true" : "false",
                ]
            }
        )
    }
}
