import ArgumentParser
import Domain
import Foundation

// MARK: - Notarization

protocol NotarizationRepository: Sendable {
    func submitNotarization(fileURL: URL) async throws -> NotarizationSubmission
    func listNotarizations(limit: Int?) async throws -> [NotarizationSubmission]
    func getNotarizationStatus(id: String) async throws -> NotarizationSubmissionStatus
    func getNotarizationLog(id: String) async throws -> NotarizationSubmissionLog
}

enum NotarizationStatusCode: String, Sendable, Codable {
    case queued
    case inProgress = "in_progress"
    case completed
    case invalid
    case failed

    var isPending: Bool {
        self == .queued || self == .inProgress
    }
}

struct NotarizationSubmission: Sendable, Codable, Equatable, Identifiable, Presentable {
    let id: String
    let status: NotarizationStatusCode

    static let tableHeaders = ["ID", "Status"]
    var tableRow: [String] {
        [id, status.rawValue]
    }
}

struct NotarizationSubmissionStatus: Sendable, Codable, Equatable, Identifiable, Presentable {
    let id: String
    let eligible: Bool
    let status: NotarizationStatusCode
    let startedAt: String?
    let updatedAt: String?
    let failureReason: String?

    var hasFailed: Bool {
        status == .failed || status == .invalid
    }

    var isPending: Bool {
        status.isPending
    }

    static let tableHeaders = ["ID", "Eligible", "Status", "Started At", "Updated At", "Failure Reason"]
    var tableRow: [String] {
        [
            id,
            eligible ? "true" : "false",
            status.rawValue,
            startedAt ?? "-",
            updatedAt ?? "-",
            failureReason ?? "-",
        ]
    }
}

struct NotarizationSubmissionLog: Sendable, Codable, Equatable, Identifiable, Presentable {
    let id: String
    let lines: [String]

    static let tableHeaders = ["ID", "Log"]
    var tableRow: [String] {
        [id, lines.joined(separator: "\n")]
    }

    var text: String {
        lines.joined(separator: "\n")
    }
}

// MARK: - Signing sync

protocol SigningSyncRepository: Sendable {
    func sync(direction: SigningSyncDirection, dryRun: Bool, confirm: Bool) async throws -> SigningSyncResult
}

enum SigningSyncDirection: String, Sendable, Codable {
    case pull
    case push
}

struct SigningSyncResult: Sendable, Codable, Equatable, Identifiable, Presentable {
    let direction: SigningSyncDirection
    let dryRun: Bool
    let confirm: Bool
    let itemCount: Int

    var id: String { "\(direction.rawValue)-\(confirm)" }

    static let tableHeaders = ["Direction", "Mode", "Items", "Confirm"]
    var tableRow: [String] {
        [direction.rawValue, dryRun ? "dry-run" : "apply", "\(itemCount)", confirm ? "true" : "false"]
    }
}

// MARK: - Profiles download

protocol ProfileDownloadRepository: Sendable {
    func downloadProfile(profileId: String) async throws -> ProfileDownloadArtifact
}

struct ProfileDownloadArtifact: Sendable, Codable, Equatable {
    let id: String
    let name: String
    let content: Data
}

struct ProfileDownloadSummary: Sendable, Codable, Equatable, Identifiable, Presentable {
    let id: String
    let output: String
    let bytes: Int
    let sha256: String

    static let tableHeaders = ["Profile ID", "Output", "Bytes", "SHA256"]
    var tableRow: [String] {
        [id, output, "\(bytes)", sha256]
    }
}

// MARK: - Structured command errors

enum CommandFallback {
    enum ErrorCode: String {
        case fileIO = "fileIO"
    }

    static func fileWriteError(
        command: String,
        path: String,
        reason: String
    ) -> ValidationError {
        let payload: [String: String] = [
            "code": ErrorCode.fileIO.rawValue,
            "command": command,
            "path": path,
            "reason": reason,
        ]
        return ValidationError(CommandFallback.serialize(payload))
    }

    private static func serialize(_ payload: [String: String]) -> String {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys]
            ),
            let json = String(data: data, encoding: .utf8)
        else {
            return payload.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        }
        return json
    }
}
