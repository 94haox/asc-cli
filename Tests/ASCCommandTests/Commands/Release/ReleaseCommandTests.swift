import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct ReleaseCommandTests {
    @Test func `release stage is blocked when readiness fails`() async throws {
        let versionRepo = MockVersionRepository()
        let appRepo = MockAppRepository()
        let buildRepo = MockBuildRepository()
        let reviewDetailRepo = MockReviewDetailRepository()
        let localizationRepo = MockVersionLocalizationRepository()
        let screenshotRepo = MockScreenshotRepository()
        let pricingRepo = MockPricingRepository()
        let projectStorage = MockProjectConfigStorage()

        given(versionRepo).listVersions(appId: .value("app-456")).willReturn([
            AppStoreVersion(id: "v-123", appId: "app-456", versionString: "1.2.3", platform: .iOS, state: .prepareForSubmission, buildId: nil),
        ])
        given(appRepo).getApp(id: .value("app-456")).willReturn(
            App(id: "app-456", name: "My App", bundleId: "com.example.app", primaryLocale: "en-US")
        )
        given(reviewDetailRepo).getReviewDetail(versionId: .value("v-123")).willReturn(
            AppStoreReviewDetail(id: "rd-1", versionId: "v-123", contactPhone: "123", contactEmail: "a@b.com", demoAccountRequired: false)
        )
        given(localizationRepo).listLocalizations(versionId: .value("v-123")).willReturn([])
        given(pricingRepo).hasPricing(appId: .value("app-456")).willReturn(false)

        let cmd = try ReleaseStageCommand.parse(["--app", "app-456", "--version", "1.2.3", "--build", "55", "--pretty"])
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

        #expect(output.contains("\"status\" : \"blocked_not_ready\""))
        #expect(output.contains("\"resolvedVersionId\" : \"v-123\""))
    }
}
