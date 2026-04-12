import Foundation
import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct LocalizationsUploadTests {

    @Test func `upload creates and updates version localizations from json files`() async throws {
        let mockVersionRepo = MockVersionLocalizationRepository()
        given(mockVersionRepo).listLocalizations(versionId: .any).willReturn([
            AppStoreVersionLocalization(
                id: "vloc-en",
                versionId: "v-1",
                locale: "en-US",
                whatsNew: "Old"
            ),
        ])
        given(mockVersionRepo).createLocalization(versionId: .any, locale: .any).willReturn(
            AppStoreVersionLocalization(
                id: "vloc-fr",
                versionId: "v-1",
                locale: "fr-FR"
            )
        )
        given(mockVersionRepo).updateLocalization(
            localizationId: .any,
            whatsNew: .any,
            description: .any,
            keywords: .any,
            marketingUrl: .any,
            supportUrl: .any,
            promotionalText: .any
        ).willReturn(
            AppStoreVersionLocalization(
                id: "updated",
                versionId: "v-1",
                locale: "en-US"
            )
        )

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("asc-localizations-upload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try LocalizationFileSupport.writeJSON(
            AppStoreVersionLocalization(
                id: "seed-en",
                versionId: "v-1",
                locale: "en-US",
                whatsNew: "New release notes",
                keywords: "one, two"
            ),
            to: temp.appendingPathComponent("en-US.json")
        )
        try LocalizationFileSupport.writeJSON(
            AppStoreVersionLocalization(
                id: "seed-fr",
                versionId: "v-1",
                locale: "fr-FR",
                whatsNew: "Notes",
                description: "Description FR"
            ),
            to: temp.appendingPathComponent("fr-FR.json")
        )

        let mockAppInfoRepo = MockAppInfoRepository()
        let cmd = try LocalizationsUpload.parse(["--version", "v-1", "--path", temp.path, "--pretty"])
        let output = try await cmd.execute(versionRepo: mockVersionRepo, appInfoRepo: mockAppInfoRepo)

        verify(mockVersionRepo).listLocalizations(versionId: .value("v-1")).called(.once)
        verify(mockVersionRepo).createLocalization(versionId: .value("v-1"), locale: .value("fr-FR")).called(.once)
        verify(mockVersionRepo).updateLocalization(
            localizationId: .value("vloc-en"),
            whatsNew: .value("New release notes"),
            description: .value(nil),
            keywords: .value("one, two"),
            marketingUrl: .value(nil),
            supportUrl: .value(nil),
            promotionalText: .value(nil)
        ).called(.once)
        verify(mockVersionRepo).updateLocalization(
            localizationId: .value("vloc-fr"),
            whatsNew: .value("Notes"),
            description: .value("Description FR"),
            keywords: .value(nil),
            marketingUrl: .value(nil),
            supportUrl: .value(nil),
            promotionalText: .value(nil)
        ).called(.once)

        #expect(output.contains("\"createdCount\" : 1"))
        #expect(output.contains("\"updatedCount\" : 2"))
        #expect(output.contains("\"fr-FR.json\""))
    }

    @Test func `upload creates and updates app-info localizations from json files`() async throws {
        let mockVersionRepo = MockVersionLocalizationRepository()
        let mockAppInfoRepo = MockAppInfoRepository()
        given(mockAppInfoRepo).listLocalizations(appInfoId: .any).willReturn([
            AppInfoLocalization(
                id: "iloc-en",
                appInfoId: "ai-1",
                locale: "en-US",
                name: "My App"
            ),
        ])
        given(mockAppInfoRepo).createLocalization(appInfoId: .any, locale: .any, name: .any).willReturn(
            AppInfoLocalization(
                id: "iloc-ja",
                appInfoId: "ai-1",
                locale: "ja-JP",
                name: "新しいアプリ"
            )
        )
        given(mockAppInfoRepo).updateLocalization(
            id: .any,
            name: .any,
            subtitle: .any,
            privacyPolicyUrl: .any,
            privacyChoicesUrl: .any,
            privacyPolicyText: .any
        ).willReturn(
            AppInfoLocalization(
                id: "updated",
                appInfoId: "ai-1",
                locale: "en-US",
                name: "My App"
            )
        )

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("asc-localizations-upload-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try LocalizationFileSupport.writeJSON(
            AppInfoLocalization(
                id: "seed-en",
                appInfoId: "ai-1",
                locale: "en-US",
                name: "My App Updated",
                subtitle: "Subtitle",
                privacyPolicyUrl: "https://example.com/privacy"
            ),
            to: temp.appendingPathComponent("en-US.json")
        )
        try LocalizationFileSupport.writeJSON(
            AppInfoLocalization(
                id: "seed-ja",
                appInfoId: "ai-1",
                locale: "ja-JP",
                name: "新しいアプリ",
                subtitle: "説明",
                privacyPolicyText: "policy"
            ),
            to: temp.appendingPathComponent("ja-JP.json")
        )

        let cmd = try LocalizationsUpload.parse(["--type", "app-info", "--app", "app-1", "--app-info", "ai-1", "--path", temp.path, "--pretty"])
        let output = try await cmd.execute(versionRepo: mockVersionRepo, appInfoRepo: mockAppInfoRepo)

        verify(mockAppInfoRepo).listLocalizations(appInfoId: .value("ai-1")).called(.once)
        verify(mockAppInfoRepo).createLocalization(appInfoId: .value("ai-1"), locale: .value("ja-JP"), name: .value("新しいアプリ")).called(.once)
        verify(mockAppInfoRepo).updateLocalization(
            id: .value("iloc-en"),
            name: .value("My App Updated"),
            subtitle: .value("Subtitle"),
            privacyPolicyUrl: .value("https://example.com/privacy"),
            privacyChoicesUrl: .value(nil),
            privacyPolicyText: .value(nil)
        ).called(.once)
        verify(mockAppInfoRepo).updateLocalization(
            id: .value("iloc-ja"),
            name: .value("新しいアプリ"),
            subtitle: .value("説明"),
            privacyPolicyUrl: .value(nil),
            privacyChoicesUrl: .value(nil),
            privacyPolicyText: .value("policy")
        ).called(.once)

        #expect(output.contains("\"createdCount\" : 1"))
        #expect(output.contains("\"updatedCount\" : 2"))
    }
}
