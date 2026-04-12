import Foundation

struct ScreenshotsCapturePlan: Codable {
    struct Scene: Codable {
        let name: String
        let device: String
        let frame: Bool
    }

    let bundleId: String
    let scenes: [Scene]
}

struct ScreenshotsReviewManifest: Codable {
    struct Entry: Codable {
        let fileName: String
    }

    let title: String
    let entryCount: Int
    let entries: [Entry]
}

enum ScreenshotsFileSupport {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp"]

    static func imageFiles(in directory: URL, fileManager: FileManager = .default) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if imageExtensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        return files.sorted(by: { $0.path < $1.path })
    }

    static func ensureDirectory(_ url: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func copyFiles(_ files: [URL], to directory: URL, fileManager: FileManager = .default) throws {
        try ensureDirectory(directory, fileManager: fileManager)
        for file in files {
            let destination = directory.appendingPathComponent(file.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: file, to: destination)
        }
    }

    static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL, pretty: Bool = true) throws {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        let data = try encoder.encode(value)
        try ensureDirectory(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
    }
}

func collectImageURLs(at path: String, recursive: Bool = true) -> [URL] {
    let directory = URL(fileURLWithPath: path)
    guard recursive else {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { ScreenshotsFileSupport.imageExtensions.contains($0.pathExtension.lowercased()) }.sorted(by: { $0.path < $1.path })
    }
    return (try? ScreenshotsFileSupport.imageFiles(in: directory, fileManager: .default)) ?? []
}
