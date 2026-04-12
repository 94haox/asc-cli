import CryptoKit
import Foundation

actor LocalNotarizationRepository: NotarizationRepository {
    private let storageDirectoryURL: URL
    private let manifestURL: URL

    init(storageDirectoryURL: URL = LocalNotarizationRepository.defaultStorageDirectory()) {
        self.storageDirectoryURL = storageDirectoryURL
        self.manifestURL = storageDirectoryURL.appendingPathComponent("notarizations.json")
    }

    func submitNotarization(fileURL: URL) async throws -> NotarizationSubmission {
        let content = try Data(contentsOf: fileURL)
        let now = Date()
        let record = NotarizationRecord(
            id: Self.makeSubmissionID(for: content, fileName: fileURL.lastPathComponent),
            fileName: fileURL.lastPathComponent,
            filePath: fileURL.standardizedFileURL.path,
            sha256: Self.sha256Hex(of: content),
            submittedAt: now,
            updatedAt: now,
            status: .queued,
            logLines: [
                "Queued notarization for \(fileURL.lastPathComponent)",
                "SHA256: \(Self.sha256Hex(of: content))",
                "Size: \(content.count) bytes",
            ]
        )
        var records = try loadRecords()
        records.removeAll { $0.id == record.id }
        records.append(record)
        try save(records: records)
        return NotarizationSubmission(id: record.id, status: record.status)
    }

    func listNotarizations(limit: Int?) async throws -> [NotarizationSubmission] {
        let records = try loadRecords()
        let ordered = records.sorted { $0.updatedAt > $1.updatedAt }
        let mapped = ordered.map { NotarizationSubmission(id: $0.id, status: derivedStatus(for: $0, at: Date()).status) }
        guard let limit else { return mapped }
        return Array(mapped.prefix(max(0, limit)))
    }

    func getNotarizationStatus(id: String) async throws -> NotarizationSubmissionStatus {
        guard let record = try loadRecords().first(where: { $0.id == id }) else {
            throw ValidationError("Notarization submission not found: \(id)")
        }
        let snapshot = derivedStatus(for: record, at: Date())
        return NotarizationSubmissionStatus(
            id: record.id,
            eligible: true,
            status: snapshot.status,
            startedAt: iso8601(record.submittedAt),
            updatedAt: iso8601(snapshot.updatedAt),
            failureReason: snapshot.failureReason
        )
    }

    func getNotarizationLog(id: String) async throws -> NotarizationSubmissionLog {
        guard let record = try loadRecords().first(where: { $0.id == id }) else {
            throw ValidationError("Notarization submission not found: \(id)")
        }
        var lines = record.logLines
        let snapshot = derivedStatus(for: record, at: Date())
        lines.append("Current status: \(snapshot.status.rawValue)")
        lines.append("Submitted at: \(iso8601(record.submittedAt) ?? "-")")
        return NotarizationSubmissionLog(id: record.id, lines: lines)
    }

    // MARK: - Private

    private static func defaultStorageDirectory() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".asc")
            .appendingPathComponent("notarization")
    }

    private static func makeSubmissionID(for data: Data, fileName: String) -> String {
        let digest = SHA256.hash(data: data)
        let hash = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return "notary-\(stem)-\(hash)"
    }

    private func derivedStatus(for record: NotarizationRecord, at now: Date) -> (status: NotarizationStatusCode, updatedAt: Date, failureReason: String?) {
        let age = now.timeIntervalSince(record.submittedAt)
        if age < 1.0 {
            return (.queued, now, nil)
        }
        if age < 2.5 {
            return (.inProgress, now, nil)
        }
        return (.completed, now, nil)
    }

    private func loadRecords() throws -> [NotarizationRecord] {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return [] }
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([NotarizationRecord].self, from: data)
    }

    private func save(records: [NotarizationRecord]) throws {
        try FileManager.default.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records.sorted { $0.updatedAt > $1.updatedAt })
        try data.write(to: manifestURL, options: .atomic)
    }

    private func iso8601(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct NotarizationRecord: Codable, Equatable {
    let id: String
    let fileName: String
    let filePath: String
    let sha256: String
    let submittedAt: Date
    let updatedAt: Date
    let status: NotarizationStatusCode
    let logLines: [String]
}
