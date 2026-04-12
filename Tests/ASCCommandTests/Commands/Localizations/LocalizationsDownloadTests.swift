import Foundation
import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct LocalizationsDownloadTests {

    @Test func `download version type writes files and resolves output`() async throws {
        let mockVersionRepo = MockVersionLocalizationRepository()
        given(mockVersionRepo).listLocalizations(versionId: .any).willReturn([
            AppStoreVersionLocalization(
                id: "vloc-1",
                versionId: "v-1",
                locale: "en-US",
                whatsNew: "Hi",
                description: "Description",
                keywords: "keyword1, keyword2"
            ),
        ])

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("asc-localizations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let mockAppInfoRepo = MockAppInfoRepository()
        let outputPath = temp.appendingPathComponent("out").path
        let cmd = try LocalizationsDownload.parse(["--version", "v-1", "--path", outputPath, "--pretty"])
        let output = try await cmd.execute(versionRepo: mockVersionRepo, appInfoRepo: mockAppInfoRepo)

        verify(mockVersionRepo).listLocalizations(versionId: .value("v-1")).called(.once)
        #expect(output.contains("\"en-US\" : {"))
        #expect(FileManager.default.fileExists(atPath: outputPath))
        #expect(FileManager.default.fileExists(atPath: temp.appendingPathComponent("out").appendingPathComponent("en-US.json").path))
    }

    @Test func `download app-info type supports path output`() async throws {
        let mockVersionRepo = MockVersionLocalizationRepository()
        let mockAppInfoRepo = MockAppInfoRepository()
        given(mockAppInfoRepo).listLocalizations(appInfoId: .any).willReturn([
            AppInfoLocalization(
                id: "iloc-1",
                appInfoId: "ai-1",
                locale: "en-US",
                name: "My App"
            ),
        ])

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("asc-localizations-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let cmd = try LocalizationsDownload.parse(["--type", "app-info", "--app", "app-1", "--app-info", "ai-1", "--path", temp.path, "--pretty"])
        let output = try await cmd.execute(versionRepo: mockVersionRepo, appInfoRepo: mockAppInfoRepo)

        verify(mockAppInfoRepo).listLocalizations(appInfoId: .value("ai-1")).called(.once)
        #expect(output.contains("\"name\" : \"My App\""))
        #expect(FileManager.default.fileExists(atPath: temp.appendingPathComponent("en-US.json").path))
    }
}
