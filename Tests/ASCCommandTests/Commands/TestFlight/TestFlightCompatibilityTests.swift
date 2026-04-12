import Foundation
import ArgumentParser
import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct TestFlightPreReleaseCompatibilityTests {

    @Test func `pre-release create rejects dead token option`() {
        let cmd = try? TestFlightPreReleaseCreate.parse([
            "--build-id", "build-1",
            "--token", "legacy",
        ])

        #expect(cmd == nil)
    }

    @Test func `pre-release create attaches groups and reports follow-up hint`() async throws {
        let buildRepo = MockBuildRepository()
        given(buildRepo).getBuild(id: .any).willReturn(
            Build(id: "build-1", version: "1.0", expired: false, processingState: .valid, buildNumber: "42")
        )
        given(buildRepo).addBetaGroups(buildId: .any, betaGroupIds: .any).willReturn()

        let cmd = try TestFlightPreReleaseCreate.parse([
            "--app-id", "app-1",
            "--build-id", "build-1",
            "--group-id", "group-1",
            "--group-id", "group-2",
            "--pretty",
        ])
        let output = try await cmd.execute(buildRepo: buildRepo)
        let normalized = output.replacingOccurrences(of: "\\/", with: "/")

        #expect(normalized.contains("\"buildId\" : \"build-1\""))
        #expect(normalized.contains("\"groupIds\" : ["))
        #expect(normalized.contains("\"nextHint\""))
    }

    @Test func `pre-release create resolves the latest build deterministically by version`() async throws {
        let buildRepo = MockBuildRepository()
        given(buildRepo).listBuilds(appId: .any, platform: .any, version: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                Build(
                    id: "build-1",
                    version: "1.0",
                    uploadedDate: Date(timeIntervalSince1970: 1_700_000_000),
                    expired: false,
                    processingState: .valid,
                    buildNumber: "42"
                ),
                Build(
                    id: "build-2",
                    version: "1.0",
                    uploadedDate: Date(timeIntervalSince1970: 1_700_000_060),
                    expired: false,
                    processingState: .valid,
                    buildNumber: "42"
                ),
            ])
        )
        given(buildRepo).addBetaGroups(buildId: .any, betaGroupIds: .any).willReturn()

        let cmd = try TestFlightPreReleaseCreate.parse([
            "--app-id", "app-1",
            "--version", "1.0",
            "--group-id", "group-1",
            "--pretty",
        ])
        let output = try await cmd.execute(buildRepo: buildRepo)

        #expect(output.contains("\"buildId\" : \"build-2\""))
        #expect(output.contains("\"buildNumber\" : \"42\""))
    }

    @Test func `pre-release status returns build processing state`() async throws {
        let buildRepo = MockBuildRepository()
        given(buildRepo).getBuild(id: .any).willReturn(
            Build(id: "build-2", version: "1.0.1", expired: true, processingState: .processing, buildNumber: "43")
        )

        let cmd = try TestFlightPreReleaseStatus.parse(["--build-id", "build-2", "--pretty"])
        let output = try await cmd.execute(buildRepo: buildRepo)

        #expect(output.contains("\"processingState\" : \"PROCESSING\""))
        #expect(output.contains("\"expired\" : true"))
    }

    @Test func `feedback list resolves the latest comment deterministically`() async throws {
        let buildRepo = MockBuildRepository()
        given(buildRepo).listBuilds(appId: .any, platform: .any, version: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                Build(id: "build-1", version: "1.0", expired: false, processingState: .valid, buildNumber: "101"),
            ])
        )
        let feedbackRepo = MockTestFlightFeedbackRepository()
        given(feedbackRepo).listScreenshotSubmissions(appId: .any, buildId: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                TestFlightFeedbackSubmission(
                    id: "feedback-undated",
                    buildId: "build-1",
                    createdDate: nil,
                    comment: "Undated feedback"
                ),
                TestFlightFeedbackSubmission(
                    id: "feedback-old",
                    buildId: "build-1",
                    createdDate: Date(timeIntervalSince1970: 10),
                    comment: "Older feedback"
                ),
                TestFlightFeedbackSubmission(
                    id: "feedback-new-a",
                    buildId: "build-1",
                    createdDate: Date(timeIntervalSince1970: 20),
                    comment: "Newest feedback A"
                ),
                TestFlightFeedbackSubmission(
                    id: "feedback-new-b",
                    buildId: "build-1",
                    createdDate: Date(timeIntervalSince1970: 20),
                    comment: "Newest feedback B"
                ),
            ])
        )

        let cmd = try TestFlightFeedbackList.parse([
            "--app-id", "app-1",
            "--pretty",
        ])
        let output = try await cmd.execute(buildRepo: buildRepo, feedbackRepo: feedbackRepo)

        #expect(output == """
        {
          "appId" : "app-1",
          "items" : [
            {
              "buildId" : "build-1",
              "buildNumber" : "101",
              "feedbackCount" : 4,
              "latestComment" : "Newest feedback B",
              "version" : "1.0",
              "visibility" : "visible"
            }
          ]
        }
        """)
    }
}

@Suite
struct TestFlightFeedbackCompatibilityTests {

    @Test func `feedback list summarizes builds with real submission counts`() async throws {
        let buildRepo = MockBuildRepository()
        given(buildRepo).listBuilds(appId: .any, platform: .any, version: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                Build(id: "build-1", version: "1.0", expired: false, processingState: .valid, buildNumber: "101"),
            ])
        )
        let feedbackRepo = MockTestFlightFeedbackRepository()
        given(feedbackRepo).listScreenshotSubmissions(appId: .any, buildId: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                TestFlightFeedbackSubmission(
                    id: "feedback-1",
                    buildId: "build-1",
                    createdDate: Date(timeIntervalSince1970: 10),
                    comment: "Older feedback"
                ),
                TestFlightFeedbackSubmission(
                    id: "feedback-2",
                    buildId: "build-1",
                    createdDate: Date(timeIntervalSince1970: 20),
                    comment: "Newest feedback"
                ),
            ])
        )

        let cmd = try TestFlightFeedbackList.parse(["--app-id", "app-1", "--pretty"])
        let output = try await cmd.execute(buildRepo: buildRepo, feedbackRepo: feedbackRepo)

        #expect(output == """
        {
          "appId" : "app-1",
          "items" : [
            {
              "buildId" : "build-1",
              "buildNumber" : "101",
              "feedbackCount" : 2,
              "latestComment" : "Newest feedback",
              "version" : "1.0",
              "visibility" : "visible"
            }
          ]
        }
        """)
    }

    @Test func `feedback export writes the real summary to disk`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-testflight-feedback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputPath = tempDir.appendingPathComponent("feedback.json").path

        let buildRepo = MockBuildRepository()
        given(buildRepo).listBuilds(appId: .any, platform: .any, version: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                Build(id: "build-1", version: "1.0", expired: false, processingState: .valid, buildNumber: "101"),
            ])
        )
        let feedbackRepo = MockTestFlightFeedbackRepository()
        given(feedbackRepo).listScreenshotSubmissions(appId: .any, buildId: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                TestFlightFeedbackSubmission(
                    id: "feedback-1",
                    buildId: "build-1",
                    createdDate: Date(timeIntervalSince1970: 10),
                    comment: "Only feedback"
                ),
            ])
        )

        let cmd = try TestFlightFeedbackExport.parse([
            "--app-id", "app-1",
            "--output", outputPath,
            "--pretty",
        ])
        _ = try await cmd.execute(buildRepo: buildRepo, feedbackRepo: feedbackRepo)

        let fileContents = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(fileContents == """
        {
          "appId" : "app-1",
          "items" : [
            {
              "buildId" : "build-1",
              "buildNumber" : "101",
              "feedbackCount" : 1,
              "latestComment" : "Only feedback",
              "version" : "1.0",
              "visibility" : "visible"
            }
          ]
        }
        """)
    }
}

@Suite
struct TestFlightCrashCompatibilityTests {

    @Test func `crashes list filters undated submissions and resolves latest comment deterministically`() async throws {
        let buildRepo = MockBuildRepository()
        given(buildRepo).listBuilds(appId: .any, platform: .any, version: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                Build(id: "build-1", version: "1.0", expired: false, processingState: .valid, buildNumber: "101"),
            ])
        )
        let feedbackRepo = MockTestFlightFeedbackRepository()
        given(feedbackRepo).listCrashSubmissions(appId: .any, buildId: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                TestFlightCrashSubmission(
                    id: "crash-undated",
                    buildId: "build-1",
                    createdDate: nil,
                    comment: "Undated crash",
                    hasCrashLog: true
                ),
                TestFlightCrashSubmission(
                    id: "crash-old",
                    buildId: "build-1",
                    createdDate: Date(timeIntervalSince1970: 10),
                    comment: "Older crash",
                    hasCrashLog: false
                ),
                TestFlightCrashSubmission(
                    id: "crash-new-a",
                    buildId: "build-1",
                    createdDate: Date(timeIntervalSince1970: 20),
                    comment: "Newest crash A",
                    hasCrashLog: false
                ),
                TestFlightCrashSubmission(
                    id: "crash-new-b",
                    buildId: "build-1",
                    createdDate: Date(timeIntervalSince1970: 20),
                    comment: "Newest crash B",
                    hasCrashLog: true
                ),
            ])
        )

        let cmd = try TestFlightCrashesList.parse([
            "--app-id", "app-1",
            "--since", "1970-01-01T00:00:15Z",
            "--pretty",
        ])
        let output = try await cmd.execute(buildRepo: buildRepo, feedbackRepo: feedbackRepo)

        #expect(output == """
        {
          "appId" : "app-1",
          "items" : [
            {
              "buildId" : "build-1",
              "buildNumber" : "101",
              "crashCount" : 2,
              "hasCrashLog" : true,
              "latestComment" : "Newest crash B",
              "version" : "1.0",
              "visibility" : "visible"
            }
          ]
        }
        """)
    }

    @Test func `crashes export writes the real summary to disk`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-testflight-crashes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputPath = tempDir.appendingPathComponent("crashes.json").path

        let buildRepo = MockBuildRepository()
        given(buildRepo).listBuilds(appId: .any, platform: .any, version: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                Build(id: "build-1", version: "1.0", expired: false, processingState: .valid, buildNumber: "101"),
            ])
        )
        let feedbackRepo = MockTestFlightFeedbackRepository()
        given(feedbackRepo).listCrashSubmissions(appId: .any, buildId: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                TestFlightCrashSubmission(
                    id: "crash-1",
                    buildId: "build-1",
                    createdDate: Date(timeIntervalSince1970: 10),
                    comment: "Only crash",
                    hasCrashLog: true
                ),
            ])
        )

        let cmd = try TestFlightCrashesExport.parse([
            "--app-id", "app-1",
            "--output", outputPath,
            "--pretty",
        ])
        _ = try await cmd.execute(buildRepo: buildRepo, feedbackRepo: feedbackRepo)

        let fileContents = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(fileContents == """
        {
          "appId" : "app-1",
          "items" : [
            {
              "buildId" : "build-1",
              "buildNumber" : "101",
              "crashCount" : 1,
              "hasCrashLog" : true,
              "latestComment" : "Only crash",
              "version" : "1.0",
              "visibility" : "visible"
            }
          ]
        }
        """)
    }
}

@Suite
struct TestFlightConfigCompatibilityTests {

    @Test func `config export writes a snapshot file`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-testflight-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputPath = tempDir.appendingPathComponent("testflight-config.json").path

        let testFlightRepo = MockTestFlightRepository()
        given(testFlightRepo).listBetaGroups(appId: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                BetaGroup(id: "group-1", appId: "app-1", name: "External Testers", isInternalGroup: false),
            ])
        )
        given(testFlightRepo).listBetaTesters(groupId: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                BetaTester(id: "tester-1", groupId: "group-1", firstName: "Jane", lastName: "Doe", email: "jane@example.com"),
            ])
        )
        let buildRepo = MockBuildRepository()
        given(buildRepo).listBuilds(appId: .any, platform: .any, version: .any, limit: .any).willReturn(
            PaginatedResponse(data: [])
        )

        let cmd = try TestFlightConfigExport.parse([
            "--app-id", "app-1",
            "--output", outputPath,
            "--include-testers",
            "--pretty",
        ])
        _ = try await cmd.execute(testFlightRepo: testFlightRepo, buildRepo: buildRepo)

        let fileContents = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(fileContents.contains("External Testers"))
        #expect(fileContents.contains("jane@example.com"))
    }

    @Test func `config import dry run reports planned changes`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-testflight-config-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let inputPath = tempDir.appendingPathComponent("testflight-config.json").path
        try """
        {
          "appId": "app-1",
          "groups": [
            {
              "id": "group-1",
              "name": "External Testers",
              "testers": [
                {
                  "email": "jane@example.com",
                  "firstName": "Jane",
                  "lastName": "Doe"
                }
              ]
            }
          ]
        }
        """.write(toFile: inputPath, atomically: true, encoding: .utf8)

        let testFlightRepo = MockTestFlightRepository()
        given(testFlightRepo).listBetaGroups(appId: .any, limit: .any).willReturn(PaginatedResponse(data: []))
        given(testFlightRepo).listBetaTesters(groupId: .any, limit: .any).willReturn(PaginatedResponse(data: []))

        let cmd = try TestFlightConfigImport.parse([
            "--app-id", "app-1",
            "--input", inputPath,
            "--dry-run",
            "--pretty",
        ])
        let output = try await cmd.execute(testFlightRepo: testFlightRepo)

        #expect(output.contains("\"dryRun\" : true"))
        #expect(output.contains("\"plannedGroups\""))
    }
}
