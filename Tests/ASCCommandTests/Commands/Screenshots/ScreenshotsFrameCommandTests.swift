import Foundation
import Testing
@testable import ASCCommand

@Suite
struct ScreenshotsFrameCommandTests {

    private func makeImageDirectory() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-frame-input-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for index in 1...2 {
            let file = dir.appendingPathComponent("screen-\(index).png")
            try "image-\(index)".data(using: .utf8)!.write(to: file)
        }
        return dir
    }

    @Test func `frame creates framed outputs from image directory`() async throws {
        let sourceDir = try makeImageDirectory()
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-frame-output-\(UUID().uuidString)")

        let cmd = try ScreenshotsFrame.parse([
            "--input", sourceDir.path,
            "--output-dir", outputDir.path,
            "--device", "iPhone 16",
            "--orientation", "portrait",
            "--pretty"
        ])
        let output = try cmd.execute(fileManager: .default)

        #expect(output.contains("\"status\" : \"planned\""))
        #expect(output.contains("framedCount\""))
        let framedCount = collectImageURLs(at: outputDir.path, recursive: true).count
        #expect(framedCount == 2)
    }

    @Test func `frame throws when no image inputs are found`() async throws {
        let sourceDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-frame-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-frame-output-empty-\(UUID().uuidString)")

        let cmd = try ScreenshotsFrame.parse([
            "--input", sourceDir.path,
            "--output-dir", outputDir.path,
            "--device", "iPhone 16"
        ])

        await #expect(throws: (any Error).self) {
            _ = try cmd.execute(fileManager: .default)
        }
    }
}
