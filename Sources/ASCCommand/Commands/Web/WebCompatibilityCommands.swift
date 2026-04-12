import ArgumentParser
import Domain
import Foundation
import Infrastructure

struct WebCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "web",
        abstract: "Compatibility commands for web-session workflows",
        subcommands: [WebAuthCommand.self, WebAppsCommand.self, WebPrivacyCommand.self, WebReviewCommand.self]
    )
}

// MARK: - Auth

struct WebAuthCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Inspect authentication capabilities",
        subcommands: [WebAuthCapabilities.self]
    )
}

struct WebAuthCapabilities: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capabilities",
        abstract: "Summarize the current auth context"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .customLong("key-id"), help: "Override the current key ID when resolving capabilities")
    var keyId: String?

    func run() async throws {
        print(try await execute(storage: FileAuthStorage(), envProvider: EnvironmentAuthProvider()))
    }

    func execute(storage: any AuthStorage, envProvider: any AuthProvider) async throws -> String {
        let credentials: AuthCredentials
        let source: String
        let accountName: String?
        let state: WebAuthCapabilityState
        let reason: String?

        if let stored = try? storage.load(name: nil) {
            credentials = stored
            let accounts = (try? storage.loadAll()) ?? []
            accountName = accounts.first(where: \.isActive)?.name
            source = CredentialSource.file.rawValue
            do {
                try stored.validate()
                state = .available
                reason = nil
            } catch {
                state = .invalid
                reason = webAuthCapabilityReason(error)
            }
        } else {
            do {
                credentials = try envProvider.resolve()
                state = .available
                reason = nil
            } catch {
                credentials = AuthCredentials(keyID: keyId ?? "", issuerID: "", privateKeyPEM: "")
                let classification = webAuthCapabilityClassification(error)
                state = classification.state
                reason = classification.reason
            }
            source = CredentialSource.environment.rawValue
            accountName = nil
        }

        let capability = WebAuthCapability(
            name: accountName,
            keyID: keyId ?? credentials.keyID,
            issuerID: credentials.issuerID,
            source: source,
            state: state.rawValue,
            reason: reason,
            isValid: state == .available,
            roles: [],
            permissions: [],
            expiresAt: nil,
            hasWebFallbackRoutes: state == .available
        )

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems([capability])
    }
}

private enum WebAuthCapabilityState: String, Codable {
    case available
    case missing
    case invalid
}

private struct WebAuthCapability: Codable, Presentable, AffordanceProviding {
    let name: String?
    let keyID: String
    let issuerID: String
    let source: String
    let state: String
    let reason: String?
    let isValid: Bool
    let roles: [String]
    let permissions: [String]
    let expiresAt: String?
    let hasWebFallbackRoutes: Bool

    static let tableHeaders = ["Name", "Key ID", "Source", "Valid"]
    var tableRow: [String] {
        [name ?? "", keyID, source, isValid ? "Yes" : "No"]
    }

    var affordances: [String: String] {
        var affordances = [
            "authCheck": "asc auth check",
        ]

        guard hasWebFallbackRoutes else {
            return affordances
        }

        affordances["appsAvailabilityCreate"] = "asc web apps availability create --app-id <app-id> --territory <territory>"
        affordances["privacyPull"] = "asc web privacy pull --app-id <app-id> --out privacy.json"
        return affordances
    }
}

private func webAuthCapabilityClassification(_ error: Error) -> (state: WebAuthCapabilityState, reason: String) {
    switch error {
    case AuthError.missingKeyID:
        return (.missing, "missingKeyID")
    case AuthError.missingIssuerID:
        return (.missing, "missingIssuerID")
    case AuthError.missingPrivateKey:
        return (.missing, "missingPrivateKey")
    case AuthError.invalidPrivateKey(let message):
        return (.invalid, "invalidPrivateKey: \(message)")
    case AuthError.tokenGenerationFailed(let message):
        return (.invalid, "tokenGenerationFailed: \(message)")
    case AuthError.accountNotFound(let account):
        return (.invalid, "accountNotFound: \(account)")
    default:
        return (.missing, String(describing: error))
    }
}

