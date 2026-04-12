import ArgumentParser
import CryptoKit
import Foundation
import Domain

struct ProfilesDownload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download",
        abstract: "Export a provisioning profile from the local store"
    )

    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false

    @Option(name: .customLong("format"), help: "Output format: json, table, markdown")
    var format: String = "json"

    @Option(name: .long, help: "Profile resource ID")
    var id: String

    @Option(name: .long, help: "Output path in the local workspace (defaults to ./profiles/<name>.mobileprovision)")
    var output: String?

    func run() async throws {
        let repo = try ClientProvider.makeProfileDownloadRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any ProfileDownloadRepository) async throws -> String {
        let artifact = try await repo.downloadProfile(profileId: id)

        let targetPath = output ?? defaultOutputPath(for: artifact.name)
        let destinationURL = URL(fileURLWithPath: targetPath).standardizedFileURL
        do {
            try ensureDirectoryExists(for: destinationURL)
            try artifact.content.write(to: destinationURL, options: .atomic)
        } catch {
            throw CommandFallback.fileWriteError(
                command: "asc profiles download",
                path: destinationURL.path,
                reason: error.localizedDescription
            )
        }

        let summary = ProfileDownloadSummary(
            id: artifact.id,
            output: destinationURL.path,
            bytes: artifact.content.count,
            sha256: sha256Hex(of: artifact.content)
        )

        let outputFormat = OutputFormat(rawValue: format) ?? .json
        let formatter = OutputFormatter(format: outputFormat, pretty: pretty)
        if outputFormat == .json {
            return try formatter.format(DataResponse(data: [summary]))
        }
        return try formatter.formatItems(
            [summary],
            headers: ["Profile ID", "Output", "Bytes", "SHA256"],
            rowMapper: { [$0.id, $0.output, "\($0.bytes)", $0.sha256] }
        )
    }

    private func defaultOutputPath(for profileName: String) -> String {
        let fileName = profileName.hasSuffix(".mobileprovision") ?
            profileName :
            "\(profileName).mobileprovision"
        return "profiles/\(fileName)"
    }

    private func ensureDirectoryExists(for destinationURL: URL) throws {
        let directory = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
    }

    private func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
