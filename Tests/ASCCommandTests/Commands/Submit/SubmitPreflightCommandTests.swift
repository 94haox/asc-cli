import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct SubmitPreflightCommandTests {
    @Test func `preflight returns ready when readiness passes`() async throws {
        let versionRepo = MockVersionRepository()
        let appRepo = MockAppRepository()
        let buildRepo = MockBuildRepository()
        let reviewDetailRepo = MockReviewDetailRepository()
        let localizationRepo = MockVersionLocalizationRepository()
        let screenshotRepo = MockScreenshotRepository()
        let pricingRepo = MockPricingRepository()
        let projectStorage = MockProjectConfigStorage()

        given(versionRepo).listVersions(appId: .value("app-456")).willReturn([
            AppStoreVersion(id: "v-123", appId: "app-456", versionString: "1.2.3", platform: .iOS, state: .prepareForSubmission, buildId: "build-1"),
        ])
        given(appRepo).getApp(id: .value("app-456")).willReturn(
            App(id: "app-456", name: "My App", bundleId: "com.example.app", primaryLocale: "en-US")
        )
        given(buildRepo).getBuild(id: .value("build-1")).willReturn(
            Build(id: "build-1", version: "1.2.3", expired: false, processingState: .valid, buildNumber: "55")
        )
        given(reviewDetailRepo).getReviewDetail(versionId: .value("v-123")).willReturn(
            AppStoreReviewDetail(id: "rd-1", versionId: "v-123", contactPhone: "123", contactEmail: "a@b.com", demoAccountRequired: false)
        )
        given(localizationRepo).listLocalizations(versionId: .value("v-123")).willReturn([
            AppStoreVersionLocalization(
                id: "loc-1",
                versionId: "v-123",
                locale: "en-US",
                description: "desc",
                keywords: "k"
            ),
        ])
        given(screenshotRepo).listScreenshotSets(localizationId: .value("loc-1")).willReturn([
            AppScreenshotSet(id: "set-1", localizationId: "loc-1", screenshotDisplayType: .iphone67, screenshotsCount: 1),
        ])
        given(pricingRepo).hasPricing(appId: .value("app-456")).willReturn(true)

        let cmd = try SubmitPreflightCommand.parse(["--app", "app-456", "--version", "1.2.3", "--pretty"])
        let output = try await cmd.execute(
            versionRepo: versionRepo,
            appRepo: appRepo,
            buildRepo: buildRepo,
            reviewDetailRepo: reviewDetailRepo,
            localizationRepo: localizationRepo,
            screenshotRepo: screenshotRepo,
            pricingRepo: pricingRepo,
            projectStorage: projectStorage
        )

        #expect(output.contains("\"command\" : \"submit preflight\""))
        #expect(output.contains("\"readinessStatus\" : \"ready\""))
        #expect(output.contains("\"resolvedVersionId\" : \"v-123\""))
    }
}