private func webAuthCapabilityReason(_ error: Error) -> String {
    switch error {
    case AuthError.missingKeyID:
        return "missingKeyID"
    case AuthError.missingIssuerID:
        return "missingIssuerID"
    case AuthError.missingPrivateKey:
        return "missingPrivateKey"
    case AuthError.invalidPrivateKey(let message):
        return "invalidPrivateKey: \(message)"
    case AuthError.tokenGenerationFailed(let message):
        return "tokenGenerationFailed: \(message)"
    case AuthError.accountNotFound(let account):
        return "accountNotFound: \(account)"
    default:
        return String(describing: error)
    }
}

// MARK: - Apps

struct WebAppsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apps",
        abstract: "Web-session helpers for app availability",
        subcommands: [WebAppsAvailabilityCommand.self]
    )
}

struct WebAppsAvailabilityCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "availability",
        abstract: "Manage app availability",
        subcommands: [WebAppsAvailabilityCreate.self, WebAppsAvailabilityUpdate.self]
    )
}

struct WebAppsAvailabilityCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create app availability via web-session fallback"
    )

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .customLong("territory"), help: "Territory code; may be repeated")
    var territories: [String] = []

    @Flag(name: .customLong("available-in-new-territories"), help: "Make the app available in new territories")
    var availableInNewTerritories: Bool = false

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    func run() async throws {
        let repo = try ClientProvider.makeAppAvailabilityRepository()
        print(try await execute(appAvailabilityRepo: repo))
    }

    func execute(appAvailabilityRepo: any AppAvailabilityRepository) async throws -> String {
        guard !territories.isEmpty else {
            throw ValidationError("Provide at least one --territory value.")
        }

        let territoryIds = normalizedTerritories(territories)
        do {
            let availability = try await appAvailabilityRepo.getAppAvailability(appId: appId)
            return try encodeJSON(
                WebAppsAvailabilityResult(
                    appId: appId,
                    operation: "existing",
                    confirmed: true,
                    territoryIds: territoryIds,
                    available: true,
                    availableInNewTerritories: availability.isAvailableInNewTerritories,
                    availability: availability
                ),
                pretty: pretty
            )
        } catch let error as APIError {
            guard case .notFound = error else { throw error }
            let availability = try await appAvailabilityRepo.createAvailability(
                appId: appId,
                isAvailableInNewTerritories: availableInNewTerritories,
                territoryIds: territoryIds
            )
            return try encodeJSON(
                WebAppsAvailabilityResult(
                    appId: appId,
                    operation: "created",
                    confirmed: true,
                    territoryIds: territoryIds,
                    available: true,
                    availableInNewTerritories: availability.isAvailableInNewTerritories,
                    availability: availability
                ),
                pretty: pretty
            )
        }
    }
}

struct WebAppsAvailabilityUpdate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Preview or update app availability via web-session fallback"
    )

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .customLong("territory"), help: "Territory code; may be repeated")
    var territories: [String] = []

    @Option(name: .customLong("available"), help: "Set selected territories to available/unavailable")
    var available: Bool = true

    @Flag(name: .customLong("available-in-new-territories"), help: "Make the app available in new territories")
    var availableInNewTerritories: Bool = false

    @Flag(name: .customLong("confirm"), help: "Apply the availability change")
    var confirm: Bool = false

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    func run() async throws {
        let repo = try ClientProvider.makeAppAvailabilityRepository()
        print(try await execute(appAvailabilityRepo: repo))
    }

    func execute(appAvailabilityRepo: any AppAvailabilityRepository) async throws -> String {
        guard !territories.isEmpty else {
            throw ValidationError("Provide at least one --territory value.")
        }

        let territoryIds = normalizedTerritories(territories)
        let plan = WebAppsAvailabilityPlan(
            appId: appId,
            territories: territoryIds,
            availableInNewTerritories: availableInNewTerritories,
            confirmed: confirm,
            nextHint: confirm ? "Apply the requested territory change." : "Re-run with --confirm to apply."
        )

        guard confirm else {
            return try encodeJSON(plan, pretty: pretty)
        }

        do {
            let existing = try await appAvailabilityRepo.getAppAvailability(appId: appId)
            let updated = try await appAvailabilityRepo.updateAvailability(
                appId: appId,
                territoryIds: territoryIds,
                isAvailable: available
            )
            return try encodeJSON(
                WebAppsAvailabilityResult(
                    appId: appId,
                    operation: "updated",
                    confirmed: true,
                    territoryIds: territoryIds,
                    available: available,
                    availableInNewTerritories: existing.isAvailableInNewTerritories,
                    availability: updated
                ),
                pretty: pretty
            )
        } catch let error as APIError {
            guard case .notFound = error else { throw error }
            let created = try await appAvailabilityRepo.createAvailability(
                appId: appId,
                isAvailableInNewTerritories: availableInNewTerritories,
                territoryIds: territoryIds
            )
            return try encodeJSON(
                WebAppsAvailabilityResult(
                    appId: appId,
                    operation: "created",
                    confirmed: true,
                    territoryIds: territoryIds,
                    available: true,
                    availableInNewTerritories: created.isAvailableInNewTerritories,
                    availability: created
                ),
                pretty: pretty
            )
        }
    }
}

