import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct BuildsInfoTests {

    @Test func `parser supports build id`() throws {
        var cmd = try BuildsInfo.parse(["--build-id", "build-1"])
        #expect(cmd.buildId == "build-1")
        #expect(cmd.app == nil)
        #expect(cmd.version == nil)
        #expect(cmd.latest == false)
    }

    @Test func `execute with build-id fetches build and adds buildId compatibility field`() async throws {
        let mockRepo = MockBuildRepository()
        given(mockRepo).getBuild(id: .value("build-1")).willReturn(
            Build(
                id: "build-1",
                version: "3",
                expired: false,
                processingState: .valid,
                buildNumber: "22",
                platform: .iOS
            )
        )

        let cmd = try BuildsInfo.parse(["--build-id", "build-1", "--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        verify(mockRepo).getBuild(id: .value("build-1")).called(.once)
        verify(mockRepo).listBuilds(appId: .any, platform: .any, version: .any, limit: .any).called(.never)

        #expect(output == """
        {
          "data" : {
            "affordances" : {
              "addToTestFlight" : "asc builds add-beta-group --build-id build-1 --beta-group-id <beta-group-id>",
              "updateBetaNotes" : "asc builds update-beta-notes --build-id build-1 --locale en-US --notes <notes>"
            },
            "appId" : null,
            "buildId" : "build-1",
            "buildNumber" : "22",
            "expired" : false,
            "id" : "build-1",
            "platform" : "IOS",
            "processingState" : "VALID",
            "version" : "3"
          }
        }
        """)
    }

    @Test func `execute uses latest build from app when no build-id provided`() async throws {
        let mockRepo = MockBuildRepository()
        given(mockRepo).listBuilds(appId: .value("app-1"), platform: .value(.iOS), version: .value("1.2.0"), limit: .any)
            .willReturn(
                PaginatedResponse(data: [
                    Build(id: "b-1", version: "1.2.0", expired: false, processingState: .valid, buildNumber: "10", platform: .iOS),
                    Build(id: "b-2", version: "1.2.0", expired: false, processingState: .valid, buildNumber: "9", platform: .iOS),
                ], nextCursor: nil)
            )

        let cmd = try BuildsInfo.parse(["--app", "app-1", "--version", "1.2.0", "--platform", "ios", "--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        verify(mockRepo).listBuilds(
            appId: .value("app-1"),
            platform: .value(.iOS),
            version: .value("1.2.0"),
            limit: .value(nil)
        ).called(.once)
        verify(mockRepo).getBuild(id: .any).called(.never)

        #expect(output.contains("\"buildId\" : \"b-1\""))
        #expect(output.contains("\"appId\" : \"app-1\""))
        #expect(output.contains("\"buildNumber\" : \"10\""))
    }

    @Test func `execute selects latest when app latest requested`() async throws {
        let mockRepo = MockBuildRepository()
        given(mockRepo).listBuilds(appId: .value("app-1"), platform: .any, version: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                Build(id: "b-1", version: "3", expired: false, processingState: .valid, buildNumber: "2", platform: .iOS),
                Build(id: "b-2", version: "4", expired: false, processingState: .valid, buildNumber: "42", platform: .macOS),
            ], nextCursor: nil)
        )

        let cmd = try BuildsInfo.parse(["--app", "app-1", "--latest", "--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        verify(mockRepo).listBuilds(appId: .value("app-1"), platform: .any, version: .any, limit: .value(nil)).called(.once)
        #expect(output.contains("\"buildId\" : \"b-2\""))
        #expect(output.contains("\"buildNumber\" : \"42\""))
    }

    @Test func `execute throws when app query is incomplete`() async throws {
        let mockRepo = MockBuildRepository()

        let cmd = try BuildsInfo.parse(["--version", "1.2.0"])
        await #expect(throws: (any Error).self) {
            try await cmd.execute(repo: mockRepo)
        }
    }

    @Test func `execute throws when no build found`() async throws {
        let mockRepo = MockBuildRepository()
        given(mockRepo).listBuilds(appId: .any, platform: .any, version: .any, limit: .any).willReturn(PaginatedResponse(data: [], nextCursor: nil))

        let cmd = try BuildsInfo.parse(["--app", "app-1", "--latest"])
        await #expect(throws: (any Error).self) {
            try await cmd.execute(repo: mockRepo)
        }
    }
}

