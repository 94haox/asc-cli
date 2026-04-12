import Foundation

public struct TestFlightCrashSubmission: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let buildId: String
    public let createdDate: Date?
    public let comment: String?
    public let email: String?
    public let hasCrashLog: Bool

    public init(
        id: String,
        buildId: String,
        createdDate: Date? = nil,
        comment: String? = nil,
        email: String? = nil,
        hasCrashLog: Bool = false
    ) {
        self.id = id
        self.buildId = buildId
        self.createdDate = createdDate
        self.comment = comment
        self.email = email
        self.hasCrashLog = hasCrashLog
    }
}