private struct WebAppsAvailabilityPlan: Codable {
    let appId: String
    let territories: [String]
    let availableInNewTerritories: Bool
    let confirmed: Bool
    let nextHint: String
}

private struct WebAppsAvailabilityResult: Codable {
    let appId: String
    let operation: String
    let confirmed: Bool
    let territoryIds: [String]
    let available: Bool
    let availableInNewTerritories: Bool
    let availability: AppAvailability
}

private func normalizedTerritories(_ territories: [String]) -> [String] {
    territories.sorted()
}

// MARK: - Privacy

struct WebPrivacyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "privacy",
        abstract: "Inspect and apply App Privacy compatibility snapshots",
        subcommands: [WebPrivacyPull.self, WebPrivacyPlan.self, WebPrivacyApply.self, WebPrivacyPublish.self]
    )
}

struct WebPrivacyPull: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Export the current privacy snapshot"
    )

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .customLong("out"), help: "Output file path")
    var out: String?

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    func run() async throws {
        let repo = try ClientProvider.makeAppInfoRepository()
        print(try await execute(appInfoRepo: repo))
    }

    func execute(appInfoRepo: any AppInfoRepository) async throws -> String {
        let snapshot = try await loadPrivacySnapshot(appId: appId, appInfoRepo: appInfoRepo)
        let json = try encodeJSON(snapshot, pretty: pretty)
        if let out {
            try json.write(toFile: out, atomically: true, encoding: String.Encoding.utf8)
        }
        return json
    }
}

struct WebPrivacyPlan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Preview privacy changes"
    )

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .customLong("file"), help: "Input privacy snapshot file")
    var file: String

    @Option(name: .customLong("out"), help: "Output file path")
    var out: String?

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    func run() async throws {
        let repo = try ClientProvider.makeAppInfoRepository()
        print(try await execute(appInfoRepo: repo))
    }

    func execute(appInfoRepo: any AppInfoRepository) async throws -> String {
        let desired = try JSONDecoder().decode(WebPrivacySnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: file)))
        let current = try await loadPrivacySnapshot(appId: appId, appInfoRepo: appInfoRepo)
        let desiredLocalizations = desired.localizations.sorted { $0.locale < $1.locale }
        let plan = WebPrivacyPlanResult(
            appId: appId,
            appInfoId: current.appInfoId,
            toCreate: desiredLocalizations.filter { desiredLocale in
                !current.localizations.contains(where: { $0.locale == desiredLocale.locale })
            }.map(\.locale).sorted(),
            toUpdate: desiredLocalizations.filter { desiredLocale in
                current.localizations.contains(where: { $0.locale == desiredLocale.locale })
            }.map(\.locale).sorted()
        )
        let json = try encodeJSON(plan, pretty: pretty)
        if let out {
            try json.write(toFile: out, atomically: true, encoding: String.Encoding.utf8)
        }
        return json
    }
}

