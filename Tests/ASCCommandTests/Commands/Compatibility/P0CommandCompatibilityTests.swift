import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct P0ValidateCompatibilityTests {
    @Test func `validate root emits readiness envelope`() async throws {
        let versionRepo = MockVersionRepository()
        let appRepo = MockAppRepository()
        let buildRepo = MockBuildRepository()
        let reviewDetailRepo = MockReviewDetailRepository()
        let localizationRepo = MockVersionLocalizationRepository()
        let screenshotRepo = MockScreenshotRepository()
        let pricingRepo = MockPricingRepository()
        let projectStorage = MockProjectConfigStorage()

        given(versionRepo).listVersions(appId: .value("123")).willReturn([
            AppStoreVersion(
                id: "v-1",
                appId: "123",
                versionString: "1.2.3",
                platform: .iOS,
                state: .prepareForSubmission,
                buildId: nil
            ),
        ])
        given(appRepo).getApp(id: .value("123")).willReturn(App(id: "123", name: "App", bundleId: "com.example.app", primaryLocale: "en-US"))
        given(reviewDetailRepo).getReviewDetail(versionId: .value("v-1")).willReturn(
            AppStoreReviewDetail(id: "rd-1", versionId: "v-1", contactPhone: "123", contactEmail: "a@b.com", demoAccountRequired: false)
        )
        given(localizationRepo).listLocalizations(versionId: .value("v-1")).willReturn([])
        given(pricingRepo).hasPricing(appId: .value("123")).willReturn(true)

        let cmd = try ValidateCommand.parse(["--app", "123", "--version", "1.2.3", "--pretty"])
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

        #expect(output.contains("\"command\" : \"validate\""))
        #expect(output.contains("\"appId\" : \"123\""))
        #expect(output.contains("\"requestedVersion\" : \"1.2.3\""))
    }

    @Test func `validate iap emits category iap`() async throws {
        let cmd = try ValidateIAPCommand.parse(["--app", "123", "--pretty"])
        let output = try cmd.execute()

        #expect(output.contains("\"category\" : \"iap\""))
    }

    @Test func `validate subscriptions emits category subscriptions`() async throws {
        let cmd = try ValidateSubscriptionsCommand.parse(["--app", "123", "--pretty"])
        let output = try cmd.execute()

        #expect(output.contains("\"category\" : \"subscriptions\""))
    }
}

@Suite
struct P0WorkflowCompatibilityTests {
    @Test func `workflow list emits compatible command marker`() async throws {
        let cmd = try WorkflowListCommand.parse(["--pretty"])
        let output = try cmd.execute()

        #expect(output.contains("\"command\" : \"workflow list\""))
    }

    @Test func `workflow validate defaults to valid true for missing file`() async throws {
        let cmd = try WorkflowValidateCommand.parse([])
        let output = try cmd.execute(fileExists: { _ in false })

        #expect(output.contains("\"valid\":true"))
    }
}

@Suite
struct P0SubmitReleaseCompatibilityTests {
    @Test func `submit status supports version-id`() async throws {
        let cmd = try SubmitStatusCommand.parse(["--version-id", "ver-1", "--pretty"])
        let output = try cmd.execute()

        #expect(output.contains("\"command\" : \"submit status\""))
        #expect(output.contains("\"versionId\" : \"ver-1\""))
    }

    @Test func `release stage dry-run emits planned steps`() async throws {
        let cmd = try ReleaseStageCommand.parse([
            "--app", "123", "--version", "1.2.3", "--build", "456", "--dry-run", "--pretty",
        ])
        let output = try cmd.execute()

        #expect(output.contains("\"command\" : \"release stage\""))
        #expect(output.contains("\"dryRun\" : true"))
        #expect(output.contains("ensureVersion"))
    }
}
