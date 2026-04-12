import ArgumentParser
import Domain
import Foundation

enum MetadataWorkflowSupport {
    static func resolveVersion(
        appId: String,
        version: String,
        versionRepo: any VersionRepository
    ) async throws -> AppStoreVersion {
        let versions = try await versionRepo.listVersions(appId: appId)
        guard let version = versions.first(where: { $0.versionString == version }) else {
            throw ValidationError("Version \(version) was not found for app \(appId).")
        }
        return version
    }

    static func exportMetadata(
        appId: String,
        version: String,
        outputDir: String,
        versionRepo: any VersionRepository,
        versionLocalizationRepo: any VersionLocalizationRepository,
        appInfoRepo: any AppInfoRepository
    ) async throws -> MetadataExportSummary {
        let versionRecord = try await resolveVersion(appId: appId, version: version, versionRepo: versionRepo)
        let appInfos = try await appInfoRepo.listAppInfos(appId: appId).sorted(by: { $0.id < $1.id })
        let versionLocalizations = try await versionLocalizationRepo.listLocalizations(versionId: versionRecord.id).sorted(by: { $0.locale < $1.locale })
        var appInfoLocalizationCount = 0

        let root = URL(fileURLWithPath: outputDir)
        try LocalizationFileSupport.ensureDirectory(at: MetadataFileSupport.versionLocalizationsDirectory(root: root))
        try LocalizationFileSupport.ensureDirectory(at: MetadataFileSupport.appInfoLocalizationsDirectory(root: root))

        for localization in versionLocalizations {
            try MetadataFileSupport.writeVersionLocalization(localization, root: root)
        }

        for appInfo in appInfos {
            let localizations = try await appInfoRepo.listLocalizations(appInfoId: appInfo.id).sorted(by: { $0.locale < $1.locale })
            appInfoLocalizationCount += localizations.count
            for localization in localizations {
                try MetadataFileSupport.writeAppInfoLocalization(localization, root: root)
            }
        }

        try MetadataFileSupport.writeManifest(
            MetadataManifest(
                appId: appId,
                version: version,
                versionId: versionRecord.id,
                appInfoIds: appInfos.map(\.id),
                versionLocalizationCount: versionLocalizations.count,
                appInfoLocalizationCount: appInfoLocalizationCount
            ),
            root: root
        )

        return MetadataExportSummary(
            mode: "export",
            appId: appId,
            version: version,
            versionId: versionRecord.id,
            root: root.path,
            appInfoIds: appInfos.map(\.id),
            versionLocalizationCount: versionLocalizations.count,
            appInfoLocalizationCount: appInfoLocalizationCount
        )
    }

    static func syncMetadata(
        appId: String,
        version: String,
        root: String,
        apply: Bool,
        versionRepo: any VersionRepository,
        versionLocalizationRepo: any VersionLocalizationRepository,
        appInfoRepo: any AppInfoRepository
    ) async throws -> MetadataSyncSummary {
        let versionRecord = try await resolveVersion(appId: appId, version: version, versionRepo: versionRepo)
        let rootURL = URL(fileURLWithPath: root)
        let scan = MetadataFileSupport.scanWorkspace(root: rootURL)
        guard scan.errors.isEmpty else {
            throw ValidationError(scan.errors.joined(separator: "\n"))
        }
        let versionFiles = scan.versionFiles
        let appInfoFiles = scan.appInfoFiles

        var actions: [MetadataSyncAction] = []

        let existingVersionLocalizations = try await versionLocalizationRepo.listLocalizations(versionId: versionRecord.id)
        actions += try await syncVersionLocalizations(
            versionId: versionRecord.id,
            root: rootURL,
            files: versionFiles,
            existing: existingVersionLocalizations,
            repo: versionLocalizationRepo,
            apply: apply
        )

        let appInfoIds = Array(Set(appInfoFiles.map(\.appInfoId))).sorted()
        for appInfoId in appInfoIds {
            let existing = try await appInfoRepo.listLocalizations(appInfoId: appInfoId)
            let files = appInfoFiles.filter { $0.appInfoId == appInfoId }
            actions += try await syncAppInfoLocalizations(
                appInfoId: appInfoId,
                root: rootURL,
                files: files,
                existing: existing,
                repo: appInfoRepo,
                apply: apply
            )
        }

        return MetadataSyncSummary(
            mode: apply ? "apply" : "dry-run",
            root: rootURL.path,
            createdCount: actions.filter { $0.operation.contains("created") }.count,
            updatedCount: actions.filter { $0.operation.contains("updated") }.count,
            actions: actions
        )
    }

    static func validateMetadata(root: String) -> MetadataValidationReport {
        MetadataFileSupport.validate(root: URL(fileURLWithPath: root))
    }

