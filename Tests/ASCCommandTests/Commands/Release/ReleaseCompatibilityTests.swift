import ArgumentParser
import Foundation
import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct ReleaseCompatibilityTests {

    @Test func `stage confirms and copies metadata into the target directory`() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDir = tempRoot.appendingPathComponent("source")
        let targetDir = tempRoot.appendingPathComponent("target")
        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let sourceFile = sourceDir.appendingPathComponent("metadata.json")
        try Data(#"{"version":"4.0.0"}"#.utf8).write(to: sourceFile)

        let cmd = try ReleaseStage.parse([
            "--app", "app-1",
            "--version", "4.0.0",
            "--metadata-dir", targetDir.path,
            "--copy-metadata-from", sourceDir.path,
            "--confirm",
            "--pretty"
        ])

        let output = try await cmd.execute()

        #expect(fileManager.fileExists(atPath: targetDir.appendingPathComponent("metadata.json").path))
        #expect(output.contains("\"mode\" : \"staged\""))
        #expect(output.contains("\"confirmed\" : true"))
        #expect(output.contains("\"appId\" : \"app-1\""))
    }

    @Test func `run executes validate submit and publish when not dry-run`() async throws {
        let mockAppRepo = MockAppRepository()
        let mockVersionRepo = MockVersionRepository()
        let mockBuildRepo = MockBuildRepository()
        let mockReviewRepo = MockReviewDetailRepository()
        let mockLocalizationRepo = MockVersionLocalizationRepository()
        let mockScreenshotRepo = MockScreenshotRepository()
        let mockPricingRepo = MockPricingRepository()
        let mockSubmissionRepo = MockSubmissionRepository()

        given(mockAppRepo).getApp(id: .value("app-1")).willReturn(
            App(
                id: "app-1",
                name: "Sample",
                bundleId: "com.example.sample",
                primaryLocale: "en-US"
            )
        )
        given(mockVersionRepo).listVersions(appId: .value("app-1")).willReturn([
            AppStoreVersion(
                id: "v-1",
                appId: "app-1",
                versionString: "4.0.0",
                platform: .iOS,
                state: .prepareForSubmission,
                buildId: "build-1"
            )
        ])
        given(mockBuildRepo).getBuild(id: .value("build-1")).willReturn(
            Build(
                id: "build-1",
                version: "4.0.0",
                expired: false,
                processingState: .valid,
                buildNumber: "42",
                platform: .iOS
            )
        )
        given(mockReviewRepo).getReviewDetail(versionId: .value("v-1")).willReturn(
            AppStoreReviewDetail(
                id: "rd-1",
                versionId: "v-1",
                contactPhone: "+1-555-0100",
                contactEmail: "review@example.com"
            )
        )
        given(mockLocalizationRepo).listLocalizations(versionId: .value("v-1")).willReturn([
            AppStoreVersionLocalization(
                id: "loc-1",
                versionId: "v-1",
                locale: "en-US",
                description: "Description",
                keywords: "sample"
            )
        ])
        given(mockScreenshotRepo).listScreenshotSets(localizationId: .value("loc-1")).willReturn([
            AppScreenshotSet(
                id: "set-1",
                localizationId: "loc-1",
                screenshotDisplayType: .iphone67,
                screenshotsCount: 3
            )
        ])
        given(mockPricingRepo).hasPricing(appId: .value("app-1")).willReturn(true)
        given(mockSubmissionRepo).submitVersion(versionId: .value("v-1")).willReturn(
            ReviewSubmission(
                id: "sub-1",
                appId: "app-1",
                appStoreVersionId: "v-1",
                platform: .iOS,
                state: .waitingForReview
            )
        )

        let cmd = try ReleaseRun.parse([
            "--app", "app-1",
            "--version", "4.0.0",
            "--validate",
            "--submit",
            "--publish",
            "--pretty"
        ])

        let output = try await cmd.execute(
            versionRepo: mockVersionRepo,
            buildRepo: mockBuildRepo,
            appRepo: mockAppRepo,
            reviewDetailRepo: mockReviewRepo,
            localizationRepo: mockLocalizationRepo,
            screenshotRepo: mockScreenshotRepo,
            pricingRepo: mockPricingRepo,
            submissionRepo: mockSubmissionRepo
        )

        #expect(output.contains("\"mode\" : \"applied\""))
        #expect(output.contains("\"validate\" : true"))
        #expect(output.contains("\"submit\" : true"))
        #expect(output.contains("\"publish\" : true"))
        #expect(output.contains("\"version\" : \"4.0.0\""))
    }
}
