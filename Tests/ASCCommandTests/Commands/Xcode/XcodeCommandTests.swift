import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct XcodeVersionAliasTests {

    @Test func `version list reuses xcode cloud workflows`() async throws {
        let mockRepo = MockXcodeCloudWorkflowRepository()
        given(mockRepo).listWorkflows(productId: .value("prod-1")).willReturn([
            XcodeCloudWorkflow(
                id: "wf-1",
                productId: "prod-1",
                name: "Release CI",
                isEnabled: true,
                isLockedForEditing: false
            )
        ])

        let cmd = try XcodeVersionList.parse(["--product-id", "prod-1", "--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        #expect(output.contains("\"name\" : \"Release CI\""))
        #expect(output.contains("\"listBuildRuns\" : \"asc xcode-cloud builds list --workflow-id wf-1\""))
    }

    @Test func `version list without product id returns empty result`() async throws {
        let mockRepo = MockXcodeCloudWorkflowRepository()
        let cmd = try XcodeVersionList.parse(["--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        #expect(output.contains("\"data\" : ["))
        #expect(output.contains("]"))
    }
}
