import Foundation
import Testing
@testable import ASCCommand

@Suite
struct LocalNotarizationRepositoryTests {

    @Test func `submit persists record and status advances locally`() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("asc-notarization-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let fileURL = workspace.appendingPathComponent("sample.pkg")
        try Data("artifact".utf8).write(to: fileURL)

        let repo = LocalNotarizationRepository(storageDirectoryURL: workspace.appendingPathComponent(".asc").appendingPathComponent("notarization"))
        let submitted = try await repo.submitNotarization(fileURL: fileURL)

        let immediate = try await repo.getNotarizationStatus(id: submitted.id)
        #expect(immediate.status == .queued || immediate.status == .inProgress)

        try await Task.sleep(nanoseconds: 3_000_000_000)

        let finished = try await repo.getNotarizationStatus(id: submitted.id)
        #expect(finished.status == .completed)

        let list = try await repo.listNotarizations(limit: nil)
        #expect(list.map(\.id) == [submitted.id])

        let log = try await repo.getNotarizationLog(id: submitted.id)
        #expect(log.text.contains("Queued notarization"))
        #expect(log.text.contains("Current status: completed"))
    }
}
