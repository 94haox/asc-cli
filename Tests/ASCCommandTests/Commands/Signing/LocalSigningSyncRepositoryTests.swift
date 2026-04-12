import Foundation
import Testing
@testable import ASCCommand
@testable import Infrastructure

@Suite
struct LocalSigningSyncRepositoryTests {

    @Test func `push snapshots profiles and certificates into a local manifest`() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("asc-signing-sync-\(UUID().uuidString)")
        let profilesDir = workspace.appendingPathComponent("profiles")
        try FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let profileURL = profilesDir.appendingPathComponent("TeamProfile.mobileprovision")
        try Data("profile-bytes".utf8).write(to: profileURL)

        let store = LocalProvisioningProfileStore(
            searchDirectories: [profilesDir],
            decoder: StubProvisioningProfileDecoder(metadata: .init(
                id: "PROFILE-1",
                name: "Team Profile",
                expirationDate: nil
            ))
        )
        let shellRunner = StubShellRunner(stdout: """
          1) ABCDEF0123456789ABCDEF0123456789ABCDEF01 "Apple Development: Jane Doe (TEAM123)"
             1 valid identities found
        """)
        let repo = LocalSigningSyncRepository(
            workspaceDirectoryURL: workspace,
            profileStore: store,
            shellRunner: shellRunner
        )

        let result = try await repo.sync(direction: .push, dryRun: false, confirm: true)
        #expect(result.itemCount == 2)

        let manifestURL = workspace
            .appendingPathComponent(".asc")
            .appendingPathComponent("signing-sync")
            .appendingPathComponent("manifest.json")
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        #expect(((json?["profiles"] as? [[String: Any]])?.count) == 1)
        #expect(((json?["certificates"] as? [[String: Any]])?.count) == 1)
    }

    @Test func `pull restores profiles from the local manifest`() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("asc-signing-sync-pull-\(UUID().uuidString)")
        let profilesDir = workspace.appendingPathComponent("profiles")
        try FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let content = Data("restored-profile".utf8)
        let manifest: [String: Any] = [
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "certificates": [],
            "profiles": [
                [
                    "id": "PROFILE-RESTORE",
                    "name": "Restored Profile",
                    "fileName": "Restored.mobileprovision",
                    "sourcePath": "/tmp/restored.mobileprovision",
                    "content": content.base64EncodedString(),
                    "expirationDate": NSNull(),
                ],
            ],
        ]
        let manifestURL = workspace
            .appendingPathComponent(".asc")
            .appendingPathComponent("signing-sync")
            .appendingPathComponent("manifest.json")
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: manifestURL)

        let store = LocalProvisioningProfileStore(
            searchDirectories: [profilesDir],
            decoder: StubProvisioningProfileDecoder(metadata: .init(
                id: "PROFILE-RESTORE",
                name: "Restored Profile",
                expirationDate: nil
            ))
        )
        let repo = LocalSigningSyncRepository(
            workspaceDirectoryURL: workspace,
            profileStore: store,
            shellRunner: StubShellRunner(stdout: "")
        )

        let result = try await repo.sync(direction: .pull, dryRun: false, confirm: true)
        #expect(result.itemCount == 1)

        let restoredURL = profilesDir.appendingPathComponent("Restored.mobileprovision")
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
        #expect(try Data(contentsOf: restoredURL) == content)
    }
}

private struct StubProvisioningProfileDecoder: ProvisioningProfileDecoding {
    let metadata: ProvisioningProfileMetadata

    func decodeProfile(at url: URL) async throws -> ProvisioningProfileMetadata {
        _ = url
        return metadata
    }
}

private struct StubShellRunner: ShellRunner {
    let stdout: String

    func run(command: String, arguments: [String], environment: [String : String]?) async throws -> String {
        _ = command
        _ = arguments
        _ = environment
        return stdout
    }
}
