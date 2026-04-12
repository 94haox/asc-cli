import Foundation
import ArgumentParser
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct ProfilesDownloadTests {

    @Test func `abstract describes local store semantics`() {
        #expect(ProfilesDownload.configuration.abstract == "Export a provisioning profile from the local store")
    }

    @Test func `downloads profile and writes output file`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-profile-download-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputPath = tempDir.appendingPathComponent("profile.mobileprovision").path
        let mockRepo = MockProfileDownloadRepository()
        await mockRepo.setArtifact(ProfileDownloadArtifact(
            id: "p-1",
            name: "DeveloperProfile",
            content: Data([0x00, 0x01, 0x02])
        ))

        let cmd = try ProfilesDownload.parse(["--id", "p-1", "--output", outputPath, "--pretty"])
        let output = try await cmd.execute(repo: mockRepo)
        let normalized = output.replacingOccurrences(of: "\\/", with: "/")

        #expect(FileManager.default.fileExists(atPath: outputPath))
        #expect(try Data(contentsOf: URL(fileURLWithPath: outputPath)) == Data([0x00, 0x01, 0x02]))
        #expect(normalized.contains("\"output\" : \"\(outputPath)\""))
        #expect(normalized.contains("\"bytes\" : 3"))
    }

    @Test func `uses default output path under profiles directory`() async throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("asc-profile-download-default-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)

        let previous = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tempBase.path)
        defer { FileManager.default.changeCurrentDirectoryPath(previous) }

        let mockRepo = MockProfileDownloadRepository()
        await mockRepo.setArtifact(ProfileDownloadArtifact(
            id: "p-2",
            name: "TeamProfile",
            content: Data([0x03, 0x04, 0x05, 0x06])
        ))

        let cmd = try ProfilesDownload.parse(["--id", "p-2", "--pretty"])
        _ = try await cmd.execute(repo: mockRepo)

        let expectedPath = tempBase.appendingPathComponent("profiles/TeamProfile.mobileprovision").path
        #expect(FileManager.default.fileExists(atPath: expectedPath))
        #expect(try Data(contentsOf: URL(fileURLWithPath: expectedPath)) == Data([0x03, 0x04, 0x05, 0x06]))
        defer { try? FileManager.default.removeItem(at: tempBase) }
    }

    @Test func `propagates writable file error as structured payload`() async throws {
        let mockRepo = MockProfileDownloadRepository()
        await mockRepo.setArtifact(ProfileDownloadArtifact(
            id: "p-3",
            name: "BadProfile",
            content: Data([0x07])
        ))

        let path = "/"
        let cmd = try ProfilesDownload.parse(["--id", "p-3", "--output", path])
        do {
            _ = try await cmd.execute(repo: mockRepo)
            #expect(Bool(false))
        } catch {
            guard let validation = error as? ValidationError else {
                Issue.record("Expected ValidationError, got \(error)")
                return
            }
            let decoded = try JSONSerialization.jsonObject(with: Data(validation.message.utf8)) as? [String: String]
            #expect(decoded?["code"] == "fileIO")
            #expect(decoded?["command"] == "asc profiles download")
            #expect(decoded?["path"] == "/")
            #expect((decoded?["reason"]?.isEmpty == false) == true)
        }
    }

    @Test func `propagates repository failure when download fails`() async throws {
        let cmd = try ProfilesDownload.parse(["--id", "p-4"])
        await #expect(throws: ProfileDownloadTestError.self) {
            _ = try await cmd.execute(repo: FailingProfileDownloadRepository())
        }
    }
}

private actor MockProfileDownloadRepository: ProfileDownloadRepository {
    private var artifact: ProfileDownloadArtifact = ProfileDownloadArtifact(id: "placeholder", name: "placeholder", content: Data())

    func setArtifact(_ value: ProfileDownloadArtifact) async {
        artifact = value
    }

    func downloadProfile(profileId: String) async throws -> ProfileDownloadArtifact {
        _ = profileId
        return artifact
    }
}

private actor FailingProfileDownloadRepository: ProfileDownloadRepository {
    func downloadProfile(profileId: String) async throws -> ProfileDownloadArtifact {
        _ = profileId
        throw ProfileDownloadTestError.failed
    }
}

private enum ProfileDownloadTestError: Error {
    case failed
}
