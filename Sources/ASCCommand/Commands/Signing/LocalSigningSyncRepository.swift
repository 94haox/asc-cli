import Foundation
import Infrastructure

actor LocalSigningSyncRepository: SigningSyncRepository {
    private let workspaceDirectoryURL: URL
    private let storageDirectoryURL: URL
    private let manifestURL: URL
    private let profileStore: LocalProvisioningProfileStore
    private let shellRunner: ShellRunner

    init(
        workspaceDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        profileStore: LocalProvisioningProfileStore = LocalProvisioningProfileStore(),
        shellRunner: ShellRunner = SystemShellRunner()
    ) {
        self.workspaceDirectoryURL = workspaceDirectoryURL
        self.storageDirectoryURL = workspaceDirectoryURL
            .appendingPathComponent(".asc")
            .appendingPathComponent("signing-sync")
        self.manifestURL = storageDirectoryURL.appendingPathComponent("manifest.json")
        self.profileStore = profileStore
        self.shellRunner = shellRunner
    }

    func sync(direction: SigningSyncDirection, dryRun: Bool, confirm: Bool) async throws -> SigningSyncResult {
        switch direction {
        case .push:
            let snapshot = try await captureLocalSnapshot()
            if !dryRun {
                try save(snapshot: snapshot)
            }
            return SigningSyncResult(
                direction: direction,
                dryRun: dryRun,
                confirm: confirm,
                itemCount: snapshot.itemCount
            )
        case .pull:
            let manifest = try loadManifest()
            if !dryRun {
                try apply(manifest: manifest)
            }
            return SigningSyncResult(
                direction: direction,
                dryRun: dryRun,
                confirm: confirm,
                itemCount: manifest.itemCount
            )
        }
    }

    // MARK: - Snapshot

    private func captureLocalSnapshot() async throws -> SigningSyncManifest {
        let profiles = try await profileStore.scanProfiles()
        let certificates = try await scanCertificates()
        return SigningSyncManifest(
            updatedAt: Date(),
            certificates: certificates,
            profiles: profiles.map {
                SigningSyncProfileRecord(
                    id: $0.metadata.id,
                    name: $0.metadata.name,
                    fileName: $0.fileName,
                    sourcePath: $0.url.path,
                    content: $0.content,
                    expirationDate: $0.metadata.expirationDate
                )
            }
        )
    }

    private func scanCertificates() async throws -> [SigningSyncCertificateRecord] {
        do {
            let output = try await shellRunner.run(
                command: "security",
                arguments: ["find-identity", "-v", "-p", "codesigning"],
                environment: nil
            )
            let regex = try NSRegularExpression(pattern: "([0-9A-Fa-f]{40})\\s+\"([^\"]+)\"")
            return output
                .split(separator: "\n")
                .compactMap { line in
                    let string = String(line)
                    guard let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) else {
                        return nil
                    }
                    guard
                        let fingerprintRange = Range(match.range(at: 1), in: string),
                        let nameRange = Range(match.range(at: 2), in: string)
                    else {
                        return nil
                    }
                    return SigningSyncCertificateRecord(
                        id: String(string[fingerprintRange]),
                        name: String(string[nameRange]),
                        rawOutput: string
                    )
                }
        } catch {
            return []
        }
    }

    // MARK: - Apply / persistence

    private func apply(manifest: SigningSyncManifest) throws {
        let destinationDirectory = profileStore.searchDirectories.first ?? workspaceDirectoryURL.appendingPathComponent("profiles")
        for profile in manifest.profiles {
            let file = ProvisioningProfileFile(
                url: destinationDirectory.appendingPathComponent(profile.fileName),
                content: profile.content,
                metadata: ProvisioningProfileMetadata(
                    id: profile.id,
                    name: profile.name,
                    expirationDate: profile.expirationDate
                )
            )
            try profileStore.writeProfile(file, to: destinationDirectory)
        }
    }

    private func loadManifest() throws -> SigningSyncManifest {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return SigningSyncManifest(updatedAt: Date(), certificates: [], profiles: [])
        }
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SigningSyncManifest.self, from: data)
    }

    private func save(snapshot: SigningSyncManifest) throws {
        try FileManager.default.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: manifestURL, options: .atomic)
    }
}

private struct SigningSyncManifest: Codable {
    let updatedAt: Date
    let certificates: [SigningSyncCertificateRecord]
    let profiles: [SigningSyncProfileRecord]

    var itemCount: Int {
        certificates.count + profiles.count
    }
}

private struct SigningSyncCertificateRecord: Codable, Equatable {
    let id: String
    let name: String
    let rawOutput: String
}

private struct SigningSyncProfileRecord: Codable, Equatable {
    let id: String
    let name: String
    let fileName: String
    let sourcePath: String
    let content: Data
    let expirationDate: Date?
}
