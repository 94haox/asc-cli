import ArgumentParser
import Foundation
import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct ValidateCompatibilityTests {

    @Test func `app validation reports structured checks`() async throws {
        let mockAppRepo = MockAppRepository()
        let mockVersionRepo = MockVersionRepository()
        let mockBuildRepo = MockBuildRepository()
        let mockReviewRepo = MockReviewDetailRepository()
        let mockLocalizationRepo = MockVersionLocalizationRepository()
        let mockScreenshotRepo = MockScreenshotRepository()
        let mockPricingRepo = MockPricingRepository()

        given(mockAppRepo).getApp(id: .value("app-789")).willReturn(App(
            id: "app-789",
            name: "Validator",
            bundleId: "com.example.validator",
            primaryLocale: "en-US"
        ))
        given(mockVersionRepo).listVersions(appId: .value("app-789")).willReturn([
            AppStoreVersion(
                id: "v-789",
                appId: "app-789",
                versionString: "3.1.4",
                platform: .iOS,
                state: .prepareForSubmission,
                buildId: "build-789"
            )
        ])
        given(mockBuildRepo).getBuild(id: .value("build-789")).willReturn(Build(
            id: "build-789",
            version: "3.1.4",
            expired: false,
            processingState: .valid,
            buildNumber: "789",
            platform: .iOS
        ))
        given(mockReviewRepo).getReviewDetail(versionId: .value("v-789")).willReturn(AppStoreReviewDetail(
            id: "rd-789",
            versionId: "v-789",
            contactPhone: "+1-555-0100",
            contactEmail: "review@example.com"
        ))
        given(mockLocalizationRepo).listLocalizations(versionId: .value("v-789")).willReturn([])
        given(mockScreenshotRepo).listScreenshotSets(localizationId: .any).willReturn([])
        given(mockPricingRepo).hasPricing(appId: .value("app-789")).willReturn(true)

        let cmd = try ValidateApp.parse([
            "--app", "app-789",
            "--version", "3.1.4",
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

        #expect(output.contains("\"ok\" : true"))
        #expect(output.contains("\"versionId\" : \"v-789\""))
        #expect(output.contains("\"checks\" : ["))
    }

    @Test func `iap validation reports readiness and blockers`() async throws {
        let iapRepo = MockInAppPurchaseRepository()
        let priceRepo = MockInAppPurchasePriceRepository()
        let availabilityRepo = MockInAppPurchaseAvailabilityRepository()

        given(iapRepo).listInAppPurchases(appId: .value("app-1"), limit: .any).willReturn(
            PaginatedResponse(
                data: [
                    InAppPurchase(
                        id: "iap-ready",
                        appId: "app-1",
                        referenceName: "Coins",
                        productId: "coins",
                        type: .consumable,
                        state: .readyToSubmit
                    ),
                    InAppPurchase(
                        id: "iap-blocked",
                        appId: "app-1",
                        referenceName: "Gems",
                        productId: "gems",
                        type: .nonConsumable,
                        state: .missingMetadata
                    ),
                ]
            )
        )
        given(priceRepo).listPricePoints(iapId: .value("iap-ready"), territory: .value(nil)).willReturn([
            InAppPurchasePricePoint(id: "pp-1", iapId: "iap-ready", territory: "USA", customerPrice: "0.99", proceeds: "0.70"),
        ])
        given(priceRepo).listPricePoints(iapId: .value("iap-blocked"), territory: .value(nil)).willReturn([])
        given(availabilityRepo).getAvailability(iapId: .value("iap-ready")).willReturn(
            InAppPurchaseAvailability(
                id: "avail-1",
                iapId: "iap-ready",
                isAvailableInNewTerritories: true,
                territories: [Territory(id: "USA", currency: "USD")]
            )
        )
        given(availabilityRepo).getAvailability(iapId: .value("iap-blocked")).willReturn(
            InAppPurchaseAvailability(
                id: "avail-2",
                iapId: "iap-blocked",
                isAvailableInNewTerritories: false,
                territories: []
            )
        )

        let cmd = try ValidateIAP.parse([
            "--app", "app-1",
            "--pretty"
        ])

        let output = try await cmd.execute(
            inAppPurchaseRepo: iapRepo,
            priceRepo: priceRepo,
            availabilityRepo: availabilityRepo
        )

        #expect(output.contains("\"kind\" : \"iap\""))
        #expect(output.contains("\"totalItems\" : 2"))
        #expect(output.contains("\"validCount\" : 1"))
        #expect(output.contains("\"iap-ready\""))
        #expect(output.contains("\"iap-blocked\""))
        #expect(output.contains("\"issues\" : ["))
    }

    @Test func `subscriptions validation reports readiness and blockers`() async throws {
        let groupRepo = MockSubscriptionGroupRepository()
        let subscriptionRepo = MockSubscriptionRepository()
        let availabilityRepo = MockSubscriptionAvailabilityRepository()

        given(groupRepo).listSubscriptionGroups(appId: .value("app-1"), limit: .any).willReturn(
            PaginatedResponse(data: [
                SubscriptionGroup(id: "group-1", appId: "app-1", referenceName: "Premium"),
            ])
        )
        given(subscriptionRepo).listSubscriptions(groupId: .value("group-1"), limit: .any).willReturn(
            PaginatedResponse(
                data: [
                    Subscription(
                        id: "sub-ready",
                        groupId: "group-1",
                        name: "Monthly",
                        productId: "monthly",
                        subscriptionPeriod: .oneMonth,
                        state: .readyToSubmit
                    ),
                    Subscription(
                        id: "sub-blocked",
                        groupId: "group-1",
                        name: "Yearly",
                        productId: "yearly",
                        subscriptionPeriod: .oneYear,
                        state: .developerActionNeeded
                    ),
                ]
            )
        )
        given(availabilityRepo).getAvailability(subscriptionId: .value("sub-ready")).willReturn(
            SubscriptionAvailability(
                id: "s-avail-1",
                subscriptionId: "sub-ready",
                isAvailableInNewTerritories: true,
                territories: [Territory(id: "USA", currency: "USD")]
            )
        )
        given(availabilityRepo).getAvailability(subscriptionId: .value("sub-blocked")).willReturn(
            SubscriptionAvailability(
                id: "s-avail-2",
                subscriptionId: "sub-blocked",
                isAvailableInNewTerritories: false,
                territories: []
            )
        )

        let cmd = try ValidateSubscriptions.parse([
            "--app", "app-1",
            "--pretty"
        ])

        let output = try await cmd.execute(
            subscriptionGroupRepo: groupRepo,
            subscriptionRepo: subscriptionRepo,
            availabilityRepo: availabilityRepo
        )

        #expect(output.contains("\"kind\" : \"subscriptions\""))
        #expect(output.contains("\"totalItems\" : 2"))
        #expect(output.contains("\"validCount\" : 1"))
        #expect(output.contains("\"sub-ready\""))
        #expect(output.contains("\"sub-blocked\""))
        #expect(output.contains("\"issues\" : ["))
    }
}
