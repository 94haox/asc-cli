import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct BuildsGroupAliasTests {

    @Test func `add-groups accepts comma-separated and repeated group values`() async throws {
        let mockRepo = MockBuildRepository()
        given(mockRepo).addBetaGroups(buildId: .any, betaGroupIds: .any).willReturn()

        let cmd = try BuildsAddGroups.parse([
            "--build-id", "build-1",
            "--group", "g-a",
            "--group", "g-b,g-c",
            "--pretty",
        ])
        try await cmd.execute(repo: mockRepo)

        verify(mockRepo).addBetaGroups(
            buildId: .value("build-1"),
            betaGroupIds: .value(["g-a", "g-b", "g-c"])
        ).called(.once)
    }

    @Test func `remove-groups accepts confirm and groups`() async throws {
        let mockRepo = MockBuildRepository()
        given(mockRepo).removeBetaGroups(buildId: .any, betaGroupIds: .any).willReturn()

        let cmd = try BuildsRemoveGroups.parse([
            "--build-id", "build-2",
            "--group", "g-x",
            "--confirm",
            "--pretty",
        ])
        #expect(cmd.confirm == true)
        #expect(cmd.buildId == "build-2")

        try await cmd.execute(repo: mockRepo)

        verify(mockRepo).removeBetaGroups(
            buildId: .value("build-2"),
            betaGroupIds: .value(["g-x"])
        ).called(.once)
    }
}

