import Foundation
import ArgumentParser
import Testing
@testable import ASCCommand

@Suite
struct WorkflowCommandTests {

    @Test func `list hides private workflows unless all is requested`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-workflow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workflowURL = tempDir.appendingPathComponent("workflow.json")
        try """
        {
          "workflows": {
            "release": {
              "steps": [
                "echo release"
              ]
            },
            "private": {
              "private": true,
              "steps": [
                "echo private"
              ]
            }
          }
        }
        """.data(using: .utf8)!.write(to: workflowURL)

        let cmd = try WorkflowList.parse(["--file", workflowURL.path, "--pretty"])
        let output = try await cmd.execute(fileManager: FileManager.default)

        #expect(output.contains("\"name\" : \"release\""))
        #expect(!output.contains("\"name\" : \"private\""))

        let allCmd = try WorkflowList.parse(["--file", workflowURL.path, "--all", "--pretty"])
        let allOutput = try await allCmd.execute(fileManager: FileManager.default)
        #expect(allOutput.contains("\"name\" : \"private\""))
    }

    @Test func `validate accepts jsonc and reports valid`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-workflow-validate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workflowURL = tempDir.appendingPathComponent("workflow.jsonc")
        try """
        {
          // comment
          "workflows": {
            "release": {
              "steps": [
                "echo X:version",
              ]
            }
          }
        }
        """.data(using: .utf8)!.write(to: workflowURL)

        let cmd = try WorkflowValidate.parse(["--file", workflowURL.path, "--pretty"])
        let output = try await cmd.execute(fileManager: FileManager.default)

        #expect(output.contains("\"valid\" : true"))
        #expect(output.contains("\"errors\" : ["))
    }

    @Test func `validate reports malformed placeholder syntax`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-workflow-placeholder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workflowURL = tempDir.appendingPathComponent("workflow.json")
        try """
        {
          "workflows": {
            "release": {
              "steps": [
                "echo X:"
              ]
            }
          }
        }
        """.data(using: .utf8)!.write(to: workflowURL)

        let cmd = try WorkflowValidate.parse(["--file", workflowURL.path, "--pretty"])
        let output = try await cmd.execute(fileManager: FileManager.default)

        #expect(output.contains("\"valid\" : false"))
        #expect(output.contains("malformed placeholder syntax"))
    }

    @Test func `validate reports structural errors`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-workflow-invalid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workflowURL = tempDir.appendingPathComponent("workflow.json")
        try """
        {
          "invalid": true
        }
        """.data(using: .utf8)!.write(to: workflowURL)

        let cmd = try WorkflowValidate.parse(["--file", workflowURL.path, "--pretty"])
        let output = try await cmd.execute(fileManager: FileManager.default)

        #expect(output.contains("\"valid\" : false"))
        #expect(output.contains("\"workflows\""))
    }

    @Test func `run plans commands and substitutes parameters`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-workflow-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workflowURL = tempDir.appendingPathComponent("workflow.json")
        try """
        {
          "workflows": {
            "release": {
              "steps": [
                "echo X:version",
                { "name": "package", "run": "echo X:artifact" }
              ]
            }
          }
        }
        """.data(using: .utf8)!.write(to: workflowURL)

        let cmd = try WorkflowRun.parse([
            "--file", workflowURL.path,
            "--dry-run",
            "release",
            "version:1.2.3",
            "artifact:ipa",
            "--pretty"
        ])
        let output = try await cmd.execute(fileManager: FileManager.default)

        #expect(output.contains("\"status\" : \"dry-run\""))
        #expect(output.contains("\"stepsExecuted\" : 2"))
        #expect(output.contains("echo 1.2.3"))
        #expect(output.contains("echo ipa"))
    }

    @Test func `run help language stays preview oriented`() {
        #expect(WorkflowRun.configuration.abstract == "Preview a workflow plan from file with validated substitutions")
    }

    @Test func `run rejects malformed override tokens`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-workflow-run-bad-override-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workflowURL = tempDir.appendingPathComponent("workflow.json")
        try """
        {
          "workflows": {
            "release": {
              "steps": [
                "echo X:version"
              ]
            }
          }
        }
        """.data(using: .utf8)!.write(to: workflowURL)

        let cmd = try WorkflowRun.parse([
            "--file", workflowURL.path,
            "--dry-run",
            "release",
            "version",
            "--pretty"
        ])

        do {
            _ = try await cmd.execute(fileManager: FileManager.default)
            Issue.record("Expected ValidationError")
        } catch let error as ValidationError {
            #expect(error.message.contains("key:value form"))
        }
        catch {
            Issue.record("Expected ValidationError, got \(error)")
        }
    }

    @Test func `run rejects malformed placeholder syntax before planning`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-workflow-run-bad-placeholder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workflowURL = tempDir.appendingPathComponent("workflow.json")
        try """
        {
          "workflows": {
            "release": {
              "steps": [
                "echo X:"
              ]
            }
          }
        }
        """.data(using: .utf8)!.write(to: workflowURL)

        let cmd = try WorkflowRun.parse([
            "--file", workflowURL.path,
            "release",
            "--pretty"
        ])

        do {
            _ = try await cmd.execute(fileManager: FileManager.default)
            Issue.record("Expected ValidationError")
        } catch let error as ValidationError {
            #expect(error.message.contains("malformed placeholder syntax"))
        }
        catch {
            Issue.record("Expected ValidationError, got \(error)")
        }
    }
}
