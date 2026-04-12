import ArgumentParser
import Foundation

struct ScreenshotsSizes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sizes",
        abstract: "List supported screenshot size presets"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Filter to a platform: ios, macos, tvos, or watchos")
    var platform: String?

    func run() async throws {
        print(try execute())
    }

    func execute() throws -> String {
        let all = Self.platforms
        let filtered = try filter(platform: platform, all: all)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        if globals.outputFormat == .json {
            return try formatter.format(DataResponse(data: filtered))
        }
        return try formatter.formatItems(
            filtered,
            headers: ["Platform", "Sizes"],
            rowMapper: { [$0.platform, $0.sizes.joined(separator: ", ")] }
        )
    }

    private func filter(platform: String?, all: [ScreenshotsPlatformSizes]) throws -> [ScreenshotsPlatformSizes] {
        guard let platform else { return all }
        let normalized = platform.lowercased()
        guard all.contains(where: { $0.platform == normalized }) else {
            throw ValidationError("Unsupported platform '\(platform)'. Expected ios, macos, tvos, or watchos.")
        }
        return all.filter { $0.platform == normalized }
    }

    private static let platforms: [ScreenshotsPlatformSizes] = [
        .init(platform: "ios", sizes: ["iPhone 6.7\"", "iPhone 6.5\"", "iPhone 6.1\"", "iPhone 5.5\""]),
        .init(platform: "macos", sizes: ["Mac 16\"", "Mac 13\""]),
        .init(platform: "tvos", sizes: ["Apple TV 1920×1080"]),
        .init(platform: "watchos", sizes: ["Apple Watch 44mm", "Apple Watch 40mm"]),
    ]
}

private struct ScreenshotsPlatformSizes: Codable {
    let platform: String
    let sizes: [String]
}
