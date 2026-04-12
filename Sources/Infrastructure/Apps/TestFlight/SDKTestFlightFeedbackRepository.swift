@preconcurrency import AppStoreConnect_Swift_SDK
import Domain

public struct SDKTestFlightFeedbackRepository: TestFlightFeedbackRepository, @unchecked Sendable {
    private let client: any APIClient

    public init(client: any APIClient) {
        self.client = client
    }

    public func listScreenshotSubmissions(appId: String, buildId: String?, limit: Int?) async throws -> PaginatedResponse<TestFlightFeedbackSubmission> {
        let request = APIEndpoint.v1.apps.id(appId).betaFeedbackScreenshotSubmissions.get(parameters: .init(
            filterBuild: buildId.map { [$0] },
            sort: [.minuscreatedDate],
            limit: limit,
            include: [.build]
        ))
        let response = try await client.request(request)
        return PaginatedResponse(
            data: response.data.map { mapScreenshotSubmission($0, buildId: buildId) },
            nextCursor: response.links.next,
            totalCount: response.meta?.paging.total
        )
    }

    public func listCrashSubmissions(appId: String, buildId: String?, limit: Int?) async throws -> PaginatedResponse<TestFlightCrashSubmission> {
        let request = APIEndpoint.v1.apps.id(appId).betaFeedbackCrashSubmissions.get(parameters: .init(
            filterBuild: buildId.map { [$0] },
            sort: [.minuscreatedDate],
            limit: limit,
            include: [.build]
        ))
        let response = try await client.request(request)
        return PaginatedResponse(
            data: response.data.map { mapCrashSubmission($0, buildId: buildId) },
            nextCursor: response.links.next,
            totalCount: response.meta?.paging.total
        )
    }

    private func mapScreenshotSubmission(_ sdk: AppStoreConnect_Swift_SDK.BetaFeedbackScreenshotSubmission, buildId: String?) -> TestFlightFeedbackSubmission {
        TestFlightFeedbackSubmission(
            id: sdk.id,
            buildId: sdk.relationships?.build?.data?.id ?? buildId ?? "",
            createdDate: sdk.attributes?.createdDate,
            comment: sdk.attributes?.comment,
            email: sdk.attributes?.email
        )
    }

    private func mapCrashSubmission(_ sdk: AppStoreConnect_Swift_SDK.BetaFeedbackCrashSubmission, buildId: String?) -> TestFlightCrashSubmission {
        TestFlightCrashSubmission(
            id: sdk.id,
            buildId: sdk.relationships?.build?.data?.id ?? buildId ?? "",
            createdDate: sdk.attributes?.createdDate,
            comment: sdk.attributes?.comment,
            email: sdk.attributes?.email,
            hasCrashLog: sdk.relationships?.crashLog?.links?.related != nil || sdk.relationships?.crashLog?.links?.this != nil
        )
    }
}
