import ArgumentParser
import Domain

struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Compatibility entrypoint for validation flow",
        subcommands: [ValidateApp.self, ValidateIAP.self, ValidateSubscriptions.self]
    )
}

struct ValidateApp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Validate an app version before release"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "App ID") var app: String
    @Option(name: .long, help: "Version string") var version: String
    @Option(name: .long, help: "Platform") var platform: AppStorePlatform = .iOS

    func run() async throws {
        print(try await execute(
            appRepo: ClientProvider.makeAppRepository(),
            versionRepo: ClientProvider.makeVersionRepository(),
            buildRepo: ClientProvider.makeBuildRepository(),
            reviewDetailRepo: ClientProvider.makeReviewDetailRepository(),
            localizationRepo: ClientProvider.makeVersionLocalizationRepository(),
            screenshotRepo: ClientProvider.makeScreenshotRepository(),
            pricingRepo: ClientProvider.makePricingRepository()
        ))
    }

    func execute(
        appRepo: any AppRepository,
        versionRepo: any VersionRepository,
        buildRepo: any BuildRepository,
        reviewDetailRepo: any ReviewDetailRepository,
        localizationRepo: any VersionLocalizationRepository,
        screenshotRepo: any ScreenshotRepository,
        pricingRepo: any PricingRepository
    ) async throws -> String {
        let resolvedVersion = try await ReleaseFlowCompatibilitySupport.loadVersion(
            appId: app,
            versionString: version,
            platform: platform,
            versionRepo: versionRepo
        )
        let build: Build?
        if let buildId = resolvedVersion.buildId {
            build = try await buildRepo.getBuild(id: buildId)
        } else {
            build = nil
        }
        let assessment = try await ReleaseFlowCompatibilitySupport.assess(
            appId: app,
            version: resolvedVersion,
            build: build,
            appRepo: appRepo,
            buildRepo: buildRepo,
            reviewDetailRepo: reviewDetailRepo,
            localizationRepo: localizationRepo,
            screenshotRepo: screenshotRepo,
            pricingRepo: pricingRepo
        )

        let report = ValidateAppReport(
            id: resolvedVersion.id,
            appId: app,
            version: resolvedVersion.versionString,
            versionId: resolvedVersion.id,
            platform: resolvedVersion.platform,
            ok: assessment.blockers.isEmpty,
            blockers: assessment.blockers,
            warnings: assessment.warnings,
            checks: assessment.checks
        )

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try ReleaseFlowCompatibilitySupport.render(
            [report],
            formatter: formatter,
            headers: ["ID", "App ID", "Version", "OK"],
            rowMapper: { (item: ValidateAppReport) in [item.id, item.appId, item.version, item.ok ? "yes" : "no"] }
        )
    }
}

struct ValidateIAP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iap",
        abstract: "Validate in-app purchases"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "App ID") var app: String

    func run() async throws {
        print(try await execute(
            inAppPurchaseRepo: ClientProvider.makeInAppPurchaseRepository(),
            priceRepo: ClientProvider.makeInAppPurchasePriceRepository(),
            availabilityRepo: ClientProvider.makeInAppPurchaseAvailabilityRepository()
        ))
    }

    func execute(
        inAppPurchaseRepo: any InAppPurchaseRepository,
        priceRepo: any InAppPurchasePriceRepository,
        availabilityRepo: any InAppPurchaseAvailabilityRepository
    ) async throws -> String {
        let iaps = try await inAppPurchaseRepo.listInAppPurchases(appId: app, limit: nil).data
        var items: [CommerceValidationItem] = []
        for iap in iaps {
            let pricePoints = try await priceRepo.listPricePoints(iapId: iap.id, territory: nil)
            let availability = try await availabilityRepo.getAvailability(iapId: iap.id)
            items.append(
                makeIAPValidationItem(
                    iap: iap,
                    hasPrice: !pricePoints.isEmpty,
                    hasTerritoryCoverage: !availability.territories.isEmpty
                )
            )
        }

        return try renderCommerceValidationReport(
            CommerceValidationReport(
                id: "iap:\(app)",
                appId: app,
                kind: "iap",
                totalItems: items.count,
                validCount: items.filter(\.readyForSubmission).count,
                items: items
            ),
            globals: globals
        )
    }
}

