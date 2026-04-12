import ArgumentParser
import Foundation

struct ScreenshotsRun: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Plan the full screenshot workflow"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Path to screenshots plan JSON")
    var plan: String

    @Option(name: .long, help: "Output directory for all generated files")
    var outputDir: String

    @Option(name: .long, help: "Raw capture output directory")
    var captureOutputDir: String

    @Option(name: .long, help: "Framed output directory")
    var framedOutputDir: String

    @Option(name: .long, help: "Review output directory")
    var reviewOutputDir: String

    @Flag(name: .long, help: "Only describe the workflow without executing it")
    var dryRun: Bool = false

    func run() async throws {
        print(try execute())
    }

    func execute(fileManager: FileManager = .default) throws -> String {
        let planURL = URL(fileURLWithPath: plan)
        guard fileManager.fileExists(atPath: planURL.path) else {
            throw ValidationError("Plan not found at \(plan)")
        }

        _ = try ScreenshotsFileSupport.readJSON(ScreenshotsCapturePlan.self, from: planURL)

        let steps = [
            ScreenshotsRunStep(name: "capture", outputDir: captureOutputDir),
            ScreenshotsRunStep(name: "frame", outputDir: framedOutputDir),
            ScreenshotsRunStep(name: "review-generate", outputDir: reviewOutputDir),
            ScreenshotsRunStep(name: "upload", outputDir: outputDir),
        ]
        let result = ScreenshotsRunResult(
            command: "asc screenshots run",
            status: dryRun ? "dry-run" : "planned",
            planPath: plan,
            outputDir: outputDir,
            dryRun: dryRun,
            steps: steps
        )

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        if globals.outputFormat == .json {
            return try formatter.format(DataResponse(data: [result]))
        }
        return try formatter.formatItems(
            [result],
            headers: ["Command", "Status", "Dry Run", "Plan", "Output Dir", "Steps"],
            rowMapper: { [$0.command, $0.status, $0.dryRun ? "true" : "false", $0.planPath, $0.outputDir, "\($0.steps.count)"] }
        )
    }
}

private struct ScreenshotsRunResult: Codable {
    let command: String
    let status: String
    let planPath: String
    let outputDir: String
    let dryRun: Bool
    let steps: [ScreenshotsRunStep]
}

private struct ScreenshotsRunStep: Codable {
    let name: String
    let outputDir: String
}
