import Foundation
import ArgumentParser
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct NotarizationCommandTests {

    @Test func `command abstracts describe local manifest semantics`() {
        #expect(NotarizationCommand.configuration.abstract == "Manage local notarization submissions")
        #expect(NotarizationSubmit.configuration.abstract == "Submit a file for local notarization")
        #expect(NotarizationList.configuration.abstract == "List notarization submissions in the local manifest")
        #expect(NotarizationStatusCommand.configuration.abstract == "Get local notarization status details by submission ID")
        #expect(NotarizationLogCommand.configuration.abstract == "Get local notarization logs by submission ID")
    }

    @Test func `submit parses file and calls repository`() async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-notary-submit-test-\(UUID().uuidString)")
        let fileContent = Data("notary artifact".utf8)
        try fileContent.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let mockRepo = MockNotarizationRepository()
        await mockRepo.setSubmitResult(
            NotarizationSubmission(id: "sub-1", status: .queued)
        )

        let cmd = try NotarizationSubmit.parse(["--file", tempFile.path, "--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        let submittedPaths = await mockRepo.submittedFiles()
        let statusPayload = output
        #expect(submittedPaths == [tempFile.path])
        #expect(statusPayload.contains("\"id\" : \"sub-1\""))
        #expect(statusPayload.contains("\"status\" : \"queued\""))
    }

    @Test func `submit waits for completion when wait is enabled`() async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-notary-wait-test-\(UUID().uuidString)")
        try Data("notary artifact".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let mockRepo = MockNotarizationRepository()
        await mockRepo.setSubmitResult(NotarizationSubmission(id: "sub-2", status: .queued))
        await mockRepo.setStatusSequence([
            NotarizationSubmissionStatus(id: "sub-2", eligible: true, status: .inProgress, startedAt: nil, updatedAt: nil, failureReason: nil),
            NotarizationSubmissionStatus(id: "sub-2", eligible: true, status: .completed, startedAt: "1", updatedAt: "2", failureReason: nil),
        ])

        let cmd = try NotarizationSubmit.parse(["--file", tempFile.path, "--wait", "--poll-interval", "0", "--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        #expect(output.contains("\"id\" : \"sub-2\""))
        #expect(output.contains("\"status\" : \"completed\""))
        #expect(await mockRepo.statusCallCount() == 2)
    }

    @Test func `submit validates file existence`() async throws {
        let mockRepo = MockNotarizationRepository()
        let missingPath = "/tmp/asc-notary-missing-\(UUID().uuidString).ipa"

        let cmd = try NotarizationSubmit.parse(["--file", missingPath, "--pretty"])
        await #expect(throws: ValidationError.self) {
            _ = try await cmd.execute(repo: mockRepo)
        }
    }

    @Test func `list returns json payload`() async throws {
        let mockRepo = MockNotarizationRepository()
        await mockRepo.setListResult([
            NotarizationSubmission(id: "sub-1", status: .completed),
            NotarizationSubmission(id: "sub-2", status: .failed),
        ])

        let cmd = try NotarizationList.parse(["--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        #expect(output.contains("\"id\" : \"sub-1\""))
        #expect(output.contains("\"status\" : \"completed\""))
        #expect(output.contains("\"id\" : \"sub-2\""))
        #expect(output.contains("\"status\" : \"failed\""))
    }

    @Test func `status and log return structured payloads`() async throws {
        let mockRepo = MockNotarizationRepository()
        await mockRepo.setStatusResult(
            "n-100",
            value: NotarizationSubmissionStatus(
                id: "n-100",
                eligible: false,
                status: .invalid,
                startedAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-01T01:00:00Z",
                failureReason: "Signature mismatch"
            )
        )
        await mockRepo.setLogResult(
            "n-100",
            value: NotarizationSubmissionLog(id: "n-100", lines: ["line one", "line two"])
        )

        let statusCmd = try NotarizationStatusCommand.parse(["--id", "n-100", "--pretty"])
        let statusOutput = try await statusCmd.execute(repo: mockRepo)
        #expect(statusOutput.contains("\"eligible\" : false"))
        #expect(statusOutput.contains("\"failureReason\" : \"Signature mismatch\""))

        let logCmd = try NotarizationLogCommand.parse(["--id", "n-100", "--pretty"])
        let logOutput = try await logCmd.execute(repo: mockRepo)
        #expect(logOutput.contains("\"lines\" : ["))
        #expect(logOutput.contains("\"line one\""))
    }

    @Test func `list propagates repository failure when repo is unavailable`() async throws {
        let repo = FailingNotarizationRepository()
        let cmd = try NotarizationList.parse(["--pretty"])

        await #expect(throws: NotarizationTestError.self) {
            _ = try await cmd.execute(repo: repo)
        }
    }
}

private actor MockNotarizationRepository: NotarizationRepository {
    private var submitFilePaths: [String] = []
    private var submitResult: NotarizationSubmission = .init(id: "n-0", status: .queued)
    private var listResult: [NotarizationSubmission] = []
    private var statusResults: [String: NotarizationSubmissionStatus] = [:]
    private var logResults: [String: NotarizationSubmissionLog] = [:]
    private var statusSequence: [NotarizationSubmissionStatus] = []
    private var statusRequests: [String] = []

    func setSubmitResult(_ value: NotarizationSubmission) async {
        submitResult = value
    }

    func setListResult(_ value: [NotarizationSubmission]) async {
        listResult = value
    }

    func setStatusResult(_ id: String, value: NotarizationSubmissionStatus) async {
        statusResults[id] = value
    }

    func setStatusSequence(_ values: [NotarizationSubmissionStatus]) async {
        statusSequence = values
    }

    func setLogResult(_ id: String, value: NotarizationSubmissionLog) async {
        logResults[id] = value
    }

    func submitNotarization(fileURL: URL) async throws -> NotarizationSubmission {
        submitFilePaths.append(fileURL.path)
        return submitResult
    }

    func listNotarizations(limit: Int?) async throws -> [NotarizationSubmission] {
        _ = limit
        return listResult
    }

    func getNotarizationStatus(id: String) async throws -> NotarizationSubmissionStatus {
        statusRequests.append(id)
        if let next = statusSequence.first {
            statusSequence.removeFirst()
            return next
        }
        return statusResults[id] ?? NotarizationSubmissionStatus(
            id: id,
            eligible: true,
            status: .completed,
            startedAt: nil,
            updatedAt: nil,
            failureReason: nil
        )
    }

    func getNotarizationLog(id: String) async throws -> NotarizationSubmissionLog {
        return logResults[id] ?? NotarizationSubmissionLog(id: id, lines: [])
    }

    func statusCallCount() -> Int {
        statusRequests.count
    }

    func submittedFiles() -> [String] {
        submitFilePaths
    }
}

private actor FailingNotarizationRepository: NotarizationRepository {
    func submitNotarization(fileURL: URL) async throws -> NotarizationSubmission {
        _ = fileURL
        throw NotarizationTestError.failed
    }

    func listNotarizations(limit: Int?) async throws -> [NotarizationSubmission] {
        _ = limit
        throw NotarizationTestError.failed
    }

    func getNotarizationStatus(id: String) async throws -> NotarizationSubmissionStatus {
        _ = id
        throw NotarizationTestError.failed
    }

    func getNotarizationLog(id: String) async throws -> NotarizationSubmissionLog {
        _ = id
        throw NotarizationTestError.failed
    }
}

private enum NotarizationTestError: Error {
    case failed
}