    private static func syncVersionLocalizations(
        versionId: String,
        root: URL,
        files: [MetadataVersionLocalizationFile],
        existing: [AppStoreVersionLocalization],
        repo: any VersionLocalizationRepository,
        apply: Bool
    ) async throws -> [MetadataSyncAction] {
        var actions: [MetadataSyncAction] = []
        let fileLocales = Set(files.map { $0.localization.locale })

        for file in files.sorted(by: { $0.fileURL.lastPathComponent < $1.fileURL.lastPathComponent }) {
            if file.localization.versionId != versionId {
                throw ValidationError("Version localization \(file.fileURL.lastPathComponent) does not belong to version \(versionId).")
            }

            if let current = existing.first(where: { $0.locale == file.localization.locale }) {
                if apply {
                    let updated = try await repo.updateLocalization(
                        localizationId: current.id,
                        whatsNew: file.localization.whatsNew,
                        description: file.localization.description,
                        keywords: file.localization.keywords,
                        marketingUrl: file.localization.marketingUrl,
                        supportUrl: file.localization.supportUrl,
                        promotionalText: file.localization.promotionalText
                    )
                    actions.append(.init(scope: "version", file: file.fileURL.lastPathComponent, locale: file.localization.locale, operation: "updated", localizationId: updated.id))
                } else {
                    actions.append(.init(scope: "version", file: file.fileURL.lastPathComponent, locale: file.localization.locale, operation: "planned-update", localizationId: current.id))
                }
            } else {
                if apply {
                    let created = try await repo.createLocalization(versionId: versionId, locale: file.localization.locale)
                    let hasContent = file.localization.whatsNew != nil
                        || file.localization.description != nil
                        || file.localization.keywords != nil
                        || file.localization.marketingUrl != nil
                        || file.localization.supportUrl != nil
                        || file.localization.promotionalText != nil
                    let final = hasContent
                        ? try await repo.updateLocalization(
                            localizationId: created.id,
                            whatsNew: file.localization.whatsNew,
                            description: file.localization.description,
                            keywords: file.localization.keywords,
                            marketingUrl: file.localization.marketingUrl,
                            supportUrl: file.localization.supportUrl,
                            promotionalText: file.localization.promotionalText
                        )
                        : created
                    actions.append(.init(scope: "version", file: file.fileURL.lastPathComponent, locale: file.localization.locale, operation: hasContent ? "created+updated" : "created", localizationId: final.id))
                } else {
                    actions.append(.init(scope: "version", file: file.fileURL.lastPathComponent, locale: file.localization.locale, operation: "planned-create", localizationId: ""))
                }
            }
        }

        let missingExisting = existing
            .filter { fileLocales.contains($0.locale) == false }
            .sorted(by: { lhs, rhs in
                if lhs.locale != rhs.locale { return lhs.locale < rhs.locale }
                return lhs.id < rhs.id
            })
        for localization in missingExisting {
            actions.append(.init(
                scope: "version",
                file: "(missing)",
                locale: localization.locale,
                operation: apply ? "delete-unsupported" : "planned-delete-unsupported",
                localizationId: localization.id
            ))
        }

        return actions
    }

    private static func syncAppInfoLocalizations(
        appInfoId: String,
        root: URL,
        files: [MetadataAppInfoLocalizationFile],
        existing: [AppInfoLocalization],
        repo: any AppInfoRepository,
        apply: Bool
    ) async throws -> [MetadataSyncAction] {
        var actions: [MetadataSyncAction] = []
        let fileLocales = Set(files.map { $0.localization.locale })

        for file in files.sorted(by: { $0.fileURL.lastPathComponent < $1.fileURL.lastPathComponent }) {
            if file.localization.appInfoId != appInfoId {
                throw ValidationError("App info localization \(file.fileURL.lastPathComponent) does not belong to app info \(appInfoId).")
            }

            if let current = existing.first(where: { $0.locale == file.localization.locale }) {
                if apply {
                    let updated = try await repo.updateLocalization(
                        id: current.id,
                        name: file.localization.name,
                        subtitle: file.localization.subtitle,
                        privacyPolicyUrl: file.localization.privacyPolicyUrl,
                        privacyChoicesUrl: file.localization.privacyChoicesUrl,
                        privacyPolicyText: file.localization.privacyPolicyText
                    )
                    actions.append(.init(scope: "app-info", file: file.fileURL.lastPathComponent, locale: file.localization.locale, operation: "updated", localizationId: updated.id))
                } else {
                    actions.append(.init(scope: "app-info", file: file.fileURL.lastPathComponent, locale: file.localization.locale, operation: "planned-update", localizationId: current.id))
                }
            } else {
                guard let name = file.localization.name else {
                    throw ValidationError("App info localization \(file.fileURL.lastPathComponent) must include name.")
                }
                if apply {
                    let created = try await repo.createLocalization(appInfoId: appInfoId, locale: file.localization.locale, name: name)
                    let hasContent = file.localization.subtitle != nil
                        || file.localization.privacyPolicyUrl != nil
                        || file.localization.privacyChoicesUrl != nil
                        || file.localization.privacyPolicyText != nil
                    let final = hasContent
                        ? try await repo.updateLocalization(
                            id: created.id,
                            name: file.localization.name,
                            subtitle: file.localization.subtitle,
                            privacyPolicyUrl: file.localization.privacyPolicyUrl,
                            privacyChoicesUrl: file.localization.privacyChoicesUrl,
                            privacyPolicyText: file.localization.privacyPolicyText
                        )
                        : created
                    actions.append(.init(scope: "app-info", file: file.fileURL.lastPathComponent, locale: file.localization.locale, operation: hasContent ? "created+updated" : "created", localizationId: final.id))
                } else {
                    actions.append(.init(scope: "app-info", file: file.fileURL.lastPathComponent, locale: file.localization.locale, operation: "planned-create", localizationId: ""))
                }
            }
        }

        let missingExisting = existing
            .filter { fileLocales.contains($0.locale) == false }
            .sorted(by: { lhs, rhs in
                if lhs.locale != rhs.locale { return lhs.locale < rhs.locale }
                return lhs.id < rhs.id
            })
        for localization in missingExisting {
            actions.append(.init(
                scope: "app-info",
                file: "(missing)",
                locale: localization.locale,
                operation: apply ? "delete-unsupported" : "planned-delete-unsupported",
                localizationId: localization.id
            ))
        }

        return actions
    }
}
