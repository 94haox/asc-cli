import ArgumentParser
import Foundation
import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct PublishCompatibilityTests {

    @Test func `testflight confirms upload and attaches the beta group after build resolution`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let ipaURL = tempDir.appendingPathComponent("sample.ipa")
        try Data("ipa".utf8).write(to: ipaURL)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let uploadRepo = MockBuildUploadRepository()
        let buildRepo = MockBuildRepository()
        let testFlightRepo = MockTestFlightRepository()

        given(uploadRepo).uploadBuild(
            appId: .value("app-77"),
            version: .value("1.2.3"),
            buildNumber: .value("42"),
            platform: .value(.iOS),
            fileURL: .any
        ).willReturn(
            BuildUpload(
                id: "upload-1",
                appId: "app-77",
                version: "1.2.3",
                buildNumber: "42",
                platform: .iOS,
                state: .complete
            )
        )
        given(buildRepo).listBuilds(appId: .value("app-77"), platform: .value(.iOS), version: .value("1.2.3"), limit: .any).willReturn(
            PaginatedResponse(
                data: [
                    Build(
                        id: "build-1",
                        version: "1.2.3",
                        expired: false,
                        processingState: .valid,
                        buildNumber: "42",
                        platform: .iOS
                    )
                ]
            )
        )
        given(testFlightRepo).listBetaGroups(appId: .value("app-77"), limit: .any).willReturn(
            PaginatedResponse(
                data: [
                    BetaGroup(id: "beta-team", appId: "app-77", name: "Beta Team")
                ]
            )
        )
        given(buildRepo).addBetaGroups(buildId: .value("build-1"), betaGroupIds: .value(["beta-team"])).willReturn()

        let cmd = try PublishTestFlight.parse([
            "--app", "app-77",
            "--ipa", ipaURL.path,
            "--group", "beta-team",
            "--version", "1.2.3",
            "--build-number", "42",
            "--platform", "ios",
            "--wait",
            "--confirm",
            "--pretty"
        ])

        let output = try await cmd.execute(
            uploadRepo: uploadRepo,
            buildRepo: buildRepo,
            testFlightRepo: testFlightRepo
        )

        #expect(output.contains("\"appId\" : \"app-77\""))
        #expect(output.contains("\"group\" : \"beta-team\""))
        #expect(output.contains("\"mode\" : \"applied\""))
        #expect(output.contains("\"wait\" : true"))
        #expect(output.contains("Resolved build build-1"))
        #expect(output.contains("Added build build-1 to beta group beta-team"))
    }

    @Test func `appstore confirms upload and submits the linked version`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let ipaURL = tempDir.appendingPathComponent("sample.ipa")
        try Data("ipa".utf8).write(to: ipaURL)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let uploadRepo = MockBuildUploadRepository()
        let buildRepo = MockBuildRepository()
        let versionRepo = MockVersionRepository()
        let submissionRepo = MockSubmissionRepository()

        given(uploadRepo).uploadBuild(
            appId: .value("app-77"),
            version: .value("1.2.3"),
            buildNumber: .value("42"),
            platform: .value(.iOS),
            fileURL: .any
        ).willReturn(
            BuildUpload(
                id: "upload-2",
                appId: "app-77",
                version: "1.2.3",
                buildNumber: "42",
                platform: .iOS,
                state: .complete
            )
        )
        given(buildRepo).listBuilds(appId: .value("app-77"), platform: .value(.iOS), version: .value("1.2.3"), limit: .any).willReturn(
            PaginatedResponse(
                data: [
                    Build(
                        id: "build-2",
                        version: "1.2.3",
                        expired: false,
                        processingState: .valid,
                        buildNumber: "42",
                        platform: .iOS
                    )
                ]
            )
        )
        given(versionRepo).listVersions(appId: .value("app-77")).willReturn([
            AppStoreVersion(
                id: "v-77",
                appId: "app-77",
                versionString: "1.2.3",
                platform: .iOS,
                state: .prepareForSubmission,
                buildId: nil
            )
        ])
        given(versionRepo).setBuild(versionId: .value("v-77"), buildId: .value("build-2")).willReturn()
        given(submissionRepo).submitVersion(versionId: .value("v-77")).willReturn(
            ReviewSubmission(
                id: "sub-77",
                appId: "app-77",
                appStoreVersionId: "v-77",
                platform: .iOS,
                state: .waitingForReview
            )
        )

        let cmd = try PublishAppStore.parse([
            "--app", "app-77",
            "--ipa", ipaURL.path,
            "--version", "1.2.3",
            "--build-number", "42",
            "--platform", "ios",
            "--submit",
            "--confirm",
            "--wait",
            "--pretty"
        ])

        let output = try await cmd.execute(
            uploadRepo: uploadRepo,
            buildRepo: buildRepo,
            versionRepo: versionRepo,
            submissionRepo: submissionRepo
        )

        #expect(output.contains("\"mode\" : \"applied\""))
        #expect(output.contains("\"submit\" : true"))
        #expect(output.contains("\"wait\" : true"))
        #expect(output.contains("Resolved build build-2"))
        #expect(output.contains("Linked build build-2 to version v-77"))
    }
}