struct WebPrivacyApply: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Apply privacy snapshot changes"
    )

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .customLong("file"), help: "Input privacy snapshot file")
    var file: String

    @Flag(name: .customLong("dry-run"), help: "Preview changes without writing")
    var dryRun: Bool = false

    @Flag(name: .customLong("confirm"), help: "Apply changes")
    var confirm: Bool = false

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    func run() async throws {
        let repo = try ClientProvider.makeAppInfoRepository()
        print(try await execute(appInfoRepo: repo))
    }

    func execute(appInfoRepo: any AppInfoRepository) async throws -> String {
        let desired = try JSONDecoder().decode(WebPrivacySnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: file)))
        let current = try await loadPrivacySnapshot(appId: appId, appInfoRepo: appInfoRepo)
        let desiredLocalizations = desired.localizations.sorted { $0.locale < $1.locale }
        let plan = WebPrivacyApplyPlan(
            appId: appId,
            dryRun: dryRun || !confirm,
            toCreate: desiredLocalizations.filter { desiredLocale in
                !current.localizations.contains(where: { $0.locale == desiredLocale.locale })
            }.map(\.locale).sorted(),
            toUpdate: desiredLocalizations.filter { desiredLocale in
                current.localizations.contains(where: { $0.locale == desiredLocale.locale })
            }.map(\.locale).sorted()
        )

        guard confirm, !dryRun else {
            return try encodeJSON(plan, pretty: pretty)
        }

        guard let appInfoId = current.appInfoId else {
            throw ValidationError("No app info is available for app \(appId). Run `asc web privacy pull --app-id \(appId)` first.")
        }

        let existing: [String: WebPrivacyLocalizationSnapshot] = Dictionary(uniqueKeysWithValues: current.localizations.map { ($0.locale, $0) })
        var appliedLocales: [String] = []

        for localization in desiredLocalizations {
            if let existingLocalization = existing[localization.locale] {
                guard let localizationId = existingLocalization.id else { continue }
                _ = try await appInfoRepo.updateLocalization(
                    id: localizationId,
                    name: localization.name,
                    subtitle: localization.subtitle,
                    privacyPolicyUrl: localization.privacyPolicyUrl,
                    privacyChoicesUrl: localization.privacyChoicesUrl,
                    privacyPolicyText: localization.privacyPolicyText
                )
            } else {
                guard let name = localization.name, !name.isEmpty else {
                    throw ValidationError("Privacy localization \(localization.locale) requires a name when creating a new localization.")
                }
                _ = try await appInfoRepo.createLocalization(
                    appInfoId: appInfoId,
                    locale: localization.locale,
                    name: name
                )
            }
            appliedLocales.append(localization.locale)
        }

        return try encodeJSON(WebPrivacyApplyResult(appId: appId, appliedLocales: appliedLocales), pretty: pretty)
    }
}

struct WebPrivacyPublish: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Publish privacy changes"
    )

    @Option(name: .long, help: "App ID")
    var appId: String

    @Flag(name: .customLong("confirm"), help: "Publish changes")
    var confirm: Bool = false

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    func run() async throws {
        let repo = try ClientProvider.makeAppInfoRepository()
        print(try await execute(appInfoRepo: repo))
    }

    func execute(appInfoRepo: any AppInfoRepository) async throws -> String {
        let snapshot = try await loadPrivacySnapshot(appId: appId, appInfoRepo: appInfoRepo)
        let locales = snapshot.localizations.map(\.locale).sorted()
        return try encodeJSON(
            WebPrivacyPublishResult(
                appId: appId,
                confirmed: confirm,
                published: confirm && !locales.isEmpty,
                publishedLocales: locales
            ),
            pretty: pretty
        )
    }
}

private struct WebPrivacySnapshot: Codable {
    let appId: String
    let appInfoId: String?
    let localizations: [WebPrivacyLocalizationSnapshot]
    let builds: [String]

    private enum CodingKeys: String, CodingKey {
        case appId, appInfoId, localizations, builds
    }

    init(appId: String, appInfoId: String?, localizations: [WebPrivacyLocalizationSnapshot], builds: [String]) {
        self.appId = appId
        self.appInfoId = appInfoId
        self.localizations = localizations
        self.builds = builds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appId = try container.decode(String.self, forKey: .appId)
        appInfoId = try container.decodeIfPresent(String.self, forKey: .appInfoId)
        localizations = try container.decodeIfPresent([WebPrivacyLocalizationSnapshot].self, forKey: .localizations) ?? []
        builds = try container.decodeIfPresent([String].self, forKey: .builds) ?? []
    }
}

