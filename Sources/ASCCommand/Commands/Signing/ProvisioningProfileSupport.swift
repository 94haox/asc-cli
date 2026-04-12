import Foundation
import Infrastructure

struct ProvisioningProfileMetadata: Sendable, Equatable {
    let id: String
    let name: String
    let expirationDate: Date?

    var isNamed: Bool {
        !name.isEmpty
    }
}

struct ProvisioningProfileFile: Sendable, Equatable {
    let url: URL
    let content: Data
    let metadata: ProvisioningProfileMetadata

    var fileName: String {
        url.lastPathComponent
    }
}

protocol ProvisioningProfileDecoding: Sendable {
    func decodeProfile(at url: URL) async throws -> ProvisioningProfileMetadata
}

struct SecurityCMSProvisioningProfileDecoder: ProvisioningProfileDecoding {
    private let shellRunner: ShellRunner

    init(shellRunner: ShellRunner = SystemShellRunner()) {
        self.shellRunner = shellRunner
    }

    func decodeProfile(at url: URL) async throws -> ProvisioningProfileMetadata {
        let plistXML = try await shellRunner.run(
            command: "security",
            arguments: ["cms", "-D", "-i", url.path],
            environment: nil
        )
        guard let data = plistXML.data(using: .utf8) else {
            throw ValidationError("Unable to decode provisioning profile metadata at \(url.path)")
        }
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        guard let dict = plist as? [String: Any] else {
            throw ValidationError("Unexpected provisioning profile format at \(url.path)")
        }
        let identifier = (dict["UUID"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let name = (dict["Name"] as? String)
            ?? identifier
        let expirationDate = dict["ExpirationDate"] as? Date
        return ProvisioningProfileMetadata(
            id: identifier,
            name: name,
            expirationDate: expirationDate
        )
    }
}

struct LocalProvisioningProfileStore {
    let searchDirectories: [URL]
    let decoder: any ProvisioningProfileDecoding

    init(
        searchDirectories: [URL] = LocalProvisioningProfileStore.defaultSearchDirectories(),
        decoder: any ProvisioningProfileDecoding = SecurityCMSProvisioningProfileDecoder()
    ) {
        self.searchDirectories = searchDirectories
        self.decoder = decoder
    }

    func scanProfiles() async throws -> [ProvisioningProfileFile] {
        var seen: Set<String> = []
        var files: [ProvisioningProfileFile] = []
        for directory in searchDirectories {
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in urls where url.pathExtension == "mobileprovision" {
                if seen.contains(url.standardizedFileURL.path) { continue }
                seen.insert(url.standardizedFileURL.path)
                guard let content = try? Data(contentsOf: url) else { continue }
                let metadata = (try? await decoder.decodeProfile(at: url))
                    ?? ProvisioningProfileMetadata(
                        id: url.deletingPathExtension().lastPathComponent,
                        name: url.deletingPathExtension().lastPathComponent,
                        expirationDate: nil
                    )
                files.append(ProvisioningProfileFile(url: url, content: content, metadata: metadata))
            }
        }
        return files.sorted { lhs, rhs in
            lhs.metadata.name.localizedCaseInsensitiveCompare(rhs.metadata.name) == .orderedAscending
        }
    }

    func findProfile(matching profileId: String) async throws -> ProvisioningProfileFile? {
        let profiles = try await scanProfiles()
        return profiles.first(where: { profile in
            profile.metadata.id == profileId
            || profile.metadata.name == profileId
            || profile.fileName == profileId
            || profile.fileName == "\(profileId).mobileprovision"
            || profile.fileName.hasPrefix(profileId)
        })
    }

    func writeProfile(_ profile: ProvisioningProfileFile, to destinationDirectory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destinationURL = destinationDirectory.appendingPathComponent(profile.fileName)
        try profile.content.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    static func defaultSearchDirectories() -> [URL] {
        let fm = FileManager.default
        return [
            fm.currentDirectoryPathURL.appendingPathComponent("profiles"),
            fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library")
                .appendingPathComponent("MobileDevice")
                .appendingPathComponent("Provisioning Profiles"),
        ]
    }
}

private extension FileManager {
    var currentDirectoryPathURL: URL {
        URL(fileURLWithPath: currentDirectoryPath)
    }
}
