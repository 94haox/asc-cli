import ArgumentParser
import Domain
import Foundation

struct PricingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pricing",
        abstract: "Manage pricing, territory availability, and pricing compatibility commands",
        subcommands: [
            PricingAvailabilityCommand.self,
            PricingTerritoriesCommand.self,
            PricingIAPCommand.self,
            PricingSubscriptionsCommand.self,
        ]
    )
}

// MARK: - Availability

struct PricingAvailabilityCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "availability",
        abstract: "Inspect app availability and territory coverage",
        subcommands: [PricingAvailabilityView.self, PricingAvailabilityEdit.self],
        defaultSubcommand: PricingAvailabilityView.self
    )
}

struct PricingAvailabilityView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View app availability and territory coverage"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App ID")
    var app: String

    func run() async throws {
        let repo = try ClientProvider.makeAppAvailabilityRepository()
        print(try await execute(appAvailabilityRepo: repo))
    }

    func execute(appAvailabilityRepo: any AppAvailabilityRepository) async throws -> String {
        let availability = try await appAvailabilityRepo.getAppAvailability(appId: app)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems(
            [availability],
            headers: ["ID", "App ID", "Available in New Territories", "Territories"],
            rowMapper: { [
                $0.id,
                $0.appId,
                $0.isAvailableInNewTerritories ? "true" : "false",
                "\($0.territories.count)",
            ] }
        )
    }
}

struct PricingAvailabilityEdit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit app availability"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App ID")
    var app: String

    @Option(name: .long, help: "Territory code to target")
    var territory: [String] = []

    @Option(name: .long, help: "Set whether the app is available in the selected territories")
    var available: Bool?

    @Option(name: .long, help: "Set whether the app is available in new territories")
    var availableInNewTerritories: Bool?

    @Flag(name: .long, help: "Show the planned update without applying it")
    var dryRun: Bool = false

    func run() async throws {
        let repo = try ClientProvider.makeAppAvailabilityRepository()
        print(try await execute(appAvailabilityRepo: repo))
    }

    func execute(appAvailabilityRepo: any AppAvailabilityRepository) async throws -> String {
        guard !territory.isEmpty else {
            throw ValidationError("Provide at least one --territory value.")
        }

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)

        if dryRun {
            let plan = PricingAvailabilityEditPlan(
                id: app,
                appId: app,
                territoryIds: territory,
                available: available,
                availableInNewTerritories: availableInNewTerritories,
                mode: "dry-run"
            )
            return try ReleaseFlowCompatibilitySupport.render(
                [plan],
                formatter: formatter,
                headers: ["App ID", "Territories", "Mode"],
                rowMapper: { [$0.appId, $0.territoryIds.joined(separator: ","), $0.mode] }
            )
        }

        let existingAvailability: AppAvailability?
        do {
            existingAvailability = try await appAvailabilityRepo.getAppAvailability(appId: app)
        } catch let error as APIError {
            if case .notFound = error {
                existingAvailability = nil
            } else {
                throw error
            }
        } catch {
            throw error
        }

        let availability: AppAvailability
        if let existingAvailability {
            guard let available else {
                throw ValidationError("Provide --available when editing an existing app availability.")
            }
            guard availableInNewTerritories == nil else {
                throw ValidationError("--available-in-new-territories can only be set when creating app availability.")
            }
            availability = try await appAvailabilityRepo.updateAvailability(
                appId: app,
                territoryIds: territory,
                isAvailable: available
            )
        } else {
            guard let availableInNewTerritories else {
                throw ValidationError("Provide --available-in-new-territories when creating app availability.")
            }
            availability = try await appAvailabilityRepo.createAvailability(
                appId: app,
                isAvailableInNewTerritories: availableInNewTerritories,
                territoryIds: territory
            )
        }

        return try ReleaseFlowCompatibilitySupport.render(
            [availability],
            formatter: formatter,
            headers: ["ID", "App ID", "Available in New Territories", "Territories"],
            rowMapper: { [
                $0.id,
                $0.appId,
                $0.isAvailableInNewTerritories ? "true" : "false",
                "\($0.territories.count)"
            ] }
        )
    }
}

private struct PricingAvailabilityEditPlan: Codable, Equatable, Identifiable {
    let id: String
    let appId: String
    let territoryIds: [String]
    let available: Bool?
    let availableInNewTerritories: Bool?
    let mode: String
}

