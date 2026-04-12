@preconcurrency import AppStoreConnect_Swift_SDK
import Domain

public struct OpenAPISubmissionRepository: SubmissionRepository, @unchecked Sendable {
    private let client: any APIClient

    public init(client: any APIClient) {
        self.client = client
    }

    public func listSubmissions(appId: String) async throws -> [Domain.ReviewSubmission] {
        let request = APIEndpoint.v1.reviewSubmissions.get(parameters: .init(
            filterApp: [appId],
            fieldsReviewSubmissions: [.platform, .submittedDate, .state, .app, .appStoreVersionForReview],
            include: [.app, .appStoreVersionForReview]
        ))
        let response = try await client.request(request)
        return try response.data.map { try mapSubmission($0, appId: appId) }
    }

    public func getSubmission(id: String) async throws -> Domain.ReviewSubmission {
        let request = APIEndpoint.v1.reviewSubmissions.id(id).get(parameters: .init(
            fieldsReviewSubmissions: [.platform, .submittedDate, .state, .app, .appStoreVersionForReview],
            include: [.app, .appStoreVersionForReview]
        ))
        let response = try await client.request(request)
        return try mapSubmission(response.data, appId: response.data.relationships?.app?.data?.id)
    }

    public func cancelSubmission(id: String) async throws -> Domain.ReviewSubmission {
        let existing = try await getSubmission(id: id)
        let request = APIEndpoint.v1.reviewSubmissions.id(id).patch(
            ReviewSubmissionUpdateRequest(
                data: .init(
                    type: .reviewSubmissions,
                    id: id,
                    attributes: .init(isCanceled: true)
                )
            )
        )
        let response = try await client.request(request)
        return try mapSubmission(
            response.data,
            appId: existing.appId,
            platform: existing.platform,
            appStoreVersionId: existing.appStoreVersionId
        )
    }

    public func submitVersion(versionId: String) async throws -> Domain.ReviewSubmission {
        // Step 1: Fetch the version to extract appId and platform
        let versionReq = APIEndpoint.v1.appStoreVersions.id(versionId).get(
            parameters: .init(include: [.app])
        )
        let versionResp = try await client.request(versionReq)
        guard
            let appId = versionResp.data.relationships?.app?.data?.id,
            let sdkPlatform = versionResp.data.attributes?.platform,
            let platform = Domain.AppStorePlatform(rawValue: sdkPlatform.rawValue)
        else {
            throw APIError.unknown("Failed to extract appId and platform from version \(versionId)")
        }

        // Step 2: Check for an existing open submission (UNRESOLVED_ISSUES or READY_FOR_REVIEW)
        let filterPlatform = APIEndpoint.V1.ReviewSubmissions.GetParameters.FilterPlatform(rawValue: sdkPlatform.rawValue)
        let listReq = APIEndpoint.v1.reviewSubmissions.get(parameters: .init(
            filterPlatform: filterPlatform.map { [$0] },
            filterState: [.unresolvedIssues, .readyForReview],
            filterApp: [appId]
        ))
        let listResp = try await client.request(listReq)
        if let existing = listResp.data.first {
            return try await patchSubmitted(id: existing.id, appId: appId, platform: platform, versionId: versionId)
        }

        // Step 3: Create new review submission
        let createReq = APIEndpoint.v1.reviewSubmissions.post(
            ReviewSubmissionCreateRequest(
                data: .init(
                    type: .reviewSubmissions,
                    attributes: .init(platform: sdkPlatform),
                    relationships: .init(
                        app: .init(data: .init(type: .apps, id: appId))
                    )
                )
            )
        )
        let submissionResp = try await client.request(createReq)
        let submissionId = submissionResp.data.id

        // Step 4: Add the version as a review submission item
        let itemReq = APIEndpoint.v1.reviewSubmissionItems.post(
            ReviewSubmissionItemCreateRequest(
                data: .init(
                    type: .reviewSubmissionItems,
                    relationships: .init(
                        reviewSubmission: .init(data: .init(type: .reviewSubmissions, id: submissionId)),
                        appStoreVersion: .init(data: .init(type: .appStoreVersions, id: versionId))
                    )
                )
            )
        )
        _ = try await client.request(itemReq)

        // Step 5: Submit for review
        return try await patchSubmitted(id: submissionId, appId: appId, platform: platform, versionId: versionId)
    }

    private func patchSubmitted(
        id: String,
        appId: String,
        platform: Domain.AppStorePlatform,
        versionId: String
    ) async throws -> Domain.ReviewSubmission {
        let submitReq = APIEndpoint.v1.reviewSubmissions.id(id).patch(
            ReviewSubmissionUpdateRequest(
                data: .init(
                    type: .reviewSubmissions,
                    id: id,
                    attributes: .init(isSubmitted: true)
                )
            )
        )
        let finalResp = try await client.request(submitReq)
        return try mapSubmission(finalResp.data, appId: appId, platform: platform, appStoreVersionId: versionId)
    }

    private func mapSubmission(
        _ sdkSubmission: AppStoreConnect_Swift_SDK.ReviewSubmission,
        appId: String? = nil,
        platform: Domain.AppStorePlatform? = nil,
        appStoreVersionId: String? = nil
    ) throws -> Domain.ReviewSubmission {
        let resolvedPlatform: Domain.AppStorePlatform
        if let platform {
            resolvedPlatform = platform
        } else if let sdkPlatform = sdkSubmission.attributes?.platform,
                  let mappedPlatform = Domain.AppStorePlatform(rawValue: sdkPlatform.rawValue) {
            resolvedPlatform = mappedPlatform
        } else {
            throw APIError.unknown("Failed to extract platform for review submission \(sdkSubmission.id)")
        }
        let state = sdkSubmission.attributes?.state.flatMap {
            Domain.ReviewSubmissionState(rawValue: $0.rawValue)
        } ?? .readyForReview
        let resolvedAppId = appId ?? sdkSubmission.relationships?.app?.data?.id ?? ""
        let resolvedVersionId = appStoreVersionId
            ?? sdkSubmission.relationships?.appStoreVersionForReview?.data?.id
        return Domain.ReviewSubmission(
            id: sdkSubmission.id,
            appId: resolvedAppId,
            appStoreVersionId: resolvedVersionId,
            platform: resolvedPlatform,
            state: state,
            submittedDate: sdkSubmission.attributes?.submittedDate
        )
    }
}
