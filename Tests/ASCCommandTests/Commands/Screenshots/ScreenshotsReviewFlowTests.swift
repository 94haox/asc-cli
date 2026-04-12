import Foundation
import Testing
@testable import ASCCommand

@Suite
struct ScreenshotsReviewFlowTests {

    private func makeFramedDirectory() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-review-framed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for index in 1...2 {
            let file = dir.appendingPathComponent("framed-\(index).png")
            try "framed-\(index)".data(using: .utf8)!.write(to: file)
        }
        return dir
    }

    private func makePlanFile(bundleId: String = "com.example.app") throws -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-run-plan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("plan.json")
        try """
        {
          "bundleId": "\(bundleId)",
          "scenes": [
            { "name": "home", "device": "iPhone 16", "frame": true }
          ]
        }
        """.data(using: .utf8)!.write(to: path, options: .atomic)
        return path.path
    }

    @Test func `review-generate writes manifest and index`() async throws {
        let framedDir = try makeFramedDirectory()
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-review-output-\(UUID().uuidString)")

        let cmd = try ScreenshotsReviewGenerate.parse([
            "--framed-dir", framedDir.path,
            "--output-dir", outputDir.path,
            "--title", "Nightly",
            "--pretty"
        ])
        let output = try cmd.execute(fileManager: .default)

        #expect(output.contains("\"status\" : \"generated\""))
        #expect(output.contains("\"entryCount\" : 2"))
        let manifestURL = outputDir.appendingPathComponent("manifest.json")
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
        let indexURL = outputDir.appendingPathComponent("index.html")
        #expect(FileManager.default.fileExists(atPath: indexURL.path))
    }

    @Test func `review-open returns local paths for static mode`() async throws {
        let reviewDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-review-open-\(UUID().uuidString)")
        let cmd = try ScreenshotsReviewOpen.parse([
            "--output-dir", reviewDir.path,
            "--pretty"
        ])
        let output = try cmd.execute(fileManager: .default)
        #expect(output.contains("\"status\" : \"ready\""))
        #expect(output.contains("indexPath"))
    }

    @Test func `review-approve returns not-ready when manifest missing`() async throws {
        let reviewDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-review-missing-\(UUID().uuidString)")
        let cmd = try ScreenshotsReviewApprove.parse([
            "--all-ready",
            "--output-dir", reviewDir.path,
            "--pretty"
        ])
        await #expect(throws: (any Error).self) {
            _ = try cmd.execute(fileManager: .default)
        }
    }

    @Test func `review-approve reports ready when all entries exist`() async throws {
        let framedDir = try makeFramedDirectory()
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-review-output-ready-\(UUID().uuidString)")
        let generateCmd = try ScreenshotsReviewGenerate.parse([
            "--framed-dir", framedDir.path,
            "--output-dir", outputDir.path,
            "--title", "Ready check",
            "--pretty"
        ])
        _ = try generateCmd.execute(fileManager: .default)

        let approveCmd = try ScreenshotsReviewApprove.parse([
            "--all-ready",
            "--output-dir", outputDir.path,
            "--pretty"
        ])
        let output = try approveCmd.execute(fileManager: .default)
        #expect(output.contains("\"ready\" : true"))
        #expect(output.contains("\"status\" : \"ready\""))
    }

    @Test func `run dry-run exposes ordered steps`() async throws {
        let plan = try makePlanFile()
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-run-output-\(UUID().uuidString)")

        let cmd = try ScreenshotsRun.parse([
            "--plan", plan,
            "--output-dir", outputDir.path,
            "--capture-output-dir", outputDir.appendingPathComponent("raw").path,
            "--framed-output-dir", outputDir.appendingPathComponent("framed").path,
            "--review-output-dir", outputDir.appendingPathComponent("review").path,
            "--dry-run",
            "--pretty"
        ])
        let output = try cmd.execute()
        #expect(output.contains("\"status\" : \"dry-run\""))
        #expect(output.contains("\"name\" : \"capture\""))
        #expect(output.contains("\"name\" : \"frame\""))
        #expect(output.contains("\"name\" : \"review-generate\""))
        #expect(output.contains("\"name\" : \"upload\""))
    }
}