// MARK: - Territories

struct PricingTerritoriesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "territories",
        abstract: "List App Store territories for pricing and availability",
        subcommands: [PricingTerritoriesList.self],
        defaultSubcommand: PricingTerritoriesList.self
    )
}

struct PricingTerritoriesList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List App Store territories"
    )

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        let repo = try ClientProvider.makeTerritoryRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any TerritoryRepository) async throws -> String {
        let territories = try await repo.listTerritories().sorted { $0.id < $1.id }
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems(territories)
    }
}

// MARK: - IAP pricing

struct PricingIAPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iap",
        abstract: "Inspect in-app purchase pricing coverage",
        subcommands: [PricingIAPView.self],
        defaultSubcommand: PricingIAPView.self
    )
}

struct PricingIAPView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "Inspect in-app purchase pricing coverage"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App ID")
    var app: String

    func run() async throws {
        let iapRepo = try ClientProvider.makeInAppPurchaseRepository()
        let priceRepo = try ClientProvider.makeInAppPurchasePriceRepository()
        let availabilityRepo = try ClientProvider.makeInAppPurchaseAvailabilityRepository()
        print(try await execute(
            inAppPurchaseRepo: iapRepo,
            priceRepo: priceRepo,
            availabilityRepo: availabilityRepo
        ))
    }

    func execute(
        inAppPurchaseRepo: any InAppPurchaseRepository,
        priceRepo: any InAppPurchasePriceRepository,
        availabilityRepo: any InAppPurchaseAvailabilityRepository
    ) async throws -> String {
        let response = try await inAppPurchaseRepo.listInAppPurchases(appId: app, limit: nil)
        let items = try await response.data.asyncMap { iap in
            let pricePoints = try await priceRepo.listPricePoints(iapId: iap.id, territory: nil)
            let availability = try await availabilityRepo.getAvailability(iapId: iap.id)
            return PricingIAPSummary(
                appId: iap.appId,
                iapId: iap.id,
                referenceName: iap.referenceName,
                productId: iap.productId,
                state: iap.state.rawValue,
                hasPrice: !pricePoints.isEmpty,
                hasTerritoryCoverage: !availability.territories.isEmpty
            )
        }

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems(
            items,
            headers: ["App ID", "IAP ID", "Reference Name", "Product ID", "State", "Has Price", "Coverage", "Pricing Status"],
            rowMapper: { (item: PricingIAPSummary) in
                [
                    item.appId,
                    item.iapId,
                    item.referenceName,
                    item.productId,
                    item.state,
                    item.hasPrice ? "true" : "false",
                    item.hasTerritoryCoverage ? "true" : "false",
                    item.pricingStatus,
                ]
            }
        )
    }
}

// MARK: - Subscriptions pricing

struct PricingSubscriptionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscriptions",
        abstract: "Inspect subscription pricing coverage",
        subcommands: [PricingSubscriptionsView.self],
        defaultSubcommand: PricingSubscriptionsView.self
    )
}

struct PricingSubscriptionsView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "Inspect subscription pricing coverage"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App ID")
    var app: String

    func run() async throws {
        let groupRepo = try ClientProvider.makeSubscriptionGroupRepository()
        let subscriptionRepo = try ClientProvider.makeSubscriptionRepository()
        let availabilityRepo = try ClientProvider.makeSubscriptionAvailabilityRepository()
        print(try await execute(
            subscriptionGroupRepo: groupRepo,
            subscriptionRepo: subscriptionRepo,
            availabilityRepo: availabilityRepo
        ))
    }

    func execute(
        subscriptionGroupRepo: any SubscriptionGroupRepository,
        subscriptionRepo: any SubscriptionRepository,
        availabilityRepo: any SubscriptionAvailabilityRepository
    ) async throws -> String {
        let groups = try await subscriptionGroupRepo.listSubscriptionGroups(appId: app, limit: nil).data
        var items: [PricingSubscriptionSummary] = []
        for group in groups {
            let response = try await subscriptionRepo.listSubscriptions(groupId: group.id, limit: nil)
            for subscription in response.data {
                let availability = try await availabilityRepo.getAvailability(subscriptionId: subscription.id)
                items.append(
                    PricingSubscriptionSummary(
                        appId: group.appId,
                        groupId: group.id,
                        groupReferenceName: group.referenceName,
                        subscriptionId: subscription.id,
                        name: subscription.name,
                        productId: subscription.productId,
                        period: subscription.subscriptionPeriod.displayName,
                        state: subscription.state.rawValue,
                        hasTerritoryCoverage: !availability.territories.isEmpty
                    )
                )
            }
        }

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems(
            items,
            headers: ["App ID", "Group ID", "Subscription ID", "Name", "Product ID", "Period", "State", "Coverage", "Pricing Status"],
            rowMapper: {
                [
                    $0.appId,
                    $0.groupId,
                    $0.subscriptionId,
                    $0.name,
                    $0.productId,
                    $0.period,
                    $0.state,
                    $0.hasTerritoryCoverage ? "true" : "false",
                    $0.pricingStatus,
                ]
            }
        )
    }
}

