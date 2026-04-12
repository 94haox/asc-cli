import Testing
@testable import ASCCommand

@Suite
struct ScreenshotsSizesTests {

    @Test func `sizes defaults to all platforms in pretty json`() async throws {
        let cmd = try ScreenshotsSizes.parse(["--pretty"])
        let output = try cmd.execute()
        #expect(output.contains("\"platform\" : \"ios\""))
        #expect(output.contains("\"platform\" : \"macos\""))
        #expect(output.contains("\"platform\" : \"tvos\""))
        #expect(output.contains("\"platform\" : \"watchos\""))
    }

    @Test func `sizes supports platform filter`() async throws {
        let cmd = try ScreenshotsSizes.parse(["--platform", "ios", "--pretty"])
        let output = try cmd.execute()
        #expect(output.contains("\"platform\" : \"ios\""))
        #expect(!output.contains("\"platform\" : \"tvos\""))
        #expect(output.contains("iPhone 6.7"))
    }

    @Test func `sizes rejects unsupported platform`() async throws {
        let cmd = try ScreenshotsSizes.parse(["--platform", "android", "--pretty"])
        await #expect(throws: (any Error).self) {
            _ = try cmd.execute()
        }
    }
}
