import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct AppsViewTests {

    @Test func `parser exposes id`() throws {
        var cmd = try AppsView.parse(["--id", "app-1"])
        #expect(cmd.id == "app-1")
        #expect(cmd.globals.pretty == false)
    }

    @Test func `execute returns app details with affordances`() async throws {
        let mockRepo = MockAppRepository()
        given(mockRepo).getApp(id: .value("app-1")).willReturn(
            App(
                id: "app-1",
                name: "My App",
                bundleId: "com.example.myapp"
            )
        )

        let cmd = try AppsView.parse(["--id", "app-1", "--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        verify(mockRepo).getApp(id: .value("app-1")).called(.once)

        #expect(output == """
        {
          "data" : [
            {
              "affordances" : {
                "listAppInfos" : "asc app-infos list --app-id app-1",
                "listReviews" : "asc reviews list --app-id app-1",
                "listVersions" : "asc versions list --app-id app-1"
              },
              "bundleId" : "com.example.myapp",
              "id" : "app-1",
              "name" : "My App"
            }
          ]
        }
        """)
    }
}

