import Mockable

@Mockable
public protocol TestFlightFeedbackRepository: Sendable {
    func listScreenshotSubmissions(appId: String, buildId: String?, limit: Int?) async throws -> PaginatedResponse<TestFlightFeedbackSubmission>
    func listCrashSubmissions(appId: String, buildId: String?, limit: Int?) async throws -> PaginatedResponse<TestFlightCrashSubmission>
}
