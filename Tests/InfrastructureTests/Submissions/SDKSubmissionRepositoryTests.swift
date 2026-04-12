@preconcurrency import AppStoreConnect_Swift_SDK
import Foundation
import Testing
@testable import Infrastructure
@testable import Domain

@Suite
struct SDKSubmissionRepositoryTests {

    @Test func `listSubmissions injects appId and versionId from relationships`() async throws {
        let stub = SequencedStubAPIClient()

        stub.enqueue(ReviewSubmissionsResponse(
            data: [
                ReviewSubmission(
                    type: .reviewSubmissions,
                    id: "sub-1",
                    attributes: .init(platform: .ios, submittedDate: Date(timeIntervalSince1970: 10), state: .waitingForReview),
                    relationships: .init(
                        app: .init(data: .init(type: .apps, id: "app-1")),
                        appStoreVersionForReview: .init(data: .init(type: .appStoreVersions, id: "v-1"))
                    )
                )
            ],
            links: .init(this: ""),
            meta: nil
        ))

        let repo = OpenAPISubmissionRepository(client: stub)
        let result = try await repo.listSubmissions(appId: "app-1")

        #expect(result.count == 1)
        #expect(result[0].appId == "app-1")
        #expect(result[0].appStoreVersionId == "v-1")
        #expect(result[0].platform == .iOS)
        #expect(result[0].state == .waitingForReview)
    }

    @Test func `getSubmission maps appId and versionId from response`() async throws {
        let stub = SequencedStubAPIClient()

        stub.enqueue(ReviewSubmissionResponse(
            data: ReviewSubmission(
                type: .reviewSubmissions,
                id: "sub-2",
                attributes: .init(platform: .macOs, submittedDate: Date(timeIntervalSince1970: 20), state: .inReview),
                relationships: .init(
                    app: .init(data: .init(type: .apps, id: "app-2")),
                    appStoreVersionForReview: .init(data: .init(type: .appStoreVersions, id: "v-2"))
                )
            ),
            links: .init(this: "")
        ))

        let repo = OpenAPISubmissionRepository(client: stub)
        let result = try await repo.getSubmission(id: "sub-2")

        #expect(result.id == "sub-2")
        #expect(result.appId == "app-2")
        #expect(result.appStoreVersionId == "v-2")
        #expect(result.platform == .macOS)
        #expect(result.state == .inReview)
    }

    @Test func `cancelSubmission marks submission canceled`() async throws {
        let stub = SequencedStubAPIClient()

        stub.enqueue(ReviewSubmissionResponse(
            data: ReviewSubmission(
                type: .reviewSubmissions,
                id: "sub-3",
                attributes: .init(platform: .ios, submittedDate: Date(timeIntervalSince1970: 30), state: .waitingForReview),
                relationships: .init(
                    app: .init(data: .init(type: .apps, id: "app-3")),
                    appStoreVersionForReview: .init(data: .init(type: .appStoreVersions, id: "v-3"))
                )
            ),
            links: .init(this: "")
        ))
        stub.enqueue(ReviewSubmissionResponse(
            data: ReviewSubmission(
                type: .reviewSubmissions,
                id: "sub-3",
                attributes: .init(platform: .ios, submittedDate: Date(timeIntervalSince1970: 30), state: .canceling),
                relationships: .init(
                    app: .init(data: .init(type: .apps, id: "app-3")),
                    appStoreVersionForReview: .init(data: .init(type: .appStoreVersions, id: "v-3"))
                )
            ),
            links: .init(this: "")
        ))

        let repo = OpenAPISubmissionRepository(client: stub)
        let result = try await repo.cancelSubmission(id: "sub-3")

        #expect(result.id == "sub-3")
        #expect(result.appId == "app-3")
        #expect(result.appStoreVersionId == "v-3")
        #expect(result.state == .canceling)
    }

