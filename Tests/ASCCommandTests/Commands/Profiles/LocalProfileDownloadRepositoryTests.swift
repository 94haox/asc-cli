import Foundation
import Testing
@testable import ASCCommand

@Suite
struct LocalProfileDownloadRepositoryTests {

    @Test func `downloads profile from local provisioning profiles directory`() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("asc-profile-download-repo-\(UUID().uuidString)")
        let profilesDir = workspace.appendingPathComponent("profiles")
        try FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let profileURL = profilesDir.appendingPathComponent("DeveloperProfile.mobileprovision")
        let payload = Data("mobileprovision-bytes".utf8)
        try payload.write(to: profileURL)

        let decoder = StubProvisioningProfileDecoder(metadata: .init(
            id: "UUID-1234",
            name: "Developer Profile",
            expirationDate: nil
        ))
        let store = LocalProvisioningProfileStore(searchDirectories: [profilesDir], decoder: decoder)
        let repo = LocalProfileDownloadRepository(profileStore: store)

        let artifact = try await repo.downloadProfile(profileId: "UUID-1234")

        #expect(artifact.id == "UUID-1234")
        #expect(artifact.name == "Developer Profile")
        #expect(artifact.content == payload)
    }
}

private struct StubProvisioningProfileDecoder: ProvisioningProfileDecoding {
    let metadata: ProvisioningProfileMetadata

    func decodeProfile(at url: URL) async throws -> ProvisioningProfileMetadata {
        _ = url
        return metadata
    }
}
