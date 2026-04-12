import Foundation
import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct PricingAvailabilityTests {

    @Test func `availability view returns app territory coverage`() async throws {
        let mockRepo = MockAppAvailabilityRepository()
        given(mockRepo).getAppAvailability(appId: .value("app-42")).willReturn(
            AppAvailability(
                id: "avail-1",
                appId: "app-42",
                isAvailableInNewTerritories: true,
                territories: [
                    AppTerritoryAvailability(
                        id: "t-usa",
                        territoryId: "USA",
                        isAvailable: true,
                        releaseDate: nil,
                        isPreOrderEnabled: false,
                        contentStatuses: [.available]
                    )
                ]
            )
        )

        let cmd = try PricingAvailabilityView.parse(["--app", "app-42", "--pretty"])
        let output = try await cmd.execute(appAvailabilityRepo: mockRepo)

        #expect(output == """
        {
          "data" : [
            {
              "affordances" : {
                "getAvailability" : "asc app-availability get --app-id app-42",
                "listTerritories" : "asc territories list"
              },
              "appId" : "app-42",
              "id" : "avail-1",
              "isAvailableInNewTerritories" : true,
              "territories" : [
                {
                  "contentStatuses" : [
                    "AVAILABLE"
                  ],
                  "id" : "t-usa",
                  "isAvailable" : true,
                  "isPreOrderEnabled" : false,
                  "territoryId" : "USA"
                }
              ]
            }
          ]
        }
        """)
    }

    @Test func `availability edit updates existing territory availability`() async throws {
        let mockRepo = MockAppAvailabilityRepository()
        given(mockRepo).getAppAvailability(appId: .value("app-42")).willReturn(
            AppAvailability(
                id: "avail-1",
                appId: "app-42",
                isAvailableInNewTerritories: true,
                territories: [
                    AppTerritoryAvailability(
                        id: "ta-usa",
                        territoryId: "USA",
                        isAvailable: true,
                        releaseDate: nil,
                        isPreOrderEnabled: false,
                        contentStatuses: [.available]
                    )
                ]
            )
        )
        given(mockRepo).updateAvailability(
            appId: .value("app-42"),
            territoryIds: .value(["USA"]),
            isAvailable: .value(false)
        ).willReturn(
            AppAvailability(
                id: "avail-1",
                appId: "app-42",
                isAvailableInNewTerritories: true,
                territories: [
                    AppTerritoryAvailability(
                        id: "ta-usa",
                        territoryId: "USA",
                        isAvailable: false,
                        releaseDate: nil,
                        isPreOrderEnabled: false,
                        contentStatuses: [.cannotSellRestrictedRating]
                    )
                ]
            )
        )

        let cmd = try PricingAvailabilityEdit.parse([
            "--app", "app-42",
            "--territory", "USA",
            "--available", "false",
            "--pretty",
        ])

        let output = try await cmd.execute(appAvailabilityRepo: mockRepo)
        #expect(output.contains("\"id\" : \"avail-1\""))
        #expect(output.contains("\"territoryId\" : \"USA\""))
        #expect(output.contains("\"isAvailable\" : false"))
    }

    @Test func `availability edit creates app availability when missing`() async throws {
        let cmd = try PricingAvailabilityEdit.parse([
            "--app", "app-42",
            "--territory", "USA",
            "--available-in-new-territories", "true",
            "--pretty",
        ])

        let output = try await cmd.execute(appAvailabilityRepo: MissingAvailabilityRepository())
        #expect(output.contains("\"id\" : \"avail-created\""))
        #expect(output.contains("\"isAvailableInNewTerritories\" : true"))
    }
}

private actor MissingAvailabilityRepository: AppAvailabilityRepository {
    func getAppAvailability(appId: String) async throws -> AppAvailability {
        _ = appId
        throw APIError.notFound("missing")
    }

    func createAvailability(
        appId: String,
        isAvailableInNewTerritories: Bool,
        territoryIds: [String]
    ) async throws -> AppAvailability {
        _ = appId
        return AppAvailability(
            id: "avail-created",
            appId: "app-42",
            isAvailableInNewTerritories: isAvailableInNewTerritories,
            territories: territoryIds.map {
                AppTerritoryAvailability(
                    id: "ta-\($0.lowercased())",
                    territoryId: $0,
                    isAvailable: true,
                    releaseDate: nil,
                    isPreOrderEnabled: false,
                    contentStatuses: [.available]
                )
            }
        )
    }

    func updateAvailability(
        appId: String,
        territoryIds: [String],
        isAvailable: Bool
    ) async throws -> AppAvailability {
        _ = appId
        _ = territoryIds
        _ = isAvailable
        fatalError("updateAvailability should not be called for create flow")
    }
}

@Suite
struct PricingTerritoriesTests {

    @Test func `territories are returned sorted by identifier`() async throws {
        let mockRepo = MockTerritoryRepository()
        given(mockRepo).listTerritories().willReturn([
            Territory(id: "JPN", currency: "JPY"),
            Territory(id: "USA", currency: "USD"),
        ])

        let cmd = try PricingTerritoriesList.parse(["--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        #expect(output == """
        {
          "data" : [
            {
              "affordances" : {
                "listTerritories" : "asc territories list"
              },
              "currency" : "JPY",
              "id" : "JPN"
            },
            {
              "affordances" : {
                "listTerritories" : "asc territories list"
              },
              "currency" : "USD",
              "id" : "USA"
            }
          ]
        }
        """)
    }
}

@Suite
struct PricingIAPTests {

    @Test func `iap pricing view combines price points and availability`() async throws {
        let iapRepo = MockInAppPurchaseRepository()
        let priceRepo = MockInAppPurchasePriceRepository()
        let availabilityRepo = MockInAppPurchaseAvailabilityRepository()

        given(iapRepo).listInAppPurchases(appId: .value("app-42"), limit: .any).willReturn(
            PaginatedResponse(
                data: [
                    InAppPurchase(
                        id: "iap-1",
                        appId: "app-42",
                        referenceName: "Coins",
                        productId: "coins",
                        type: .consumable,
                        state: .approved
                    )
                ]
            )
        )
        given(priceRepo).listPricePoints(iapId: .value("iap-1"), territory: .value(nil)).willReturn([
            InAppPurchasePricePoint(
                id: "pp-1",
                iapId: "iap-1",
                territory: "USA",
                customerPrice: "0.99",
                proceeds: "0.70"
            )
        ])
        given(availabilityRepo).getAvailability(iapId: .value("iap-1")).willReturn(
            InAppPurchaseAvailability(
                id: "avail-iap-1",
                iapId: "iap-1",
                isAvailableInNewTerritories: true,
                territories: [Territory(id: "USA", currency: "USD")]
            )
        )

        let cmd = try PricingIAPView.parse(["--app", "app-42", "--pretty"])
        let output = try await cmd.execute(
            inAppPurchaseRepo: iapRepo,
            priceRepo: priceRepo,
            availabilityRepo: availabilityRepo
        )

        #expect(output.contains("\"referenceName\" : \"Coins\""))
        #expect(output.contains("\"hasPrice\" : true"))
        #expect(output.contains("\"hasTerritoryCoverage\" : true"))
        #expect(output.contains("\"pricingStatus\" : \"configured\""))
    }
}

@Suite
struct PricingSubscriptionTests {

    @Test func `subscription pricing view combines groups subscriptions and coverage`() async throws {
        let groupRepo = MockSubscriptionGroupRepository()
        let subscriptionRepo = MockSubscriptionRepository()
        let availabilityRepo = MockSubscriptionAvailabilityRepository()

        given(groupRepo).listSubscriptionGroups(appId: .value("app-42"), limit: .any).willReturn(
            PaginatedResponse(
                data: [
                    SubscriptionGroup(id: "group-1", appId: "app-42", referenceName: "Pro")
                ]
            )
        )
        given(subscriptionRepo).listSubscriptions(groupId: .value("group-1"), limit: .any).willReturn(
            PaginatedResponse(
                data: [
                    Subscription(
                        id: "sub-1",
                        groupId: "group-1",
                        name: "Monthly",
                        productId: "pro.monthly",
                        subscriptionPeriod: .oneMonth,
                        isFamilySharable: true,
                        state: .approved
                    )
                ]
            )
        )
        given(availabilityRepo).getAvailability(subscriptionId: .value("sub-1")).willReturn(
            SubscriptionAvailability(
                id: "avail-sub-1",
                subscriptionId: "sub-1",
                isAvailableInNewTerritories: true,
                territories: [Territory(id: "USA", currency: "USD")]
            )
        )

        let cmd = try PricingSubscriptionsView.parse(["--app", "app-42", "--pretty"])
        let output = try await cmd.execute(
            subscriptionGroupRepo: groupRepo,
            subscriptionRepo: subscriptionRepo,
            availabilityRepo: availabilityRepo
        )

        #expect(output.contains("\"groupId\" : \"group-1\""))
        #expect(output.contains("\"subscriptionId\" : \"sub-1\""))
        #expect(output.contains("\"hasTerritoryCoverage\" : true"))
    }
}
