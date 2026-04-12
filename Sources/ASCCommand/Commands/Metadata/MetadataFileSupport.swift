import ArgumentParser
import Domain
import Foundation

enum MetadataFileSupport {
    static func versionLocalizationsDirectory(root: URL) -> URL {
        root.appendingPathComponent("version-localizations")
    }

    static func appInfoLocalizationsDirectory(root: URL) -> URL {
        root.appendingPathComponent("app-info-localizations")
    }

    static func metadataManifestURL(root: URL) -> URL {
        root.appendingPathComponent("metadata.json")
    }

    static func writeVersionLocalization(_ localization: AppStoreVersionLocalization, root: URL) throws {
        let url = versionLocalizationsDirectory(root: root).appendingPathComponent("\(localization.locale).json")
        try LocalizationFileSupport.writeJSON(localization, to: url)
    }

    static func writeAppInfoLocalization(_ localization: AppInfoLocalization, root: URL) throws {
        let url = appInfoLocalizationsDirectory(root: root)
            .appendingPathComponent(localization.appInfoId)
            .appendingPathComponent("\(localization.locale).json")
        try LocalizationFileSupport.writeJSON(localization, to: url)
    }

    static func readVersionLocalizations(root: URL) throws -> [MetadataVersionLocalizationFile] {
        let scan = scanWorkspace(root: root)
        try throwIfNeeded(scan.errors)
        return scan.versionFiles
    }

    static func readAppInfoLocalizations(root: URL) throws -> [MetadataAppInfoLocalizationFile] {
        let scan = scanWorkspace(root: root)
        try throwIfNeeded(scan.errors)
        return scan.appInfoFiles
    }

    static func validate(root: URL) -> MetadataValidationReport {
        let scan = scanWorkspace(root: root)
        return MetadataValidationReport(
            valid: scan.errors.isEmpty,
            root: root.path,
            versionFileCount: scan.versionFiles.count,
            appInfoFileCount: scan.appInfoFiles.count,
            errors: scan.errors
        )
    }

    static func writeManifest(_ manifest: MetadataManifest, root: URL) throws {
        try LocalizationFileSupport.writeJSON(manifest, to: metadataManifestURL(root: root))
    }

    static func scanWorkspace(root: URL) -> MetadataWorkspaceScan {
        var errors: [String] = []
        let manifest = readManifest(root: root, errors: &errors)
        let versionFiles = collectVersionLocalizationFiles(root: root, manifestVersionId: manifest?.versionId, errors: &errors)
        let appInfoFiles = collectAppInfoLocalizationFiles(root: root, manifestAppInfoIds: manifest.map { Set($0.appInfoIds) }, errors: &errors)

        if let manifest {
            if versionFiles.count != manifest.versionLocalizationCount {
                errors.append("Metadata manifest expects \(manifest.versionLocalizationCount) version localization files, found \(versionFiles.count).")
            }

            if appInfoFiles.count != manifest.appInfoLocalizationCount {
                errors.append("Metadata manifest expects \(manifest.appInfoLocalizationCount) app-info localization files, found \(appInfoFiles.count).")
            }

            let foundAppInfoIds = Set(appInfoFiles.map(\.appInfoId))
            for appInfoId in manifest.appInfoIds.sorted() where !foundAppInfoIds.contains(appInfoId) {
                errors.append("Metadata manifest lists app info \(appInfoId), but no localization files were found for it.")
            }
        }

        if versionFiles.isEmpty && appInfoFiles.isEmpty {
            errors.append("No localization JSON files were found in \(root.path).")
        }

        return MetadataWorkspaceScan(manifest: manifest, versionFiles: versionFiles, appInfoFiles: appInfoFiles, errors: errors)
    }

    private static func readManifest(root: URL, errors: inout [String]) -> MetadataManifest? {
        let url = metadataManifestURL(root: root)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errors.append("Missing metadata manifest at \(url.path).")
            return nil
        }

