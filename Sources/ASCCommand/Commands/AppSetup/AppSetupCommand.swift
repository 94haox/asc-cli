import ArgumentParser
import Domain

struct AppSetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app-setup",
        abstract: "Inspect app setup, category, and availability compatibility commands",
        subcommands: [
            AppSetupInfo.self,
            AppSetupCategories.self,
            AppSetupAvailability.self,
        ]
    )
}

struct AppSetupInfo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show app metadata for setup workflows"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App ID")
    var app: String

    func run() async throws {
        let repo = try ClientProvider.makeAppRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any AppRepository) async throws -> String {
        let app = try await repo.getApp(id: app)
        let summary = AppSetupInfoSummary(
            appId: app.id,
            appName: app.name,
            bundleId: app.bundleId,
            sku: app.sku,
            primaryLocale: app.primaryLocale
        )
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems([summary])
    }
}

struct AppSetupCategories: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "categories",
        abstract: "Inspect app categories for setup workflows"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App ID")
    var app: String

    @Option(name: .customLong("app-info-id"), help: "Specific App Info ID to edit")
    var appInfoId: String?

    @Flag(name: .long, help: "Edit category assignments")
    var edit: Bool = false

    @Option(name: .customLong("primary-category"), help: "Primary category ID")
    var primaryCategory: String?

    @Option(name: .customLong("primary-subcategory-one"), help: "Primary subcategory 1 ID")
    var primarySubcategoryOne: String?

    @Option(name: .customLong("primary-subcategory-two"), help: "Primary subcategory 2 ID")
    var primarySubcategoryTwo: String?

    @Option(name: .customLong("secondary-category"), help: "Secondary category ID")
    var secondaryCategory: String?

    @Option(name: .customLong("secondary-subcategory-one"), help: "Secondary subcategory 1 ID")
    var secondarySubcategoryOne: String?

    @Option(name: .customLong("secondary-subcategory-two"), help: "Secondary subcategory 2 ID")
    var secondarySubcategoryTwo: String?

    func run() async throws {
        let appRepo = try ClientProvider.makeAppRepository()
        let appInfoRepo = try ClientProvider.makeAppInfoRepository()
        let categoryRepo = try ClientProvider.makeAppCategoryRepository()
        print(try await execute(appRepo: appRepo, appInfoRepo: appInfoRepo, categoryRepo: categoryRepo))
    }

    func execute(
        appRepo: any AppRepository,
        appInfoRepo: any AppInfoRepository,
        categoryRepo: any AppCategoryRepository
    ) async throws -> String {
        let app = try await appRepo.getApp(id: app)
        let infos = try await appInfoRepo.listAppInfos(appId: app.id)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)

        if edit {
            guard
                primaryCategory != nil ||
                primarySubcategoryOne != nil ||
                primarySubcategoryTwo != nil ||
                secondaryCategory != nil ||
                secondarySubcategoryOne != nil ||
                secondarySubcategoryTwo != nil
            else {
                throw ValidationError("Provide at least one category field when using --edit.")
            }

            let selectedInfo: AppInfo
            if let appInfoId {
                guard let matched = infos.first(where: { $0.id == appInfoId }) else {
                    throw ValidationError("App info \(appInfoId) was not found for app \(app.id).")
                }
                selectedInfo = matched
            } else {
                guard infos.count == 1, let first = infos.first else {
                    throw ValidationError("Provide --app-info-id when the app has multiple app infos.")
                }
                selectedInfo = first
            }

            let updated = try await appInfoRepo.updateCategories(
                id: selectedInfo.id,
                primaryCategoryId: primaryCategory,
                primarySubcategoryOneId: primarySubcategoryOne,
                primarySubcategoryTwoId: primarySubcategoryTwo,
                secondaryCategoryId: secondaryCategory,
                secondarySubcategoryOneId: secondarySubcategoryOne,
                secondarySubcategoryTwoId: secondarySubcategoryTwo
            )
            let summary = AppSetupCategoriesSummary(
                appId: app.id,
                appName: app.name,
                appInfoId: updated.id,
                primaryCategoryId: updated.primaryCategoryId,
                secondaryCategoryId: updated.secondaryCategoryId,
                availableCategories: 0
            )

            return try formatter.formatAgentItems([summary])
        }

        let categories = try await categoryRepo.listCategories(platform: nil)
        let availableCount = categories.count
        let summaries = infos.map {
            AppSetupCategoriesSummary(
                appId: app.id,
                appName: app.name,
                appInfoId: $0.id,
                primaryCategoryId: $0.primaryCategoryId,
                secondaryCategoryId: $0.secondaryCategoryId,
                availableCategories: availableCount
            )
        }

        return try formatter.formatAgentItems(summaries)
    }
}

struct AppSetupAvailability: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "availability",
        abstract: "Inspect app territory availability for setup workflows"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App ID")
    var app: String

    func run() async throws {
        let repo = try ClientProvider.makeAppAvailabilityRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any AppAvailabilityRepository) async throws -> String {
        let availability = try await repo.getAppAvailability(appId: app)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems(
            [availability],
            headers: ["ID", "App ID", "Available in New Territories", "Territories"],
            rowMapper: { availability in
                [
                    availability.id,
                    availability.appId,
                    availability.isAvailableInNewTerritories ? "true" : "false",
                    "\(availability.territories.count)",
                ]
            }
        )
    }
}

private struct AppSetupInfoSummary: Codable, AffordanceProviding, Presentable {
    let appId: String
    let appName: String
    let bundleId: String
    let sku: String?
    let primaryLocale: String?

    static let tableHeaders = ["App ID", "App Name", "Bundle ID", "SKU", "Primary Locale"]

    var tableRow: [String] {
        [appId, appName, bundleId, sku ?? "-", primaryLocale ?? "-"]
    }

    var affordances: [String: String] {
        [
            "availability": "asc app-setup availability --app \(appId)",
            "categories": "asc app-setup categories --app \(appId)",
        ]
    }
}

private struct AppSetupCategoriesSummary: Codable, AffordanceProviding, Presentable {
    let appId: String
    let appName: String
    let appInfoId: String
    let primaryCategoryId: String?
    let secondaryCategoryId: String?
    let availableCategories: Int

    static let tableHeaders = ["App ID", "App Name", "App Info ID", "Primary Category", "Secondary Category", "Available Categories"]

    var tableRow: [String] {
        [appId, appName, appInfoId, primaryCategoryId ?? "-", secondaryCategoryId ?? "-", "\(availableCategories)"]
    }

    var affordances: [String: String] {
        [
            "availability": "asc app-setup availability --app \(appId)",
            "categories": "asc app-setup categories --app \(appId)",
            "info": "asc app-setup info --app \(appId)",
        ]
    }
}
