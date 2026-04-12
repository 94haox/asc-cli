import Foundation
import Infrastructure

actor LocalProfileDownloadRepository: ProfileDownloadRepository {
    private let profileStore: LocalProvisioningProfileStore

    init(profileStore: LocalProvisioningProfileStore = LocalProvisioningProfileStore()) {
        self.profileStore = profileStore
    }

    func downloadProfile(profileId: String) async throws -> ProfileDownloadArtifact {
        guard let profile = try await profileStore.findProfile(matching: profileId) else {
            throw ValidationError("Provisioning profile not found: \(profileId)")
        }
        return ProfileDownloadArtifact(
            id: profile.metadata.id,
            name: profile.metadata.name,
            content: profile.content
        )
    }
}
