import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct LocalizationsListTests {

    @Test func `version type routes to version-localizations list`() async throws {
        let mockVersionRepo = MockVersionLocalizationRepository()
        given(mockVersionRepo).listLocalizations(versionId: .any).willReturn([
            AppStoreVersionLocalization(
                id: "vloc-1",
                versionId: "v-1",
                locale: "en-US",
                whatsNew: "Hi"
            ),
        ])

        let mockAppInfoRepo = MockAppInfoRepository()
        let cmd = try LocalizationsList.parse(["--version", "v-1", "--pretty"])
        let output = try await cmd.execute(versionRepo: mockVersionRepo, appInfoRepo: mockAppInfoRepo)

        verify(mockVersionRepo).listLocalizations(versionId: .value("v-1")).called(.once)
        verify(mockAppInfoRepo).listLocalizations(appInfoId: .any).called(.never)

        #expect(output.contains("\"id\" : \"vloc-1\""))
        #expect(output.contains("\"locale\" : \"en-US\""))
    }

    @Test func `app-info type routes to app-info-localizations list`() async throws {
        let mockVersionRepo = MockVersionLocalizationRepository()
        let mockAppInfoRepo = MockAppInfoRepository()
        given(mockAppInfoRepo).listLocalizations(appInfoId: .any).willReturn([
            AppInfoLocalization(
                id: "iloc-1",
                appInfoId: "ai-1",
                locale: "en-US",
                name: "My App",
                subtitle: "Sub"
            ),
        ])

        let cmd = try LocalizationsList.parse(["--type", "app-info", "--app", "app-1", "--app-info", "ai-1", "--pretty"])
        let output = try await cmd.execute(versionRepo: mockVersionRepo, appInfoRepo: mockAppInfoRepo)

        verify(mockAppInfoRepo).listLocalizations(appInfoId: .value("ai-1")).called(.once)
        verify(mockVersionRepo).listLocalizations(versionId: .any).called(.never)

        #expect(output.contains("\"id\" : \"iloc-1\""))
        #expect(output.contains("\"appInfoId\" : \"ai-1\""))
        #expect(output.contains("\"name\" : \"My App\""))
    }
}

