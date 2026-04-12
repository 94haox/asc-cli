import Foundation
import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct AppsWallSubmitCompatibilityTests {

    @Test func `wall submit parses app and submit options`() throws {
        let cmd = try AppsWallSubmit.parse([
            "--app", "https://apps.apple.com/us/app/example/123",
            "--app", "https://apps.apple.com/us/app/example/456",
            "--link", "https://apps.apple.com/us/app/example/789",
            "--developer", "dev",
            "--name", "fallback-name",
            "--github-token", "token",
            "--token", "token2",
        ])

        #expect(cmd.app == ["https://apps.apple.com/us/app/example/123", "https://apps.apple.com/us/app/example/456"])
        #expect(cmd.link == ["https://apps.apple.com/us/app/example/789"])
        #expect(cmd.developer == "dev")
        #expect(cmd.name == "fallback-name")
        #expect(cmd.githubToken == "token")
        #expect(cmd.token == "token2")
    }

    @Test func `wall submit delegates to existing app wall submission`() async throws {
        let mockRepo = MockAppWallRepository()
        given(mockRepo).submit(app: .any).willReturn(
            AppWallSubmission(
                prNumber: 21,
                prUrl: "https://github.com/example/repo/pull/21",
                title: "feat(app-wall): add app",
                developer: "dev"
            )
        )

        let cmd = try AppsWallSubmit.parse([
            "--app", "https://apps.apple.com/us/app/example/123",
            "--developer", "dev",
            "--github-token", "token",
            "--pretty",
        ])
        let output = try await cmd.execute(repo: mockRepo)

        verify(mockRepo).submit(app: .any).called(.once)
        #expect(output.contains("\"prNumber\" : 21"))
        #expect(output.contains("\"developer\" : \"dev\""))
    }

    @Test func `wall submit supports whats-new flags precedence`() async throws {
        let mockRepo = MockAppWallRepository()
        given(mockRepo).submit(app: .any).willReturn(
            AppWallSubmission(
                prNumber: 33,
                prUrl: "https://github.com/example/repo/pull/33",
                title: "feat(app-wall): add app",
                developer: "dev"
            )
        )

        let cmd = try AppsWallSubmit.parse([
            "--name", "name-preferred",
            "--developer", "developer-preferred",
            "--app", "https://apps.apple.com/us/app/example/333",
            "--github-token", "token",
            "--pretty",
        ])
        let output = try await cmd.execute(repo: mockRepo)

        verify(mockRepo).submit(app: .any).called(.once)
        #expect(output.contains("\"developer\" : \"developer-preferred\""))
        #expect(output.contains("\"openPR\"") == false || output.contains("\"openPR\"") == false)
        #expect(!output.isEmpty)
    }

    @Test func `wall submit validates app source`() async throws {
        let mockRepo = MockAppWallRepository()
        var cmd = try AppsWallSubmit.parse(["--developer", "dev", "--github-token", "token"])
        await #expect(throws: (any Error).self) {
            _ = try await cmd.execute(repo: mockRepo)
        }
    }
}