        do {
            return try LocalizationFileSupport.readJSON(MetadataManifest.self, from: url)
        } catch {
            errors.append("Malformed JSON in metadata manifest at \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    private static func collectVersionLocalizationFiles(
        root: URL,
        manifestVersionId: String?,
        errors: inout [String]
    ) -> [MetadataVersionLocalizationFile] {
        let directory = versionLocalizationsDirectory(root: root)
        let files = LocalizationFileSupport.jsonFiles(in: directory).sorted(by: { $0.path < $1.path })
        var result: [MetadataVersionLocalizationFile] = []

        for url in files {
            guard let relativePath = relativePath(of: url, under: directory) else {
                errors.append("Version localization file \(url.path) is outside \(directory.path).")
                continue
            }

            let components = relativePath.split(separator: "/").map(String.init)
            guard components.count == 1 else {
                errors.append("Version localization file \(relativePath) must be stored at version-localizations/<locale>.json.")
                continue
            }

            let fileLocale = URL(fileURLWithPath: components[0]).deletingPathExtension().lastPathComponent
            do {
                let localization = try LocalizationFileSupport.readJSON(AppStoreVersionLocalization.self, from: url)
                if localization.locale != fileLocale {
                    errors.append("Version localization \(relativePath) stores locale \(localization.locale), but the file name declares \(fileLocale).")
                    continue
                }
                if let manifestVersionId, localization.versionId != manifestVersionId {
                    errors.append("Version localization \(relativePath) belongs to version \(localization.versionId), but metadata manifest expects version \(manifestVersionId).")
                    continue
                }
                result.append(.init(fileURL: url, localization: localization))
            } catch {
                errors.append("Malformed JSON in \(relativePath): \(error.localizedDescription)")
            }
        }

        return result
    }

    private static func collectAppInfoLocalizationFiles(
        root: URL,
        manifestAppInfoIds: Set<String>?,
        errors: inout [String]
    ) -> [MetadataAppInfoLocalizationFile] {
        let directory = appInfoLocalizationsDirectory(root: root)
        let files = LocalizationFileSupport.jsonFiles(in: directory).sorted(by: { $0.path < $1.path })
        var result: [MetadataAppInfoLocalizationFile] = []

        for url in files {
            guard let relativePath = relativePath(of: url, under: directory) else {
                errors.append("App info localization file \(url.path) is outside \(directory.path).")
                continue
            }

            let components = relativePath.split(separator: "/").map(String.init)
            guard components.count == 2 else {
                errors.append("App info localization file \(relativePath) must be stored under app-info-localizations/<appInfoId>/<locale>.json.")
                continue
            }

            let appInfoId = components[0]
            let fileLocale = URL(fileURLWithPath: components[1]).deletingPathExtension().lastPathComponent
            do {
                let localization = try LocalizationFileSupport.readJSON(AppInfoLocalization.self, from: url)
                if localization.locale != fileLocale {
                    errors.append("App info localization \(relativePath) stores locale \(localization.locale), but the file name declares \(fileLocale).")
                    continue
                }
                if localization.appInfoId != appInfoId {
                    errors.append("App info localization \(relativePath) belongs to app info \(localization.appInfoId), but the path declares \(appInfoId).")
                    continue
                }
                if let manifestAppInfoIds, manifestAppInfoIds.contains(appInfoId) == false {
                    errors.append("App info localization \(relativePath) belongs to app info \(appInfoId), but metadata manifest does not list that app info.")
                    continue
                }
                result.append(.init(fileURL: url, appInfoId: appInfoId, localization: localization))
            } catch {
                errors.append("Malformed JSON in \(relativePath): \(error.localizedDescription)")
            }
        }

        return result
    }

    private static func relativePath(of fileURL: URL, under directory: URL) -> String? {
        let basePath = directory.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(basePath) else { return nil }

        let remainder = String(filePath.dropFirst(basePath.count))
        guard remainder.hasPrefix("/") else { return nil }
        return String(remainder.dropFirst())
    }

    private static func throwIfNeeded(_ errors: [String]) throws {
        guard errors.isEmpty else {
            throw ValidationError(errors.joined(separator: "\n"))
        }
    }
}

struct MetadataVersionLocalizationFile {
    let fileURL: URL
    let localization: AppStoreVersionLocalization
}

struct MetadataAppInfoLocalizationFile {
    let fileURL: URL
    let appInfoId: String
    let localization: AppInfoLocalization
}

struct MetadataManifest: Codable {
    let appId: String
    let version: String
    let versionId: String
    let appInfoIds: [String]
    let versionLocalizationCount: Int
    let appInfoLocalizationCount: Int
}

struct MetadataValidationReport: Codable {
    let valid: Bool
    let root: String
    let versionFileCount: Int
    let appInfoFileCount: Int
    let errors: [String]
}

struct MetadataSyncAction: Codable {
    let scope: String
    let file: String
    let locale: String
    let operation: String
    let localizationId: String
}

struct MetadataSyncSummary: Codable {
    let mode: String
    let root: String
    let createdCount: Int
    let updatedCount: Int
    let actions: [MetadataSyncAction]
}

struct MetadataExportSummary: Codable {
    let mode: String
    let appId: String
    let version: String
    let versionId: String
    let root: String
    let appInfoIds: [String]
    let versionLocalizationCount: Int
    let appInfoLocalizationCount: Int
}

enum MetadataSyncMode: String {
    case export
    case import_ = "import"
}

struct MetadataWorkspaceScan {
    let manifest: MetadataManifest?
    let versionFiles: [MetadataVersionLocalizationFile]
    let appInfoFiles: [MetadataAppInfoLocalizationFile]
    let errors: [String]
}
