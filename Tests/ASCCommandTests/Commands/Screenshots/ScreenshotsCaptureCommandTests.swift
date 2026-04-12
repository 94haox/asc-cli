import Foundation
import Testing
@testable import ASCCommand

@Suite
struct ScreenshotsCaptureCommandTests {

    private func makePlanFile(bundleId: String = "com.example.app") throws -> String {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-capture-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let planURL = baseURL.appendingPathComponent("screenshots.json")

        let planData = """
        {
          "bundleId": "\(bundleId)",
          "scenes": [
            { "name": "home", "device": "iPhone 16", "frame": true },
            { "name": "settings", "device": "iPhone 16", "frame": true }
          ]
        }
        """.data(using: .utf8)!
        try planData.write(to: planURL, options: .atomic)
        return planURL.path
    }

    @Test func `capture uses plan and returns status with captured count`() async throws {
        let planPath = try makePlanFile()
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-capture-output-\(UUID().uuidString)")
            .path

        let cmd = try ScreenshotsCapture.parse([
            "--bundle-id", "com.example.app",
            "--plan", planPath,
            "--output-dir", outputDir,
            "--pretty"
        ])
        let output = try cmd.execute()
        let normalized = output.replacingOccurrences(of: "\\/", with: "/")

        #expect(normalized.contains("\"status\" : \"planned\""))
        #expect(normalized.contains("\"captured\" : 2"))
        #expect(normalized.contains(outputDir))
    }

    @Test func `capture supports table output mode` () async throws {
        let planPath = try makePlanFile()
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-capture-output-\(UUID().uuidString)")
            .path

        let cmd = try ScreenshotsCapture.parse([
            "--bundle-id", "com.example.app",
            "--plan", planPath,
            "--output-dir", outputDir,
            "--output", "table"
        ])
        let output = try cmd.execute()

        #expect(output.contains("asc screenshots capture"))
        #expect(output.contains("2"))
    }

    @Test func `capture missing plan returns validation failure` () async throws {
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asc-screenshots-capture-output-\(UUID().uuidString)")
            .path

        let cmd = try ScreenshotsCapture.parse([
            "--bundle-id", "com.example.app",
            "--plan", "/tmp/does-not-exist-\(UUID().uuidString).json",
            "--output-dir", outputDir,
        ])

        await #expect(throws: (any Error).self) {
            _ = try cmd.execute()
        }
    }
}
