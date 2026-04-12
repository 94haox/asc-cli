@preconcurrency import AppStoreConnect_Swift_SDK
import Foundation
import Testing
@testable import Infrastructure
@testable import Domain

@Suite
struct SDKTestFlightFeedbackRepositoryTests {

    @Test func `listScreenshotSubmissions injects buildId and maps comments`() async throws {
        let stub = StubAPIClient()
        stub.willReturn(BetaFeedbackScreenshotSubmissionsResponse(
            data: [
                BetaFeedbackScreenshotSubmission(
                    type: .betaFeedbackScreenshotSubmissions,
                    id: "feedback-1",
                    attributes: .init(
                        createdDate: Date(timeIntervalSince1970: 10),
                        comment: "Screenshot feedback",
                        email: "tester@example.com"
                    ),
                    relationships: .init(
                        build: .init(data: .init(type: .builds, id: "build-1"))
                    )
                )
            ],
            links: .init(this: ""),
            meta: .init(paging: .init(limit: 1))
        ))

        let repo = SDKTestFlightFeedbackRepository(client: stub)
        let result = try await repo.listScreenshotSubmissions(appId: "app-1", buildId: "build-1", limit: 1)

        #expect(result.data.count == 1)
        #expect(result.data[0].buildId == "build-1")
        #expect(result.data[0].comment == "Screenshot feedback")
        #expect(result.data[0].email == "tester@example.com")
    }

    @Test func `listCrashSubmissions injects buildId and crash log presence`() async throws {
        let stub = StubAPIClient()
        stub.willReturn(BetaFeedbackCrashSubmissionsResponse(
            data: [
                BetaFeedbackCrashSubmission(
                    type: .betaFeedbackCrashSubmissions,
                    id: "crash-1",
                    attributes: .init(
                        createdDate: Date(timeIntervalSince1970: 20),
                        comment: "Crash feedback",
                        email: "tester@example.com"
                    ),
                    relationships: .init(
                        crashLog: .init(links: .init(this: "https://example.com/crash-log")),
                        build: .init(data: .init(type: .builds, id: "build-2"))
                    )
                )
            ],
            links: .init(this: ""),
            meta: .init(paging: .init(limit: 1))
        ))

        let repo = SDKTestFlightFeedbackRepository(client: stub)
        let result = try await repo.listCrashSubmissions(appId: "app-1", buildId: "build-2", limit: 1)

        #expect(result.data.count == 1)
        #expect(result.data[0].buildId == "build-2")
        #expect(result.data[0].comment == "Crash feedback")
        #expect(result.data[0].hasCrashLog == true)
    }
}
