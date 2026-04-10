import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct ValidateCommandTests {
    @Test func `validate resolves by version-id`() async throws {
        let versionRepo = MockVersionRepository()
        let appRepo = MockAppRepository()
        let buildRepo = MockBuildRepository()
        let reviewDetailRepo = MockReviewDetailRepository()
        let localizationRepo = MockVersionLocalizationRepository()
        let screenshotRepo = MockScreenshotRepository()
        let pricingRepo = MockPricingRepository()
        let projectStorage = MockProjectConfigStorage()

        given(versionRepo).getVersion(id: .value("v-123")).willReturn(
            AppStoreVersion(
                id: "v-123",
                appId: "app-456",
                versionString: "1.2.3",
                platform: .iOS,
                state: .prepareForSubmission,
                buildId: nil
            )
        )
        given(appRepo).getApp(id: .value("app-456")).willReturn(
            App(id: "app-456", name: "My App", bundleId: "com.example.app", primaryLocale: "en-US")
        )
        given(reviewDetailRepo).getReviewDetail(versionId: .value("v-123")).willReturn(
            AppStoreReviewDetail(id: "rd-1", versionId: "v-123", contactPhone: "123", contactEmail: "a@b.com", demoAccountRequired: false)
        )
        given(localizationRepo).listLocalizations(versionId: .value("v-123")).willReturn([])
        given(pricingRepo).hasPricing(appId: .value("app-456")).willReturn(true)

        let cmd = try ValidateCommand.parse(["--version-id", "v-123"])
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

        #expect(output.contains("\"resolvedVersionId\":\"v-123\""))
        #expect(output.contains("\"command\":\"validate\""))
    }

    @Test func `validate resolves app from project config when app option missing`() async throws {
        let versionRepo = MockVersionRepository()
        let appRepo = MockAppRepository()
        let buildRepo = MockBuildRepository()
        let reviewDetailRepo = MockReviewDetailRepository()
        let localizationRepo = MockVersionLocalizationRepository()
        let screenshotRepo = MockScreenshotRepository()
        let pricingRepo = MockPricingRepository()
        let projectStorage = MockProjectConfigStorage()

        given(projectStorage).load().willReturn(
            ProjectConfig(appId: "app-456", appName: "My App", bundleId: "com.example.app")
        )
        given(versionRepo).listVersions(appId: .value("app-456")).willReturn([
            AppStoreVersion(
                id: "v-123",
                appId: "app-456",
                versionString: "1.2.3",
                platform: .iOS,
                state: .prepareForSubmission,
                buildId: nil
            ),
        ])
        given(appRepo).getApp(id: .value("app-456")).willReturn(
            App(id: "app-456", name: "My App", bundleId: "com.example.app", primaryLocale: "en-US")
        )
        given(reviewDetailRepo).getReviewDetail(versionId: .value("v-123")).willReturn(
            AppStoreReviewDetail(id: "rd-1", versionId: "v-123", contactPhone: "123", contactEmail: "a@b.com", demoAccountRequired: false)
        )
        given(localizationRepo).listLocalizations(versionId: .value("v-123")).willReturn([])
        given(pricingRepo).hasPricing(appId: .value("app-456")).willReturn(true)

        let cmd = try ValidateCommand.parse(["--version", "1.2.3"])
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

        #expect(output.contains("\"appId\":\"app-456\""))
        #expect(output.contains("\"requestedVersion\":\"1.2.3\""))
    }

    @Test func `validate filters by platform when multiple versions share string`() async throws {
        let versionRepo = MockVersionRepository()
        let appRepo = MockAppRepository()
        let buildRepo = MockBuildRepository()
        let reviewDetailRepo = MockReviewDetailRepository()
        let localizationRepo = MockVersionLocalizationRepository()
        let screenshotRepo = MockScreenshotRepository()
        let pricingRepo = MockPricingRepository()
        let projectStorage = MockProjectConfigStorage()

        given(versionRepo).listVersions(appId: .value("app-456")).willReturn([
            AppStoreVersion(id: "v-ios", appId: "app-456", versionString: "1.2.3", platform: .iOS, state: .prepareForSubmission, buildId: nil),
            AppStoreVersion(id: "v-mac", appId: "app-456", versionString: "1.2.3", platform: .macOS, state: .prepareForSubmission, buildId: nil),
        ])
        given(appRepo).getApp(id: .value("app-456")).willReturn(
            App(id: "app-456", name: "My App", bundleId: "com.example.app", primaryLocale: "en-US")
        )
        given(reviewDetailRepo).getReviewDetail(versionId: .value("v-mac")).willReturn(
            AppStoreReviewDetail(id: "rd-1", versionId: "v-mac", contactPhone: "123", contactEmail: "a@b.com", demoAccountRequired: false)
        )
        given(localizationRepo).listLocalizations(versionId: .value("v-mac")).willReturn([])
        given(pricingRepo).hasPricing(appId: .value("app-456")).willReturn(true)

        let cmd = try ValidateCommand.parse(["--app", "app-456", "--version", "1.2.3", "--platform", "macos"])
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

        #expect(output.contains("\"resolvedVersionId\":\"v-mac\""))
    }
}
