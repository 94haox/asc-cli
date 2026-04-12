import ArgumentParser
import Foundation

struct NotarizationSubmit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submit",
        abstract: "Submit a file for local notarization"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Path to the package or app file to notarize locally")
    var file: String

    @Flag(name: .long, help: "Wait until notarization finishes")
    var wait: Bool = false

    @Option(name: .long, help: "Poll interval in seconds")
    var pollInterval: Int = 10

    func run() async throws {
        let repo = try ClientProvider.makeNotarizationRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any NotarizationRepository) async throws -> String {
        let fileURL = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ValidationError("File not found: \(file)")
        }
        let submitted = try await repo.submitNotarization(fileURL: fileURL)
        let finalSubmission = try await withWaitIfNeeded(from: submitted, repo: repo)

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        if globals.outputFormat == .json {
            return try formatter.format(DataResponse(data: [finalSubmission]))
        }
        return try formatter.formatItems(
            [finalSubmission],
            headers: ["ID", "Status"],
            rowMapper: { [$0.id, $0.status.rawValue] }
        )
    }

    private func withWaitIfNeeded(
        from submitted: NotarizationSubmission,
        repo: any NotarizationRepository
    ) async throws -> NotarizationSubmission {
        guard wait else { return submitted }

        let deadline: Date? = parsedTimeoutSeconds().map { Date().addingTimeInterval(Double($0)) }
        var delay = pollInterval
        if delay < 1 { delay = 1 }

        while true {
            let status = try await repo.getNotarizationStatus(id: submitted.id)
            if !status.isPending {
                if status.hasFailed {
                    throw ValidationError("Notarization failed (id: \(submitted.id)): \(status.failureReason ?? "Unknown")")
                }
                return NotarizationSubmission(id: status.id, status: status.status)
            }

            if let deadline {
                if Date() >= deadline {
                    throw ValidationError("Timed out while waiting for notarization: \(submitted.id)")
                }
            }

            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func parsedTimeoutSeconds() -> Int? {
        guard let raw = globals.timeout?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let seconds = Int(raw) {
            return seconds
        }
        if raw.hasSuffix("s"), let seconds = Int(raw.dropLast()) {
            return seconds
        }
        if raw.hasSuffix("m"), let minutes = Int(raw.dropLast()) {
            return minutes * 60
        }
        return nil
    }
}
