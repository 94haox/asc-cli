import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct BuildsNextBuildNumberAliasTests {

    @Test func `next-build-number alias shares next-number output`() async throws {
        let mockRepo = MockBuildRepository()
        given(mockRepo).listBuilds(
            appId: .value("app-1"),
            platform: .value(.iOS),
            version: .value("1.0.1"),
            limit: .any
        ).willReturn(
            PaginatedResponse(data: [
                Build(id: "b-1", version: "1.0.1", buildNumber: "3", platform: .iOS),
            ], nextCursor: nil)
        )

        let cmd = try BuildsNextBuildNumber.parse([
            "--app-id", "app-1",
            "--version", "1.0.1",
            "--platform", "ios",
            "--pretty",
        ])
        let output = try await cmd.execute(repo: mockRepo)

        verify(mockRepo).listBuilds(appId: .value("app-1"), platform: .value(.iOS), version: .value("1.0.1"), limit: .any).called(.once)

        #expect(output == """
        {
          "data" : {
            "affordances" : {
              "archiveAndUpload" : "asc builds archive --scheme <scheme> --platform ios --upload --app-id app-1 --version 1.0.1 --build-number 4",
              "uploadBuild" : "asc builds upload --app-id app-1 --file <path> --version 1.0.1 --build-number 4 --platform ios"
            },
            "appId" : "app-1",
            "nextBuildNumber" : 4,
            "platform" : "IOS",
            "version" : "1.0.1"
          }
        }
        """)
    }
}

