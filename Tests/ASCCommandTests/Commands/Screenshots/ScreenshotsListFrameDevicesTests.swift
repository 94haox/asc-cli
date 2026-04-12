import Testing
@testable import ASCCommand

@Suite
struct ScreenshotsListFrameDevicesTests {

    @Test func `list-frame-devices outputs table by default format option`() async throws {
        let cmd = try ScreenshotsListFrameDevices.parse(["--output", "table"])
        let output = try cmd.execute()

        #expect(output.contains("Name"))
        #expect(output.contains("iPhone"))
    }

    @Test func `list-frame-devices supports json output with data root`() async throws {
        let cmd = try ScreenshotsListFrameDevices.parse(["--output", "json", "--pretty"])
        let output = try cmd.execute()
        #expect(output.contains("\"data\""))
        #expect(output.contains("\"id\""))
    }
}
