import Foundation
import ArgumentParser
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct SigningSyncCommandTests {

    @Test func `command abstracts describe local workspace semantics`() {
        #expect(SigningCommand.configuration.abstract == "Manage workspace-backed signing snapshots")
        #expect(SigningSyncCommand.configuration.abstract == "Sync local signing snapshots")
        #expect(SigningSyncPull.configuration.abstract == "Restore signing data from the local manifest to profiles")
        #expect(SigningSyncPush.configuration.abstract == "Capture local signing data into a workspace manifest")
    }

    @Test func `pull runs as dry-run by default`() async throws {
        let mockRepo = MockSigningSyncRepository()
        await mockRepo.setResult(SigningSyncResult(direction: .pull, dryRun: true, confirm: false, itemCount: 12))

        let cmd = try SigningSyncPull.parse(["--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        let lastCall = await mockRepo.lastCall()
        #expect(lastCall?.direction == .pull)
        #expect(lastCall?.dryRun == true)
        #expect(lastCall?.confirm == false)
        #expect(output.contains("\"direction\" : \"pull\""))
    }

    @Test func `push applies when confirm is passed`() async throws {
        let mockRepo = MockSigningSyncRepository()
        await mockRepo.setResult(SigningSyncResult(direction: .push, dryRun: false, confirm: true, itemCount: 3))

        let cmd = try SigningSyncPush.parse(["--confirm", "--pretty"])
        _ = try await cmd.execute(repo: mockRepo)

        let lastCall = await mockRepo.lastCall()
        #expect(lastCall?.direction == .push)
        #expect(lastCall?.dryRun == false)
        #expect(lastCall?.confirm == true)
    }

    @Test func `sync propagates repository failure`() async throws {
        let cmd = try SigningSyncPull.parse(["--pretty"])
        await #expect(throws: SigningSyncTestError.self) {
            _ = try await cmd.execute(repo: FailingSigningSyncRepository())
        }
    }
}

private actor MockSigningSyncRepository: SigningSyncRepository {
    private var result = SigningSyncResult(direction: .pull, dryRun: true, confirm: false, itemCount: 0)
    private var recordedCall: (direction: SigningSyncDirection, dryRun: Bool, confirm: Bool)?

    func setResult(_ value: SigningSyncResult) async {
        result = value
    }

    func sync(direction: SigningSyncDirection, dryRun: Bool, confirm: Bool) async throws -> SigningSyncResult {
        recordedCall = (direction, dryRun, confirm)
        return result
    }

    func lastCall() async -> (direction: SigningSyncDirection, dryRun: Bool, confirm: Bool)? {
        recordedCall
    }
}

private actor FailingSigningSyncRepository: SigningSyncRepository {
    func sync(direction: SigningSyncDirection, dryRun: Bool, confirm: Bool) async throws -> SigningSyncResult {
        _ = direction
        _ = dryRun
        _ = confirm
        throw SigningSyncTestError.failed
    }
}

private enum SigningSyncTestError: Error {
    case failed
}