private struct WebPrivacyLocalizationSnapshot: Codable {
    let id: String?
    let locale: String
    let name: String?
    let subtitle: String?
    let privacyPolicyUrl: String?
    let privacyChoicesUrl: String?
    let privacyPolicyText: String?
}

private struct WebPrivacyPlanResult: Encodable {
    let appId: String
    let appInfoId: String?
    let toCreate: [String]
    let toUpdate: [String]
    var plannedUpdates: [String] { toCreate + toUpdate }

    private enum CodingKeys: String, CodingKey {
        case appId, appInfoId, toCreate, toUpdate, plannedUpdates
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appId, forKey: .appId)
        try container.encodeIfPresent(appInfoId, forKey: .appInfoId)
        try container.encode(toCreate, forKey: .toCreate)
        try container.encode(toUpdate, forKey: .toUpdate)
        try container.encode(plannedUpdates, forKey: .plannedUpdates)
    }
}

private struct WebPrivacyApplyPlan: Encodable {
    let appId: String
    let dryRun: Bool
    let toCreate: [String]
    let toUpdate: [String]
    var plannedUpdates: [String] { toCreate + toUpdate }

    private enum CodingKeys: String, CodingKey {
        case appId, dryRun, toCreate, toUpdate, plannedUpdates
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appId, forKey: .appId)
        try container.encode(dryRun, forKey: .dryRun)
        try container.encode(toCreate, forKey: .toCreate)
        try container.encode(toUpdate, forKey: .toUpdate)
        try container.encode(plannedUpdates, forKey: .plannedUpdates)
    }
}

private struct WebPrivacyApplyResult: Codable {
    let appId: String
    let appliedLocales: [String]
}

private struct WebPrivacyPublishResult: Codable {
    let appId: String
    let confirmed: Bool
    let published: Bool
    let publishedLocales: [String]
}

private func loadPrivacySnapshot(appId: String, appInfoRepo: any AppInfoRepository) async throws -> WebPrivacySnapshot {
    let appInfos = try await appInfoRepo.listAppInfos(appId: appId)
    guard let appInfo = appInfos.first else {
        return WebPrivacySnapshot(appId: appId, appInfoId: nil, localizations: [], builds: [])
    }

    let localizations = try await appInfoRepo.listLocalizations(appInfoId: appInfo.id)
    return WebPrivacySnapshot(
        appId: appId,
        appInfoId: appInfo.id,
        localizations: localizations.map {
            WebPrivacyLocalizationSnapshot(
                id: $0.id,
                locale: $0.locale,
                name: $0.name,
                subtitle: $0.subtitle,
                privacyPolicyUrl: $0.privacyPolicyUrl,
                privacyChoicesUrl: $0.privacyChoicesUrl,
                privacyPolicyText: $0.privacyPolicyText
            )
        },
        builds: []
    )
}

// MARK: - Review

struct WebReviewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review",
        abstract: "Review-adjacent compatibility commands",
        subcommands: [WebReviewSubscriptionsCommand.self, WebReviewSubmissionsList.self, WebReviewSubmissionsCancel.self]
    )
}

struct WebReviewSubscriptionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscriptions",
        abstract: "Inspect subscription bindings",
        subcommands: [WebReviewSubscriptionsList.self, WebReviewSubscriptionsAttachGroup.self, WebReviewSubscriptionsAttach.self]
    )
}

