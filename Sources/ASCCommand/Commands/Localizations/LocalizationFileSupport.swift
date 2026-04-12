import Foundation

enum LocalizationFileSupport {
    static func jsonFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }

        var urls: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            if item.pathExtension.lowercased() == "json" {
                urls.append(item)
            }
        }
        return urls
    }

    static func ensureDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureDirectory(at: url.deletingLastPathComponent())
        let data = try JSONEncoder.sortedPretty.encode(value)
        try data.write(to: url, options: .atomic)
    }

    static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }
}

private extension JSONEncoder {
    static var sortedPretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
