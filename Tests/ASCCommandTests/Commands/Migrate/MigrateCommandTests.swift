import Foundation
import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct MigrateCommandTests {

    @Test func `export writes a migration workspace`() async throws {
        let appRepo = MockAppRepository()
        let versionRepo = MockVersionRepository()
        let versionLocalizationRepo = MockVersionLocalizationRepository()
        let appInfoRepo = MockAppInfoRepository()

        given(appRepo).getApp(id: .any).willReturn(
            App(id: "app-1", name: "My App", bundleId: "com.example.app")
        )
        given(versionRepo).listVersions(appId: .any).willReturn([
            AppStoreVersion(
                id: "ver-1",
                appId: "app-1",
                versionString: "1.0",
                platform: .iOS,
                state: .prepareForSubmission
            )
        ])
        given(versionLocalizationRepo).listLocalizations(versionId: .any).willReturn([
            AppStoreVersionLocalization(
                id: "vloc-en",
                versionId: "ver-1",
                locale: "en-US",
                whatsNew: "Hello"
            )
        ])
        given(appInfoRepo).listAppInfos(appId: .any).willReturn([
            AppInfo(id: "ai-1", appId: "app-1")
        ])
        given(appInfoRepo).listLocalizations(appInfoId: .any).willReturn([
            AppInfoLocalization(
                id: "iloc-en",
                appInfoId: "ai-1",
                locale: "en-US",
                name: "My App"
            )
        ])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("asc-migrate-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let cmd = try MigrateExport.parse(["--app", "app-1", "--version", "1.0", "--output-dir", root.path, "--pretty"])
        let output = try await cmd.execute(appRepo: appRepo, versionRepo: versionRepo, versionLocalizationRepo: versionLocalizationRepo, appInfoRepo: appInfoRepo)

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("version-localizations/en-US.json").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("app-info-localizations/ai-1/en-US.json").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("metadata.json").path))
        #expect(output.contains("\"mode\" : \"export\""))
    }

    @Test func `validate reports migration workspace health`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("asc-migrate-validate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        try MetadataFileSupport.writeVersionLocalization(
            AppStoreVersionLocalization(
                id: "vloc-en",
                versionId: "ver-1",
                locale: "en-US"
            ),
            root: root
        )
        try MetadataFileSupport.writeManifest(
            MetadataManifest(
                appId: "app-1",
                version: "1.0",
                versionId: "ver-1",
                appInfoIds: [],
                versionLocalizationCount: 1,
                appInfoLocalizationCount: 0
            ),
            root: root
        )

        let cmd = try MigrateValidate.parse(["--fastlane-dir", root.path, "--pretty"])
        let output = try await cmd.execute()

        #expect(output.contains("\"valid\" : true"))
        #expect(output.contains("\"versionFileCount\" : 1"))
    }

    @Test func `import applies migration workspace changes`() async throws {
        let versionRepo = MockVersionRepository()
        let versionLocalizationRepo = MockVersionLocalizationRepository()
        let appInfoRepo = MockAppInfoRepository()

        given(versionRepo).listVersions(appId: .any).willReturn([
            AppStoreVersion(
                id: "ver-1",
                appId: "app-1",
                versionString: "1.0",
                platform: .iOS,
                state: .prepareForSubmission
            )
        ])
        given(versionLocalizationRepo).listLocalizations(versionId: .any).willReturn([])
        given(versionLocalizationRepo).createLocalization(versionId: .any, locale: .any).willReturn(
            AppStoreVersionLocalization(
                id: "vloc-ja",
                versionId: "ver-1",
                locale: "ja-JP"
            )
        )
        given(versionLocalizationRepo).updateLocalization(
            localizationId: .any,
            whatsNew: .any,
            description: .any,
            keywords: .any,
            marketingUrl: .any,
            supportUrl: .any,
            promotionalText: .any
        ).willReturn(
            AppStoreVersionLocalization(
                id: "vloc-ja",
                versionId: "ver-1",
                locale: "ja-JP",
                whatsNew: "更新"
            )
        )
        given(appInfoRepo).listLocalizations(appInfoId: .any).willReturn([])
        given(appInfoRepo).createLocalization(appInfoId: .any, locale: .any, name: .any).willReturn(
            AppInfoLocalization(
                id: "iloc-ja",
                appInfoId: "ai-1",
                locale: "ja-JP",
                name: "新しいアプリ"
            )
        )
        given(appInfoRepo).updateLocalization(
            id: .any,
            name: .any,
            subtitle: .any,
            privacyPolicyUrl: .any,
            privacyChoicesUrl: .any,
            privacyPolicyText: .any
        ).willReturn(
            AppInfoLocalization(
                id: "iloc-ja",
                appInfoId: "ai-1",
                locale: "ja-JP",
                name: "新しいアプリ"
            )
        )

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("asc-migrate-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try MetadataFileSupport.writeVersionLocalization(
            AppStoreVersionLocalization(
                id: "seed",
                versionId: "ver-1",
                locale: "ja-JP",
                whatsNew: "更新"
            ),
            root: root
        )
        try MetadataFileSupport.writeAppInfoLocalization(
            AppInfoLocalization(
                id: "seed",
                appInfoId: "ai-1",
                locale: "ja-JP",
                name: "新しいアプリ",
                subtitle: "説明"
            ),
            root: root
        )
        try MetadataFileSupport.writeManifest(
            MetadataManifest(
                appId: "app-1",
                version: "1.0",
                versionId: "ver-1",
                appInfoIds: ["ai-1"],
                versionLocalizationCount: 1,
                appInfoLocalizationCount: 1
            ),
            root: root
        )

        let cmd = try MigrateImport.parse(["--app", "app-1", "--version", "1.0", "--fastlane-dir", root.path, "--pretty"])
        let output = try await cmd.execute(versionRepo: versionRepo, versionLocalizationRepo: versionLocalizationRepo, appInfoRepo: appInfoRepo)

        verify(versionLocalizationRepo).createLocalization(versionId: .value("ver-1"), locale: .value("ja-JP")).called(.once)
        verify(versionLocalizationRepo).updateLocalization(
            localizationId: .value("vloc-ja"),
            whatsNew: .value("更新"),
            description: .value(nil),
            keywords: .value(nil),
            marketingUrl: .value(nil),
            supportUrl: .value(nil),
            promotionalText: .value(nil)
        ).called(.once)
        verify(appInfoRepo).createLocalization(appInfoId: .value("ai-1"), locale: .value("ja-JP"), name: .value("新しいアプリ")).called(.once)
        verify(appInfoRepo).updateLocalization(
            id: .value("iloc-ja"),
            name: .value("新しいアプリ"),
            subtitle: .value("説明"),
            privacyPolicyUrl: .value(nil),
            privacyChoicesUrl: .value(nil),
            privacyPolicyText: .value(nil)
        ).called(.once)
        #expect(output.contains("\"mode\" : \"apply\""))
    }

    @Test func `import reports unsupported deletions explicitly and keeps action order deterministic`() async throws {
        let versionRepo = MockVersionRepository()
        let versionLocalizationRepo = MockVersionLocalizationRepository()
        let appInfoRepo = MockAppInfoRepository()

        given(versionRepo).listVersions(appId: .any).willReturn([
            AppStoreVersion(
                id: "ver-1",
                appId: "app-1",
                versionString: "1.0",
                platform: .iOS,
                state: .prepareForSubmission
            )
        ])
        given(versionLocalizationRepo).listLocalizations(versionId: .any).willReturn([
            AppStoreVersionLocalization(id: "vloc-ja", versionId: "ver-1", locale: "ja-JP"),
            AppStoreVersionLocalization(id: "vloc-en", versionId: "ver-1", locale: "en-US"),
            AppStoreVersionLocalization(id: "vloc-fr", versionId: "ver-1", locale: "fr-FR")
        ])
        given(appInfoRepo).listLocalizations(appInfoId: .any).willReturn([
            AppInfoLocalization(id: "iloc-ja", appInfoId: "ai-1", locale: "ja-JP", name: "新しいアプリ"),
            AppInfoLocalization(id: "iloc-en", appInfoId: "ai-1", locale: "en-US", name: "My App"),
            AppInfoLocalization(id: "iloc-fr", appInfoId: "ai-1", locale: "fr-FR", name: "Mon App")
        ])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("asc-migrate-plan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let versionDirectory = MetadataFileSupport.versionLocalizationsDirectory(root: root)
        try LocalizationFileSupport.ensureDirectory(at: versionDirectory)
        try LocalizationFileSupport.writeJSON(
            AppStoreVersionLocalization(
                id: "seed-fr",
                versionId: "ver-1",
                locale: "fr-FR",
                whatsNew: "Bonjour"
            ),
            to: versionDirectory.appendingPathComponent("fr-FR.json")
        )
        try LocalizationFileSupport.writeJSON(
            AppStoreVersionLocalization(
                id: "seed-en",
                versionId: "ver-1",
                locale: "en-US",
                whatsNew: "Hello"
            ),
            to: versionDirectory.appendingPathComponent("en-US.json")
        )

        let appInfoDirectory = MetadataFileSupport.appInfoLocalizationsDirectory(root: root).appendingPathComponent("ai-1")
        try LocalizationFileSupport.ensureDirectory(at: appInfoDirectory)
        try LocalizationFileSupport.writeJSON(
            AppInfoLocalization(
                id: "seed-fr",
                appInfoId: "ai-1",
                locale: "fr-FR",
                name: "Mon App"
            ),
            to: appInfoDirectory.appendingPathComponent("fr-FR.json")
        )
        try LocalizationFileSupport.writeJSON(
            AppInfoLocalization(
                id: "seed-en",
                appInfoId: "ai-1",
                locale: "en-US",
                name: "My App"
            ),
            to: appInfoDirectory.appendingPathComponent("en-US.json")
        )
        try MetadataFileSupport.writeManifest(
            MetadataManifest(
                appId: "app-1",
                version: "1.0",
                versionId: "ver-1",
                appInfoIds: ["ai-1"],
                versionLocalizationCount: 2,
                appInfoLocalizationCount: 2
            ),
            root: root
        )

        let cmd = try MigrateImport.parse(["--app", "app-1", "--version", "1.0", "--fastlane-dir", root.path, "--dry-run", "--pretty"])
        let output = try await cmd.execute(versionRepo: versionRepo, versionLocalizationRepo: versionLocalizationRepo, appInfoRepo: appInfoRepo)

        let firstAction = output.range(of: "\"file\" : \"en-US.json\"")
        let secondAction = output.range(of: "\"file\" : \"fr-FR.json\"")
        switch (firstAction, secondAction) {
        case let (.some(first), .some(second)):
            #expect(first.lowerBound < second.lowerBound)
        default:
            #expect(false)
        }
        #expect(output.contains("\"operation\" : \"planned-delete-unsupported\""))
    }
}