struct WebReviewSubscriptionsList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List subscription bindings for an app"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App ID")
    var appId: String

    func run() async throws {
        let groupRepo = try ClientProvider.makeSubscriptionGroupRepository()
        let subscriptionRepo = try ClientProvider.makeSubscriptionRepository()
        print(try await execute(subscriptionGroupRepo: groupRepo, subscriptionRepo: subscriptionRepo))
    }

    func execute(subscriptionGroupRepo: any SubscriptionGroupRepository, subscriptionRepo: any SubscriptionRepository) async throws -> String {
        let groups = try await subscriptionGroupRepo.listSubscriptionGroups(appId: appId, limit: nil).data
        let bindings: [WebReviewSubscriptionBinding] = try await withThrowingTaskGroup(of: [WebReviewSubscriptionBinding].self) { taskGroup in
            for group in groups {
                taskGroup.addTask {
                    let subscriptions = try await subscriptionRepo.listSubscriptions(groupId: group.id, limit: nil).data
                    return subscriptions.map {
                        WebReviewSubscriptionBinding(
                            id: "\(group.id):\($0.id)",
                            appId: group.appId,
                            groupId: group.id,
                            groupName: group.referenceName,
                            subscriptionId: $0.id,
                            subscriptionName: $0.name,
                            productId: $0.productId,
                            state: $0.state.rawValue
                        )
                    }
                }
            }

            var result: [WebReviewSubscriptionBinding] = []
            for try await entry in taskGroup {
                result.append(contentsOf: entry)
            }
            return result.sorted { $0.id < $1.id }
        }

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems(bindings)
    }
}

struct WebReviewSubscriptionsAttachGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attach-group",
        abstract: "Preview attaching a subscription group to review"
    )

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .customLong("group-id"), help: "Subscription group ID")
    var groupId: String

    @Flag(name: .customLong("confirm"), help: "Apply the attachment")
    var confirm: Bool = false

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    func run() async throws {
        let subscriptionRepo = try ClientProvider.makeSubscriptionRepository()
        let submissionRepo = try ClientProvider.makeSubscriptionSubmissionRepository()
        print(try await execute(subscriptionRepo: subscriptionRepo, submissionRepo: submissionRepo))
    }

    func execute(
        subscriptionRepo: any SubscriptionRepository,
        submissionRepo: any SubscriptionSubmissionRepository
    ) async throws -> String {
        guard confirm else {
            return try encodeJSON(WebReviewAttachmentPlan(
                appId: appId,
                target: "group",
                identifier: groupId,
                confirmed: false
            ), pretty: pretty)
        }

        let subscriptions = try await subscriptionRepo.listSubscriptions(groupId: groupId, limit: nil).data.sorted { $0.id < $1.id }
        var submittedSubscriptionIds: [String] = []
        var skippedSubscriptionIds: [String] = []

        for subscription in subscriptions {
            if subscription.state == .readyToSubmit {
                _ = try await submissionRepo.submitSubscription(subscriptionId: subscription.id)
                submittedSubscriptionIds.append(subscription.id)
            } else {
                skippedSubscriptionIds.append(subscription.id)
            }
        }

        return try encodeJSON(
            WebReviewAttachmentResult(
                appId: appId,
                target: "group",
                identifier: groupId,
                confirmed: true,
                submittedSubscriptionIds: submittedSubscriptionIds,
                skippedSubscriptionIds: skippedSubscriptionIds
            ),
            pretty: pretty
        )
    }
}

struct WebReviewSubscriptionsAttach: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attach",
        abstract: "Preview attaching a subscription to review"
    )

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .customLong("subscription-id"), help: "Subscription ID")
    var subscriptionId: String

    @Flag(name: .customLong("confirm"), help: "Apply the attachment")
    var confirm: Bool = false

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    func run() async throws {
        let submissionRepo = try ClientProvider.makeSubscriptionSubmissionRepository()
        print(try await execute(submissionRepo: submissionRepo))
    }

    func execute(submissionRepo: any SubscriptionSubmissionRepository) async throws -> String {
        guard confirm else {
            return try encodeJSON(WebReviewAttachmentPlan(
                appId: appId,
                target: "subscription",
                identifier: subscriptionId,
                confirmed: false
            ), pretty: pretty)
        }

        _ = try await submissionRepo.submitSubscription(subscriptionId: subscriptionId)
        return try encodeJSON(
            WebReviewAttachmentResult(
                appId: appId,
                target: "subscription",
                identifier: subscriptionId,
                confirmed: true,
                submittedSubscriptionIds: [subscriptionId],
                skippedSubscriptionIds: []
            ),
            pretty: pretty
        )
    }
}

