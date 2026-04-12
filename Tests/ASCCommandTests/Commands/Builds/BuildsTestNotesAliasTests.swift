import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct BuildsTestNotesAliasTests {

    @Test func `create uses notes argument`() async throws {
        let mockRepo = MockBetaBuildLocalizationRepository()
        given(mockRepo).upsertBetaBuildLocalization(buildId: .any, locale: .any, whatsNew: .any).willReturn(
            BetaBuildLocalization(id: "loc-1", buildId: "build-1", locale: "en-US", whatsNew: "Feature update")
        )

        let cmd = try BuildsTestNotesCreate.parse([
            "--build-id", "build-1",
            "--locale", "en-US",
            "--notes", "Feature update",
            "--pretty",
        ])
        let output = try await cmd.execute(repo: mockRepo)

        verify(mockRepo).upsertBetaBuildLocalization(
            buildId: .value("build-1"),
            locale: .value("en-US"),
            whatsNew: .value("Feature update")
        ).called(.once)

        #expect(output == """
        {
          "data" : [
            {
              "affordances" : {
                "updateNotes" : "asc builds update-beta-notes --build-id build-1 --locale en-US --notes <text>"
              },
              "buildId" : "build-1",
              "id" : "loc-1",
              "locale" : "en-US",
              "whatsNew" : "Feature update"
            }
          ]
        }
        """)
    }

    @Test func `update accepts whats-new alias argument`() async throws {
        let mockRepo = MockBetaBuildLocalizationRepository()
        given(mockRepo).upsertBetaBuildLocalization(buildId: .any, locale: .any, whatsNew: .any).willReturn(
            BetaBuildLocalization(id: "loc-2", buildId: "build-2", locale: "zh-Hans", whatsNew: "修复")
        )

        let cmd = try BuildsTestNotesUpdate.parse([
            "--build-id", "build-2",
            "--locale", "zh-Hans",
            "--whats-new", "修复",
            "--pretty",
        ])
        let output = try await cmd.execute(repo: mockRepo)

        verify(mockRepo).upsertBetaBuildLocalization(
            buildId: .value("build-2"),
            locale: .value("zh-Hans"),
            whatsNew: .value("修复")
        ).called(.once)

        #expect(output.contains("\"whatsNew\" : \"修复\""))
        #expect(output.contains("\"buildId\" : \"build-2\""))
    }

    @Test func `create requires locale and notes`() async throws {
        let mockRepo = MockBetaBuildLocalizationRepository()
        let cmd = try BuildsTestNotesCreate.parse(["--build-id", "build-1", "--locale", "en-US"])
        await #expect(throws: (any Error).self) {
            _ = try await cmd.execute(repo: mockRepo)
        }
    }

    @Test func `update requires locale and notes`() async throws {
        let mockRepo = MockBetaBuildLocalizationRepository()
        let cmd = try BuildsTestNotesUpdate.parse(["--build-id", "build-1", "--locale", "en-US"])
        await #expect(throws: (any Error).self) {
            _ = try await cmd.execute(repo: mockRepo)
        }
    }
}

