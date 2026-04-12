import Mockable

@Mockable
public protocol SubmissionRepository: Sendable {
    func listSubmissions(appId: String) async throws -> [ReviewSubmission]
    func getSubmission(id: String) async throws -> ReviewSubmission
    func cancelSubmission(id: String) async throws -> ReviewSubmission
    func submitVersion(versionId: String) async throws -> ReviewSubmission
}
