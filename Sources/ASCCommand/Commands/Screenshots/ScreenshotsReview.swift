import ArgumentParser
import Foundation

struct ScreenshotsReviewGenerate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review-generate",
        abstract: "Generate a local screenshot review bundle"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Path to framed screenshots directory")
    var framedDir: String

    @Option(name: .long, help: "Output directory for the review bundle")
    var outputDir: String

    @Option(name: .long, help: "Review title")
    var title: String

    func run() async throws {
        print(try execute(fileManager: .default))
    }

    func execute(fileManager: FileManager = .default) throws -> String {
        let sourceURL = URL(fileURLWithPath: framedDir)
        let framedFiles = try ScreenshotsFileSupport.imageFiles(in: sourceURL, fileManager: fileManager)
        guard !framedFiles.isEmpty else {
            throw ValidationError("No framed screenshots found in \(framedDir)")
        }

        let destinationURL = URL(fileURLWithPath: outputDir)
        try ScreenshotsFileSupport.ensureDirectory(destinationURL, fileManager: fileManager)
        try ScreenshotsFileSupport.copyFiles(framedFiles, to: destinationURL, fileManager: fileManager)

        let manifest = ScreenshotsReviewManifest(
            title: title,
            entryCount: framedFiles.count,
            entries: framedFiles.map { .init(fileName: $0.lastPathComponent) }
        )
        let manifestURL = destinationURL.appendingPathComponent("manifest.json")
        try ScreenshotsFileSupport.writeJSON(manifest, to: manifestURL, pretty: true)

        let indexURL = destinationURL.appendingPathComponent("index.html")
        try """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <title>\(title)</title>
          </head>
          <body>
            <main>\(title)</main>
          </body>
        </html>
        """.data(using: .utf8)!.write(to: indexURL, options: .atomic)

        let result = ScreenshotsReviewResult(
            command: "asc screenshots review-generate",
            status: "generated",
            entryCount: framedFiles.count,
            outputDir: outputDir,
            manifestPath: manifestURL.path,
            indexPath: indexURL.path
        )

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        if globals.outputFormat == .json {
            return try formatter.format(DataResponse(data: [result]))
        }
        return try formatter.formatItems(
            [result],
            headers: ["Command", "Status", "Entries", "Output Dir", "Manifest", "Index"],
            rowMapper: { [$0.command, $0.status, "\($0.entryCount)", $0.outputDir, $0.manifestPath, $0.indexPath] }
        )
    }
}

struct ScreenshotsReviewOpen: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review-open",
        abstract: "Open a local screenshot review bundle"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Output directory for the review bundle")
    var outputDir: String

    func run() async throws {
        print(try execute(fileManager: .default))
    }

    func execute(fileManager: FileManager = .default) throws -> String {
        let baseURL = URL(fileURLWithPath: outputDir)
        let indexURL = baseURL.appendingPathComponent("index.html")
        let manifestURL = baseURL.appendingPathComponent("manifest.json")
        if !fileManager.fileExists(atPath: baseURL.path) {
            try ScreenshotsFileSupport.ensureDirectory(baseURL, fileManager: fileManager)
        }
        if !fileManager.fileExists(atPath: indexURL.path) {
            try "<!doctype html><html><body>review</body></html>".data(using: .utf8)!.write(to: indexURL, options: .atomic)
        }

        let result = ScreenshotsReviewOpenResult(
            command: "asc screenshots review-open",
            status: "ready",
            outputDir: outputDir,
            indexPath: indexURL.path,
            manifestPath: manifestURL.path
        )

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        if globals.outputFormat == .json {
            return try formatter.format(DataResponse(data: [result]))
        }
        return try formatter.formatItems(
            [result],
            headers: ["Command", "Status", "Output Dir", "Index", "Manifest"],
            rowMapper: { [$0.command, $0.status, $0.outputDir, $0.indexPath, $0.manifestPath] }
        )
    }
}

struct ScreenshotsReviewApprove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review-approve",
        abstract: "Check whether a screenshot review bundle is ready"
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .long, help: "Require all manifest entries to be present")
    var allReady: Bool = false

    @Option(name: .long, help: "Output directory for the review bundle")
    var outputDir: String

    func run() async throws {
        print(try execute(fileManager: .default))
    }

    func execute(fileManager: FileManager = .default) throws -> String {
        let baseURL = URL(fileURLWithPath: outputDir)
        let manifestURL = baseURL.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw ValidationError("Missing manifest at \(manifestURL.path)")
        }

        let manifest = try ScreenshotsFileSupport.readJSON(ScreenshotsReviewManifest.self, from: manifestURL)
        var missing: [String] = []
        if allReady {
            for entry in manifest.entries {
                let fileURL = baseURL.appendingPathComponent(entry.fileName)
                if !fileManager.fileExists(atPath: fileURL.path) {
                    missing.append(entry.fileName)
                }
            }
        }

        guard missing.isEmpty else {
            throw ValidationError("Missing review assets: \(missing.joined(separator: ", "))")
        }

        let result = ScreenshotsReviewApproveResult(
            command: "asc screenshots review-approve",
            status: "ready",
            ready: true,
            outputDir: outputDir,
            checkedCount: manifest.entryCount
        )

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        if globals.outputFormat == .json {
            return try formatter.format(DataResponse(data: [result]))
        }
        return try formatter.formatItems(
            [result],
            headers: ["Command", "Status", "Ready", "Output Dir", "Checked"],
            rowMapper: { [$0.command, $0.status, $0.ready ? "true" : "false", $0.outputDir, "\($0.checkedCount)"] }
        )
    }
}

private struct ScreenshotsReviewResult: Codable {
    let command: String
    let status: String
    let entryCount: Int
    let outputDir: String
    let manifestPath: String
    let indexPath: String
}

private struct ScreenshotsReviewOpenResult: Codable {
    let command: String
    let status: String
    let outputDir: String
    let indexPath: String
    let manifestPath: String
}

private struct ScreenshotsReviewApproveResult: Codable {
    let command: String
    let status: String
    let ready: Bool
    let outputDir: String
    let checkedCount: Int
}
