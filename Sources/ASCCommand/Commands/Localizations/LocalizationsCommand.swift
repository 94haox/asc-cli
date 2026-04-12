import ArgumentParser
import Domain
import Foundation

struct LocalizationsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "localizations",
        abstract: "Compatibility entrypoint for version and app-info localizations",
        subcommands: [LocalizationsList.self, LocalizationsDownload.self, LocalizationsUpload.self]
    )
}

enum LocalizationTargetType: String, ExpressibleByArgument {
    case version
    case appInfo = "app-info"
}

struct LocalizationsList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List localizations")

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "Localization target type") var type: LocalizationTargetType = .version
    @Option(name: .long, help: "App Store version ID") var version: String?
    @Option(name: .long, help: "App ID") var app: String?
    @Option(name: .long, help: "App info ID") var appInfo: String?

    func run() async throws {
        let versionRepo = try ClientProvider.makeVersionLocalizationRepository()
        let appInfoRepo = try ClientProvider.makeAppInfoRepository()
        print(try await execute(versionRepo: versionRepo, appInfoRepo: appInfoRepo))
    }

    func execute(
        versionRepo: any VersionLocalizationRepository,
        appInfoRepo: any AppInfoRepository
    ) async throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        switch type {
        case .version:
            guard let version else { throw ValidationError("Provide --version for version localizations.") }
            return try formatter.formatAgentItems(try await versionRepo.listLocalizations(versionId: version))
        case .appInfo:
            _ = app
            guard let appInfo else { throw ValidationError("Provide --app-info for app-info localizations.") }
            let items = try await appInfoRepo.listLocalizations(appInfoId: appInfo)
            return try formatter.formatAgentItems(
                items,
                headers: ["ID", "Locale", "Name", "Subtitle"],
                rowMapper: { [$0.id, $0.locale, $0.name ?? "-", $0.subtitle ?? "-"] }
            )
        }
    }
}

struct LocalizationsDownload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "download", abstract: "Download localizations to disk")

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "Localization target type") var type: LocalizationTargetType = .version
    @Option(name: .long, help: "App Store version ID") var version: String?
    @Option(name: .long, help: "App ID") var app: String?
    @Option(name: .long, help: "App info ID") var appInfo: String?
    @Option(name: .long, help: "Output directory") var path: String

    func run() async throws {
        let versionRepo = try ClientProvider.makeVersionLocalizationRepository()
        let appInfoRepo = try ClientProvider.makeAppInfoRepository()
        print(try await execute(versionRepo: versionRepo, appInfoRepo: appInfoRepo))
    }

    func execute(
        versionRepo: any VersionLocalizationRepository,
        appInfoRepo: any AppInfoRepository
    ) async throws -> String {
        let outputURL = URL(fileURLWithPath: path)
        try LocalizationFileSupport.ensureDirectory(at: outputURL)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)

        switch type {
        case .version:
            guard let version else { throw ValidationError("Provide --version for version localizations.") }
            let items = try await versionRepo.listLocalizations(versionId: version)
            var payload: [String: AppStoreVersionLocalization] = [:]
            for item in items {
                payload[item.locale] = item
                try LocalizationFileSupport.writeJSON(item, to: outputURL.appendingPathComponent("\(item.locale).json"))
            }
            return try formatter.format(payload)
        case .appInfo:
            _ = app
            guard let appInfo else { throw ValidationError("Provide --app-info for app-info localizations.") }
            let items = try await appInfoRepo.listLocalizations(appInfoId: appInfo)
            var payload: [String: AppInfoLocalization] = [:]
            for item in items {
                payload[item.locale] = item
                try LocalizationFileSupport.writeJSON(item, to: outputURL.appendingPathComponent("\(item.locale).json"))
            }
            return try formatter.format(payload)
        }
    }
}

struct LocalizationsUpload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "upload", abstract: "Upload localizations from disk")

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "Localization target type") var type: LocalizationTargetType = .version
    @Option(name: .long, help: "App Store version ID") var version: String?
    @Option(name: .long, help: "App ID") var app: String?
    @Option(name: .long, help: "App info ID") var appInfo: String?
    @Option(name: .long, help: "Input directory") var path: String

    func run() async throws {
        let versionRepo = try ClientProvider.makeVersionLocalizationRepository()
        let appInfoRepo = try ClientProvider.makeAppInfoRepository()
        print(try await execute(versionRepo: versionRepo, appInfoRepo: appInfoRepo))
    }

    func execute(
        versionRepo: any VersionLocalizationRepository,
        appInfoRepo: any AppInfoRepository
    ) async throws -> String {
        let files = LocalizationFileSupport.jsonFiles(in: URL(fileURLWithPath: path))
        guard !files.isEmpty else {
            throw ValidationError("No localization JSON files found at \(path).")
        }

        switch type {
        case .version:
            guard let version else { throw ValidationError("Provide --version for version localizations.") }
            let existing = try await versionRepo.listLocalizations(versionId: version)
            return try await applyVersionUpload(
                versionId: version,
                files: files,
                existing: existing,
                repo: versionRepo
            )
        case .appInfo:
            _ = app
            guard let appInfo else { throw ValidationError("Provide --app-info for app-info localizations.") }
            let existing = try await appInfoRepo.listLocalizations(appInfoId: appInfo)
            return try await applyAppInfoUpload(
                appInfoId: appInfo,
                files: files,
                existing: existing,
                repo: appInfoRepo
            )
        }
    }
}