// MARK: - Support types

private struct PricingIAPSummary: Encodable, AffordanceProviding {
    let appId: String
    let iapId: String
    let referenceName: String
    let productId: String
    let state: String
    let hasPrice: Bool
    let hasTerritoryCoverage: Bool

    var pricingStatus: String {
        if hasPrice && hasTerritoryCoverage { return "configured" }
        if hasPrice { return "price-only" }
        return "missing-price"
    }

    private enum CodingKeys: String, CodingKey {
        case appId, iapId, referenceName, productId, state, hasPrice, hasTerritoryCoverage, pricingStatus
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appId, forKey: .appId)
        try container.encode(iapId, forKey: .iapId)
        try container.encode(referenceName, forKey: .referenceName)
        try container.encode(productId, forKey: .productId)
        try container.encode(state, forKey: .state)
        try container.encode(hasPrice, forKey: .hasPrice)
        try container.encode(hasTerritoryCoverage, forKey: .hasTerritoryCoverage)
        try container.encode(pricingStatus, forKey: .pricingStatus)
    }

    var affordances: [String: String] {
        var commands: [String: String] = [
            "getAvailability": "asc iap-availability get --iap-id \(iapId)",
            "listLocalizations": "asc iap-localizations list --iap-id \(iapId)",
            "listPricePoints": "asc iap price-points list --iap-id \(iapId)",
        ]
        if state == InAppPurchaseState.readyToSubmit.rawValue {
            commands["submit"] = "asc iap submit --iap-id \(iapId)"
        }
        return commands
    }
}

private struct PricingSubscriptionSummary: Encodable, AffordanceProviding {
    let appId: String
    let groupId: String
    let groupReferenceName: String
    let subscriptionId: String
    let name: String
    let productId: String
    let period: String
    let state: String
    let hasTerritoryCoverage: Bool

    var pricingStatus: String {
        if hasTerritoryCoverage && state == SubscriptionState.approved.rawValue {
            return "live"
        }
        if hasTerritoryCoverage {
            return "configured"
        }
        return "no-territory-coverage"
    }

    private enum CodingKeys: String, CodingKey {
        case appId, groupId, groupReferenceName, subscriptionId, name, productId, period, state, hasTerritoryCoverage, pricingStatus
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appId, forKey: .appId)
        try container.encode(groupId, forKey: .groupId)
        try container.encode(groupReferenceName, forKey: .groupReferenceName)
        try container.encode(subscriptionId, forKey: .subscriptionId)
        try container.encode(name, forKey: .name)
        try container.encode(productId, forKey: .productId)
        try container.encode(period, forKey: .period)
        try container.encode(state, forKey: .state)
        try container.encode(hasTerritoryCoverage, forKey: .hasTerritoryCoverage)
        try container.encode(pricingStatus, forKey: .pricingStatus)
    }

    var affordances: [String: String] {
        var commands: [String: String] = [
            "createLocalization": "asc subscription-localizations create --subscription-id \(subscriptionId) --locale en-US --name <name>",
            "getAvailability": "asc subscription-availability get --subscription-id \(subscriptionId)",
            "listIntroductoryOffers": "asc subscription-offers list --subscription-id \(subscriptionId)",
            "listLocalizations": "asc subscription-localizations list --subscription-id \(subscriptionId)",
            "listOfferCodes": "asc subscription-offer-codes list --subscription-id \(subscriptionId)",
        ]
        if state == SubscriptionState.readyToSubmit.rawValue {
            commands["submit"] = "asc subscriptions submit --subscription-id \(subscriptionId)"
        }
        return commands
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        result.reserveCapacity(count)
        for element in self {
            result.append(try await transform(element))
        }
        return result
    }
}