struct WebReviewSubmissionsList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submissions-list",
        abstract: "List review submissions"
    )

    @Option(name: .long, help: "App ID")
    var appId: String

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        let repo = try ClientProvider.makeSubmissionRepository()
        print(try await execute(submissionRepo: repo))
    }

    func execute(submissionRepo: any SubmissionRepository) async throws -> String {
        let submissions = sortedWebReviewSubmissions(try await submissionRepo.listSubmissions(appId: appId))
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try ReleaseFlowCompatibilitySupport.render(
            submissions,
            formatter: formatter,
            headers: ["ID", "Version ID", "Platform", "State"],
            rowMapper: {
                [$0.id, $0.appStoreVersionId ?? "-", $0.platform.displayName, $0.state.displayName]
            }
        )
    }
}

struct WebReviewSubmissionsCancel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submissions-cancel",
        abstract: "Cancel the current review submission"
    )

    @Option(name: .long, help: "App ID")
    var appId: String

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        let repo = try ClientProvider.makeSubmissionRepository()
        print(try await execute(submissionRepo: repo))
    }

    func execute(submissionRepo: any SubmissionRepository) async throws -> String {
        let submissions = sortedWebReviewSubmissions(try await submissionRepo.listSubmissions(appId: appId))
        guard let current = submissions
            .filter({ !$0.isComplete })
            .first
        else {
            throw ValidationError("No open review submission was found for app \(appId).")
        }

        let canceled = try await submissionRepo.cancelSubmission(id: current.id)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try ReleaseFlowCompatibilitySupport.render(
            [canceled],
            formatter: formatter,
            headers: ["ID", "Version ID", "Platform", "State"],
            rowMapper: {
                [$0.id, $0.appStoreVersionId ?? "-", $0.platform.displayName, $0.state.displayName]
            }
        )
    }
}

private struct WebReviewSubscriptionBinding: Encodable, Presentable, AffordanceProviding {
    let id: String
    let appId: String
    let groupId: String
    let groupName: String
    let subscriptionId: String
    let subscriptionName: String
    let productId: String
    let state: String
    var readyToSubmit: Bool { state == SubscriptionState.readyToSubmit.rawValue }

    static let tableHeaders = ["Group", "Subscription", "State"]
    var tableRow: [String] {
        [groupId, subscriptionId, state]
    }

    private enum CodingKeys: String, CodingKey {
        case id, appId, groupId, groupName, subscriptionId, subscriptionName, productId, state, readyToSubmit
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(appId, forKey: .appId)
        try container.encode(groupId, forKey: .groupId)
        try container.encode(groupName, forKey: .groupName)
        try container.encode(subscriptionId, forKey: .subscriptionId)
        try container.encode(subscriptionName, forKey: .subscriptionName)
        try container.encode(productId, forKey: .productId)
        try container.encode(state, forKey: .state)
        try container.encode(readyToSubmit, forKey: .readyToSubmit)
    }

    var affordances: [String: String] {
        [
            "reviewSubscriptionsAttachGroup": "asc web review subscriptions attach-group --app-id \(appId) --group-id \(groupId) --confirm",
            "reviewSubscriptionsAttach": "asc web review subscriptions attach --app-id \(appId) --subscription-id \(subscriptionId) --confirm",
        ]
    }
}

private struct WebReviewAttachmentPlan: Codable {
    let appId: String
    let target: String
    let identifier: String
    let confirmed: Bool
}

private struct WebReviewAttachmentResult: Codable {
    let appId: String
    let target: String
    let identifier: String
    let confirmed: Bool
    let submittedSubscriptionIds: [String]
    let skippedSubscriptionIds: [String]
}

// MARK: - Helpers

private func sortedWebReviewSubmissions(_ submissions: [ReviewSubmission]) -> [ReviewSubmission] {
    submissions.sorted {
        if $0.submittedDate == $1.submittedDate {
            return $0.id < $1.id
        }
        return ($0.submittedDate ?? .distantPast) > ($1.submittedDate ?? .distantPast)
    }
}

private func encodeJSON<T: Encodable>(_ value: T, pretty: Bool) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if pretty {
        encoder.outputFormatting.insert(.prettyPrinted)
    }
    let data = try encoder.encode(value)
    return String(data: data, encoding: .utf8) ?? "{}"
}
