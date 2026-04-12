import ArgumentParser
import Foundation

struct ScreenshotsCapture: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture",
        abstract: "Plan screenshot capture from a screenshots plan"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App bundle identifier")
    var bundleId: String

    @Option(name: .long, help: "Path to screenshots plan JSON")
    var plan: String

    @Option(name: .long, help: "Output directory for captured screenshots")
    var outputDir: String

    func run() async throws {
        print(try execute())
    }

    func execute(fileManager: FileManager = .default) throws -> String {
        let planURL = URL(fileURLWithPath: plan)
        guard fileManager.fileExists(atPath: planURL.path) else {
            throw ValidationError("Plan not found at \(plan)")
        }

        let parsedPlan = try ScreenshotsFileSupport.readJSON(ScreenshotsCapturePlan.self, from: planURL)
        guard bundleId == parsedPlan.bundleId else {
            throw ValidationError("Plan bundle id \(parsedPlan.bundleId) does not match \(bundleId)")
        }

        let result = ScreenshotsCaptureResult(
            command: "asc screenshots capture",
            status: "planned",
            captured: parsedPlan.scenes.count,
            outputDir: outputDir,
            bundleId: parsedPlan.bundleId
        )

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        if globals.outputFormat == .json {
            return try formatter.format(DataResponse(data: [result]))
        }
        return try formatter.formatItems(
            [result],
            headers: ["Command", "Status", "Captured", "Output Dir"],
            rowMapper: { [$0.command, $0.status, "\($0.captured)", $0.outputDir] }
        )
    }
}

private struct ScreenshotsCaptureResult: Codable {
    let command: String
    let status: String
    let captured: Int
    let outputDir: String
    let bundleId: String
}