struct ValidateSubscriptions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscriptions",
        abstract: "Validate subscriptions"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "App ID") var app: String

    func run() async throws {
        print(try await execute(
            subscriptionGroupRepo: ClientProvider.makeSubscriptionGroupRepository(),
            subscriptionRepo: ClientProvider.makeSubscriptionRepository(),
            availabilityRepo: ClientProvider.makeSubscriptionAvailabilityRepository()
        ))
    }

    func execute(
        subscriptionGroupRepo: any SubscriptionGroupRepository,
        subscriptionRepo: any SubscriptionRepository,
        availabilityRepo: any SubscriptionAvailabilityRepository
    ) async throws -> String {
        let groups = try await subscriptionGroupRepo.listSubscriptionGroups(appId: app, limit: nil).data
        var items: [CommerceValidationItem] = []
        for group in groups {
            let subscriptions = try await subscriptionRepo.listSubscriptions(groupId: group.id, limit: nil).data
            for subscription in subscriptions {
                let availability = try await availabilityRepo.getAvailability(subscriptionId: subscription.id)
                items.append(
                    makeSubscriptionValidationItem(
                        group: group,
                        subscription: subscription,
                        hasTerritoryCoverage: !availability.territories.isEmpty
                    )
                )
            }
        }

        return try renderCommerceValidationReport(
            CommerceValidationReport(
                id: "subscriptions:\(app)",
                appId: app,
                kind: "subscriptions",
                totalItems: items.count,
                validCount: items.filter(\.readyForSubmission).count,
                items: items
            ),
            globals: globals
        )
    }
}

private extension ValidateIAP {
    func makeIAPValidationItem(
        iap: InAppPurchase,
        hasPrice: Bool,
        hasTerritoryCoverage: Bool
    ) -> CommerceValidationItem {
        var issues: [String] = []
        if !hasPrice {
            issues.append("No price points configured")
        }
        if !hasTerritoryCoverage {
            issues.append("No territory coverage configured")
        }
        switch iap.state {
        case .missingMetadata:
            issues.append("State is missingMetadata")
        case .developerActionNeeded:
            issues.append("State requires developer action")
        case .rejected:
            issues.append("State is rejected")
        default:
            break
        }

        return CommerceValidationItem(
            id: iap.id,
            parentId: iap.appId,
            name: iap.referenceName,
            productId: iap.productId,
            state: iap.state.rawValue,
            readyForSubmission: issues.isEmpty && (iap.state == .readyToSubmit || iap.state.isPendingReview || iap.state.isLive),
            hasPricing: hasPrice,
            hasTerritoryCoverage: hasTerritoryCoverage,
            issues: issues
        )
    }
}

private extension ValidateSubscriptions {
    func makeSubscriptionValidationItem(
        group: SubscriptionGroup,
        subscription: Subscription,
        hasTerritoryCoverage: Bool
    ) -> CommerceValidationItem {
        var issues: [String] = []
        if !hasTerritoryCoverage {
            issues.append("No territory coverage configured")
        }
        switch subscription.state {
        case .missingMetadata:
            issues.append("State is missingMetadata")
        case .developerActionNeeded:
            issues.append("State requires developer action")
        case .rejected:
            issues.append("State is rejected")
        default:
            break
        }

        return CommerceValidationItem(
            id: subscription.id,
            parentId: group.id,
            name: subscription.name,
            productId: subscription.productId,
            state: subscription.state.rawValue,
            readyForSubmission: issues.isEmpty && (subscription.state == .readyToSubmit || subscription.state.isPendingReview || subscription.state.isLive),
            hasPricing: true,
            hasTerritoryCoverage: hasTerritoryCoverage,
            issues: issues
        )
    }
}

private func renderCommerceValidationReport(_ report: CommerceValidationReport, globals: GlobalOptions) throws -> String {
    let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
    return try ReleaseFlowCompatibilitySupport.render(
        [report],
        formatter: formatter,
        headers: ["App ID", "Kind", "Total", "Valid"],
        rowMapper: { [$0.appId, $0.kind, "\($0.totalItems)", "\($0.validCount)"] }
    )
}

private struct CommerceValidationReport: Encodable, Equatable, Identifiable {
    let id: String
    let appId: String
    let kind: String
    let totalItems: Int
    let validCount: Int
    let items: [CommerceValidationItem]
    var invalidCount: Int { totalItems - validCount }

    private enum CodingKeys: String, CodingKey {
        case id, appId, kind, totalItems, validCount, invalidCount, items
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(appId, forKey: .appId)
        try container.encode(kind, forKey: .kind)
        try container.encode(totalItems, forKey: .totalItems)
        try container.encode(validCount, forKey: .validCount)
        try container.encode(invalidCount, forKey: .invalidCount)
        try container.encode(items, forKey: .items)
    }
}

private struct CommerceValidationItem: Encodable, Equatable, Identifiable {
    let id: String
    let parentId: String
    let name: String
    let productId: String
    let state: String
    let readyForSubmission: Bool
    let hasPricing: Bool
    let hasTerritoryCoverage: Bool
    let issues: [String]
}