private extension LocalizationsUpload {
    func applyVersionUpload(
        versionId: String,
        files: [URL],
        existing: [AppStoreVersionLocalization],
        repo: any VersionLocalizationRepository
    ) async throws -> String {
        var actions: [LocalizationUploadAction] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let localization = try LocalizationFileSupport.readJSON(AppStoreVersionLocalization.self, from: file)
            if let current = existing.first(where: { $0.locale == localization.locale }) {
                let updated = try await repo.updateLocalization(
                    localizationId: current.id,
                    whatsNew: localization.whatsNew,
                    description: localization.description,
                    keywords: localization.keywords,
                    marketingUrl: localization.marketingUrl,
                    supportUrl: localization.supportUrl,
                    promotionalText: localization.promotionalText
                )
                actions.append(.init(file: file.lastPathComponent, locale: localization.locale, operation: "updated", localizationId: updated.id))
            } else {
                let created = try await repo.createLocalization(versionId: versionId, locale: localization.locale)
                let hasContent = localization.whatsNew != nil
                    || localization.description != nil
                    || localization.keywords != nil
                    || localization.marketingUrl != nil
                    || localization.supportUrl != nil
                    || localization.promotionalText != nil
                let final = hasContent
                    ? try await repo.updateLocalization(
                        localizationId: created.id,
                        whatsNew: localization.whatsNew,
                        description: localization.description,
                        keywords: localization.keywords,
                        marketingUrl: localization.marketingUrl,
                        supportUrl: localization.supportUrl,
                        promotionalText: localization.promotionalText
                    )
                    : created
                actions.append(.init(file: file.lastPathComponent, locale: localization.locale, operation: hasContent ? "created+updated" : "created", localizationId: final.id))
            }
        }

        return try OutputFormatter(format: globals.outputFormat, pretty: globals.pretty).format(
            LocalizationUploadSummary(
                type: type.rawValue,
                path: path,
                sourceFiles: files.map(\.lastPathComponent),
                createdCount: actions.filter { $0.operation.contains("created") }.count,
                updatedCount: actions.filter { $0.operation.contains("updated") }.count,
                actions: actions
            )
        )
    }

    func applyAppInfoUpload(
        appInfoId: String,
        files: [URL],
        existing: [AppInfoLocalization],
        repo: any AppInfoRepository
    ) async throws -> String {
        var actions: [LocalizationUploadAction] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let localization = try LocalizationFileSupport.readJSON(AppInfoLocalization.self, from: file)
            if let current = existing.first(where: { $0.locale == localization.locale }) {
                let updated = try await repo.updateLocalization(
                    id: current.id,
                    name: localization.name,
                    subtitle: localization.subtitle,
                    privacyPolicyUrl: localization.privacyPolicyUrl,
                    privacyChoicesUrl: localization.privacyChoicesUrl,
                    privacyPolicyText: localization.privacyPolicyText
                )
                actions.append(.init(file: file.lastPathComponent, locale: localization.locale, operation: "updated", localizationId: updated.id))
            } else {
                guard let name = localization.name else {
                    throw ValidationError("App info localization \(file.lastPathComponent) must include name.")
                }
                let created = try await repo.createLocalization(appInfoId: appInfoId, locale: localization.locale, name: name)
                let hasContent = localization.subtitle != nil
                    || localization.privacyPolicyUrl != nil
                    || localization.privacyChoicesUrl != nil
                    || localization.privacyPolicyText != nil
                let final = hasContent
                    ? try await repo.updateLocalization(
                        id: created.id,
                        name: localization.name,
                        subtitle: localization.subtitle,
                        privacyPolicyUrl: localization.privacyPolicyUrl,
                        privacyChoicesUrl: localization.privacyChoicesUrl,
                        privacyPolicyText: localization.privacyPolicyText
                    )
                    : created
                actions.append(.init(file: file.lastPathComponent, locale: localization.locale, operation: hasContent ? "created+updated" : "created", localizationId: final.id))
            }
        }

        return try OutputFormatter(format: globals.outputFormat, pretty: globals.pretty).format(
            LocalizationUploadSummary(
                type: type.rawValue,
                path: path,
                sourceFiles: files.map(\.lastPathComponent),
                createdCount: actions.filter { $0.operation.contains("created") }.count,
                updatedCount: actions.filter { $0.operation.contains("updated") }.count,
                actions: actions
            )
        )
    }
}

private struct LocalizationUploadSummary: Codable {
    let type: String
    let path: String
    let sourceFiles: [String]
    let createdCount: Int
    let updatedCount: Int
    let actions: [LocalizationUploadAction]
}

private struct LocalizationUploadAction: Codable {
    let file: String
    let locale: String
    let operation: String
    let localizationId: String
}
