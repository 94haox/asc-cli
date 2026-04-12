import Foundation

public struct TestFlightFeedbackSubmission: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let buildId: String
    public let createdDate: Date?
    public let comment: String?
    public let email: String?

    public init(
        id: String,
        buildId: String,
        createdDate: Date? = nil,
        comment: String? = nil,
        email: String? = nil
    ) {
        self.id = id
        self.buildId = buildId
        self.createdDate = createdDate
        self.comment = comment
        self.email = email
    }
}
