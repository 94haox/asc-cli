import ArgumentParser
import Foundation
import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct SubmitCompatibilityTests {

    @Test func `preflight reports an eligible version when build and review data are ready`() async throws {
        let mockAppRepo = MockAppRepository()
        let mockVersionRepo = MockVersionRepository()
        let mockBuildRepo = MockBuildRepository()
        let mockReviewRepo = MockReviewDetailRepository()
        let mockLocalizationRepo = MockVersionLocalizationRepository()
        let mockScreenshotRepo = MockScreenshotRepository()
        let mockPricingRepo = MockPricingRepository()

        given(mockAppRepo).getApp(id: .value("app-123")).willReturn(App(
            id: "app-123",
            name: "Sample",
            bundleId: "com.example.sample",
            primaryLocale: "en-US"
        ))
        given(mockVersionRepo).listVersions(appId: .value("app-123")).willReturn([
            AppStoreVersion(
                id: "v-123",
                appId: "app-123",
                versionString: "1.2.3",
                platform: .iOS,
                state: .prepareForSubmission,
                buildId: "build-123"
            )
        ])
        given(mockBuildRepo).getBuild(id: .value("build-123")).willReturn(Build(
            id: "build-123",
            version: "1.2.3",
            expired: false,
            processingState: .valid,
            buildNumber: "123",
            platform: .iOS
        ))
        given(mockReviewRepo).getReviewDetail(versionId: .value("v-123")).willReturn(AppStoreReviewDetail(
            id: "rd-123",
            versionId: "v-123",
            contactPhone: "+1-555-0100",
            contactEmail: "review@example.com"
        ))
        given(mockLocalizationRepo).listLocalizations(versionId: .value("v-123")).willReturn([
            AppStoreVersionLocalization(
                id: "loc-1",
                versionId: "v-123",
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
        given(mockPricingRepo).hasPricing(appId: .value("app-123")).willReturn(true)

        let cmd = try SubmitPreflight.parse([
            "--app", "app-123",
            "--version", "1.2.3",
            "--platform", "ios",
            "--pretty"
        ])

        let output = try await cmd.execute(
            appRepo: mockAppRepo,
            versionRepo: mockVersionRepo,
            buildRepo: mockBuildRepo,
            reviewDetailRepo: mockReviewRepo,
            localizationRepo: mockLocalizationRepo,
            screenshotRepo: mockScreenshotRepo,
            pricingRepo: mockPricingRepo
        )

        #expect(output == """
        {
          "data" : [
            {
              "appId" : "app-123",
              "blockingIssues" : [

              ],
              "checks" : [
                {
                  "detail" : "Version is editable",
                  "name" : "state",
                  "status" : "pass"
                },
                {
                  "detail" : "Build 123 is linked and valid",
                  "name" : "build",
                  "status" : "pass"
                },
                {
                  "detail" : "Pricing is configured",
                  "name" : "pricing",
                  "status" : "pass"
                },
                {
                  "detail" : "Review contact is set",
                  "name" : "review-contact",
                  "status" : "pass"
                },
                {
                  "detail" : "Localization and screenshots are ready",
                  "name" : "localization",
                  "status" : "pass"
                }
              ],
              "eligible" : true,
              "id" : "v-123",
              "platform" : "IOS",
              "version" : "1.2.3",
              "versionId" : "v-123",
              "warnings" : [

              ]
            }
          ]
        }
        """)
    }

    @Test func `create links the build and submits the version after resolving identifiers`() async throws {
        let mockVersionRepo = MockVersionRepository()
        let mockBuildRepo = MockBuildRepository()
        let mockSubmissionRepo = MockSubmissionRepository()

        given(mockVersionRepo).listVersions(appId: .value("app-456")).willReturn([
            AppStoreVersion(
                id: "v-456",
                appId: "app-456",
                versionString: "2.0.0",
                platform: .iOS,
                state: .prepareForSubmission,
                buildId: nil
            )
        ])
        given(mockBuildRepo).getBuild(id: .value("build-456")).willReturn(Build(
            id: "build-456",
            version: "2.0.0",
            expired: false,
            processingState: .valid,
            buildNumber: "456",
            platform: .iOS
        ))
        given(mockVersionRepo).setBuild(versionId: .value("v-456"), buildId: .value("build-456")).willReturn()
        given(mockSubmissionRepo).submitVersion(versionId: .value("v-456")).willReturn(
            ReviewSubmission(
                id: "submission-1",
                appId: "app-456",
                platform: .iOS,
                state: .waitingForReview
            )
        )

        let cmd = try SubmitCreate.parse([
            "--app", "app-456",
            "--version", "2.0.0",
            "--build", "build-456",
            "--confirm",
            "--pretty"
        ])

        let output = try await cmd.execute(
            versionRepo: mockVersionRepo,
            buildRepo: mockBuildRepo,
            submissionRepo: mockSubmissionRepo
        )

        #expect(output.contains("\"submissionId\" : \"submission-1\""))
        #expect(output.contains("\"versionId\" : \"v-456\""))
        #expect(output.contains("\"buildId\" : \"build-456\""))
    }

    @Test func `status looks up submission by version id`() async throws {
        let mockVersionRepo = MockVersionRepository()
        let mockSubmissionRepo = MockSubmissionRepository()

        given(mockVersionRepo).getVersion(id: .value("v-123")).willReturn(
            AppStoreVersion(
                id: "v-123",
                appId: "app-123",
                versionString: "1.2.3",
                platform: .iOS,
                state: .prepareForSubmission,
                buildId: "build-123"
            )
        )
        given(mockSubmissionRepo).listSubmissions(appId: .value("app-123")).willReturn([
            ReviewSubmission(
                id: "sub-1",
                appId: "app-123",
                appStoreVersionId: "v-123",
                platform: .iOS,
                state: .waitingForReview
            )
        ])

        let cmd = try SubmitStatus.parse([
            "--version-id", "v-123",
            "--pretty"
        ])

        let output = try await cmd.execute(versionRepo: mockVersionRepo, submissionRepo: mockSubmissionRepo)
        #expect(output.contains("\"appStoreVersionId\" : \"v-123\""))
        #expect(output.contains("\"state\" : \"WAITING_FOR_REVIEW\""))
    }

    @Test func `cancel returns updated submission state`() async throws {
        let mockSubmissionRepo = MockSubmissionRepository()

        given(mockSubmissionRepo).cancelSubmission(id: .value("sub-1")).willReturn(
            ReviewSubmission(
                id: "sub-1",
                appId: "app-123",
                appStoreVersionId: "v-123",
                platform: .iOS,
                state: .canceling
            )
        )

        let cmd = try SubmitCancel.parse([
            "--id", "sub-1",
            "--confirm",
            "--pretty"
        ])

        let output = try await cmd.execute(submissionRepo: mockSubmissionRepo)
        #expect(output.contains("\"state\" : \"CANCELING\""))
        #expect(output.contains("\"appStoreVersionId\" : \"v-123\""))
    }
}
