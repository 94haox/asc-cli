import Testing
@testable import ASCCommand

@Suite
struct P0ValidateCompatibilityTests {
    @Test func `validate root emits readiness envelope`() async throws {
        let cmd = try ValidateCommand.parse(["--app", "123", "--version", "1.2.3", "--pretty"])
        let output = try cmd.execute()

        #expect(output.contains("\"command\" : \"validate\""))
        #expect(output.contains("\"appId\" : \"123\""))
        #expect(output.contains("\"version\" : \"1.2.3\""))
    }

    @Test func `validate iap emits category iap`() async throws {
        let cmd = try ValidateIAPCommand.parse(["--app", "123", "--pretty"])
        let output = try cmd.execute()

        #expect(output.contains("\"category\" : \"iap\""))
    }

    @Test func `validate subscriptions emits category subscriptions`() async throws {
        let cmd = try ValidateSubscriptionsCommand.parse(["--app", "123", "--pretty"])
        let output = try cmd.execute()

        #expect(output.contains("\"category\" : \"subscriptions\""))
    }
}

@Suite
struct P0WorkflowCompatibilityTests {
    @Test func `workflow list emits compatible command marker`() async throws {
        let cmd = try WorkflowListCommand.parse(["--pretty"])
        let output = try cmd.execute()

        #expect(output.contains("\"command\" : \"workflow list\""))
    }

    @Test func `workflow validate defaults to valid true for missing file`() async throws {
        let cmd = try WorkflowValidateCommand.parse([])
        let output = try cmd.execute(fileExists: { _ in false })

        #expect(output.contains("\"valid\":true"))
    }
}

@Suite
struct P0SubmitReleaseCompatibilityTests {
    @Test func `submit status supports version-id`() async throws {
        let cmd = try SubmitStatusCommand.parse(["--version-id", "ver-1", "--pretty"])
        let output = try cmd.execute()

        #expect(output.contains("\"command\" : \"submit status\""))
        #expect(output.contains("\"versionId\" : \"ver-1\""))
    }

    @Test func `release stage dry-run emits planned steps`() async throws {
        let cmd = try ReleaseStageCommand.parse([
            "--app", "123", "--version", "1.2.3", "--build", "456", "--dry-run", "--pretty",
        ])
        let output = try cmd.execute()

        #expect(output.contains("\"command\" : \"release stage\""))
        #expect(output.contains("\"dryRun\" : true"))
        #expect(output.contains("ensureVersion"))
    }
}
