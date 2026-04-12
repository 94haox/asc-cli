import ArgumentParser
import Foundation

struct ScreenshotsListFrameDevices: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-frame-devices",
        abstract: "List supported devices for screenshot framing"
    )

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        print(try execute())
    }

    func execute() throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        if globals.outputFormat == .json {
            return try formatter.format(DataResponse(data: Self.devices))
        }
        return try formatter.formatItems(
            Self.devices,
            headers: ["ID", "Name", "Category", "Orientation"],
            rowMapper: { [$0.id, $0.name, $0.category, $0.orientation] }
        )
    }

    private static let devices: [ScreenshotsFrameDevice] = [
        .init(id: "iphone-16-pro-max", name: "iPhone 16 Pro Max", category: "iPhone", orientation: "portrait"),
        .init(id: "iphone-16", name: "iPhone 16", category: "iPhone", orientation: "portrait"),
        .init(id: "ipad-pro-13", name: "iPad Pro 13\"", category: "iPad", orientation: "portrait"),
        .init(id: "apple-watch-ultra-2", name: "Apple Watch Ultra 2", category: "Apple Watch", orientation: "portrait"),
    ]
}

private struct ScreenshotsFrameDevice: Codable {
    let id: String
    let name: String
    let category: String
    let orientation: String
}