    @Test func `submitVersion injects appId from version relationship`() async throws {
        let stub = SequencedStubAPIClient()

        // Step 1: version response with app relationship
        stub.enqueue(AppStoreVersionResponse(
            data: AppStoreVersion(
                type: .appStoreVersions,
                id: "v-1",
                attributes: .init(platform: .ios, versionString: "1.0.0"),
                relationships: .init(
                    app: .init(data: .init(type: .apps, id: "app-42"))
                )
            ),
            links: .init(this: "")
        ))

        // Step 2: no existing open submissions
        stub.enqueue(ReviewSubmissionsResponse(data: [], links: .init(this: "")))

        // Step 3: create submission response
        stub.enqueue(ReviewSubmissionResponse(
            data: ReviewSubmission(
                type: .reviewSubmissions,
                id: "sub-99",
                attributes: .init(state: .waitingForReview)
            ),
            links: .init(this: "")
        ))

        // Step 4: add item response
        stub.enqueue(ReviewSubmissionItemResponse(
            data: ReviewSubmissionItem(
                type: .reviewSubmissionItems,
                id: "item-1"
            ),
            links: .init(this: "")
        ))

        // Step 5: patch (submitted) response
        stub.enqueue(ReviewSubmissionResponse(
            data: ReviewSubmission(
                type: .reviewSubmissions,
                id: "sub-99",
                attributes: .init(platform: .ios, state: .waitingForReview)
            ),
            links: .init(this: "")
        ))

        let repo = OpenAPISubmissionRepository(client: stub)
        let result = try await repo.submitVersion(versionId: "v-1")

        #expect(result.id == "sub-99")
        #expect(result.appId == "app-42")
        #expect(result.platform == .iOS)
        #expect(result.state == .waitingForReview)
    }

    @Test func `submitVersion maps state correctly`() async throws {
        let stub = SequencedStubAPIClient()

        stub.enqueue(AppStoreVersionResponse(
            data: AppStoreVersion(
                type: .appStoreVersions,
                id: "v-2",
                attributes: .init(platform: .macOs, versionString: "2.0.0"),
                relationships: .init(
                    app: .init(data: .init(type: .apps, id: "app-7"))
                )
            ),
            links: .init(this: "")
        ))
        stub.enqueue(ReviewSubmissionsResponse(data: [], links: .init(this: "")))
        stub.enqueue(ReviewSubmissionResponse(
            data: ReviewSubmission(
                type: .reviewSubmissions,
                id: "sub-77",
                attributes: .init(platform: .macOs, state: .inReview)
            ),
            links: .init(this: "")
        ))
        stub.enqueue(ReviewSubmissionItemResponse(
            data: ReviewSubmissionItem(type: .reviewSubmissionItems, id: "item-2"),
            links: .init(this: "")
        ))
        stub.enqueue(ReviewSubmissionResponse(
            data: ReviewSubmission(
                type: .reviewSubmissions,
                id: "sub-77",
                attributes: .init(state: .inReview)
            ),
            links: .init(this: "")
        ))

        let repo = OpenAPISubmissionRepository(client: stub)
        let result = try await repo.submitVersion(versionId: "v-2")

        #expect(result.platform == .macOS)
        #expect(result.state == .inReview)
        #expect(result.isPending == true)
    }

    @Test func `submitVersion reuses existing UNRESOLVED_ISSUES submission`() async throws {
        let stub = SequencedStubAPIClient()

        // Step 1: version response
        stub.enqueue(AppStoreVersionResponse(
            data: AppStoreVersion(
                type: .appStoreVersions,
                id: "v-3",
                attributes: .init(platform: .ios, versionString: "1.0.0"),
                relationships: .init(
                    app: .init(data: .init(type: .apps, id: "app-42"))
                )
            ),
            links: .init(this: "")
        ))

        // Step 2: existing submission with UNRESOLVED_ISSUES
        stub.enqueue(ReviewSubmissionsResponse(
            data: [ReviewSubmission(
                type: .reviewSubmissions,
                id: "sub-existing",
                attributes: .init(state: .unresolvedIssues)
            )],
            links: .init(this: "")
        ))

        // Step 3: patch (resubmit) response — skips create + add item
        stub.enqueue(ReviewSubmissionResponse(
            data: ReviewSubmission(
                type: .reviewSubmissions,
                id: "sub-existing",
                attributes: .init(platform: .ios, state: .waitingForReview)
            ),
            links: .init(this: "")
        ))

        let repo = OpenAPISubmissionRepository(client: stub)
        let result = try await repo.submitVersion(versionId: "v-3")

        #expect(result.id == "sub-existing")
        #expect(result.appId == "app-42")
        #expect(result.state == .waitingForReview)
    }
}
