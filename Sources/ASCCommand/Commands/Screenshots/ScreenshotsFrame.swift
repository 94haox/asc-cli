import ArgumentParser
import Foundation

struct ScreenshotsFrame: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "frame",
        abstract: "Frame screenshots using a device template"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Path to a directory of source screenshots")
    var input: String

    @Option(name: .long, help: "Output directory for framed screenshots")
    var outputDir: String

    @Option(name: .long, help: "Device name")
    var device: String

    @Option(name: .long, help: "Orientation name")
    var orientation: String = "portrait"

    func run() async throws {
        print(try execute(fileManager: .default))
    }

    func execute(fileManager: FileManager = .default) throws -> String {
        let sourceURL = URL(fileURLWithPath: input)
        let imageURLs = try ScreenshotsFileSupport.imageFiles(in: sourceURL, fileManager: fileManager)
        guard !imageURLs.isEmpty else {
            throw ValidationError("No image files found in \(input)")
        }

        let destinationURL = URL(fileURLWithPath: outputDir)
        try ScreenshotsFileSupport.copyFiles(imageURLs, to: destinationURL, fileManager: fileManager)

        let result = ScreenshotsFrameResult(
            command: "asc screenshots frame",
            status: "planned",
            framedCount: imageURLs.count,
            outputDir: outputDir,
            device: device,
            orientation: orientation
        )

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        if globals.outputFormat == .json {
            return try formatter.format(DataResponse(data: [result]))
        }
        return try formatter.formatItems(
            [result],
            headers: ["Command", "Status", "Framed", "Output Dir", "Device", "Orientation"],
            rowMapper: { [$0.command, $0.status, "\($0.framedCount)", $0.outputDir, $0.device, $0.orientation] }
        )
    }
}

private struct ScreenshotsFrameResult: Codable {
    let command: String
    let status: String
    let framedCount: Int
    let outputDir: String
    let device: String
    let orientation: String
}
