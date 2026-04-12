import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct VersionsViewTests {

    @Test func `parser exposes version id`() throws {
        var cmd = try VersionsView.parse(["--version-id", "ver-1"])
        #expect(cmd.versionId == "ver-1")
        #expect(cmd.globals.pretty == false)
    }

    @Test func `execute gets version by id and returns same fields as list`() async throws {
        let mockRepo = MockVersionRepository()
        given(mockRepo).getVersion(id: .value("ver-1")).willReturn(
            AppStoreVersion(
                id: "ver-1",
                appId: "app-1",
                versionString: "1.2.3",
                platform: .iOS,
                state: .readyForSale
            )
        )

        let cmd = try VersionsView.parse(["--version-id", "ver-1", "--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        verify(mockRepo).getVersion(id: .value("ver-1")).called(.once)

        #expect(output == """
        {
          "data" : [
            {
              "affordances" : {
                "checkReadiness" : "asc versions check-readiness --version-id ver-1",
                "getReviewDetail" : "asc version-review-detail get --version-id ver-1",
                "listLocalizations" : "asc version-localizations list --version-id ver-1",
                "listVersions" : "asc versions list --app-id app-1"
              },
              "appId" : "app-1",
              "id" : "ver-1",
              "platform" : "IOS",
              "state" : "READY_FOR_SALE",
              "versionString" : "1.2.3"
            }
          ]
        }
        """)
    }
}

