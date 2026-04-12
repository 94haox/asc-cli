import ArgumentParser
import Domain
import Foundation

// MARK: - Pre-release

struct TestFlightPreReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pre-release",
        abstract: "Manage pre-release TestFlight distribution",
        subcommands: [TestFlightPreReleaseCreate.self, TestFlightPreReleaseStatus.self]
    )
}

struct TestFlightPreReleaseCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Attach groups to a build and prepare pre-release distribution"
    )

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    @Option(name: .long, help: "App ID")
    var appId: String?

    @Option(name: .long, help: "Build ID")
    var buildId: String?

    @Option(name: .long, help: "Version string used to resolve the latest build")
    var version: String?

    @Option(name: .customLong("group-id"), help: "Beta group ID to attach")
    var groupIds: [String] = []

    func run() async throws {
        let repo = try ClientProvider.makeBuildRepository()
        print(try await execute(buildRepo: repo))
    }

    func execute(buildRepo: any BuildRepository) async throws -> String {
        let build = try await resolveBuild(using: buildRepo)
        if !groupIds.isEmpty {
            try await buildRepo.addBetaGroups(buildId: build.id, betaGroupIds: groupIds)
        }

        let receipt = TestFlightPreReleaseReceipt(
            buildId: build.id,
            appId: appId,
            version: build.version,
            buildNumber: build.buildNumber,
            groupIds: groupIds,
            processingState: build.processingState.rawValue,
            expired: build.expired,
            nextHint: "Build expiration is not available here. Use `asc builds info --build-id \(build.id)` to inspect the build."
        )
        return try encodeJSON(receipt, pretty: pretty)
    }

    private func resolveBuild(using repo: any BuildRepository) async throws -> Build {
        if let buildId {
            return try await repo.getBuild(id: buildId)
        }

        guard let version else {
            throw ValidationError("Provide --build-id or --version with --app-id.")
        }

        guard let appId else {
            throw ValidationError("Provide --app-id when resolving a build by version.")
        }

        let builds = try await repo.listBuilds(appId: appId, platform: nil, version: version, limit: nil).data
        guard let build = selectLatestBuild(from: builds) else {
            throw ValidationError("No matching build was found. Run `asc builds list --app-id \(appId) --version \(version)` first.")
        }
        return build
    }
}

struct TestFlightPreReleaseStatus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Inspect the TestFlight processing state for a build"
    )

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    @Option(name: .long, help: "Build ID")
    var buildId: String?

    @Option(name: .long, help: "App ID")
    var appId: String?

    @Option(name: .long, help: "Version string used to resolve the latest build")
    var version: String?

    func run() async throws {
        let repo = try ClientProvider.makeBuildRepository()
        print(try await execute(buildRepo: repo))
    }

    func execute(buildRepo: any BuildRepository) async throws -> String {
        let build = try await resolveBuild(using: buildRepo)
        let status = TestFlightPreReleaseStatusRecord(
            buildId: build.id,
            version: build.version,
            buildNumber: build.buildNumber,
            expired: build.expired,
            processingState: build.processingState.rawValue,
            isUsable: build.isUsable
        )
        return try encodeJSON(status, pretty: pretty)
    }

    private func resolveBuild(using repo: any BuildRepository) async throws -> Build {
        if let buildId {
            return try await repo.getBuild(id: buildId)
        }

        guard let version else {
            throw ValidationError("Provide --build-id or --version with --app-id.")
        }

        guard let appId else {
            throw ValidationError("Provide --app-id when resolving a build by version.")
        }

        let builds = try await repo.listBuilds(appId: appId, platform: nil, version: version, limit: nil).data
        guard let build = selectLatestBuild(from: builds) else {
            throw ValidationError("No matching build was found. Run `asc builds list --app-id \(appId) --version \(version)` first.")
        }
        return build
    }
}

private struct TestFlightPreReleaseReceipt: Codable {
    let buildId: String
    let appId: String?
    let version: String
    let buildNumber: String?
    let groupIds: [String]
    let processingState: String
    let expired: Bool
    let nextHint: String
}

private struct TestFlightPreReleaseStatusRecord: Codable {
    let buildId: String
    let version: String
    let buildNumber: String?
    let expired: Bool
    let processingState: String
    let isUsable: Bool
}

// MARK: - Feedback

struct TestFlightFeedbackCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "feedback",
        abstract: "Inspect feedback-related compatibility data",
        subcommands: [TestFlightFeedbackList.self, TestFlightFeedbackExport.self]
    )
}

struct TestFlightFeedbackList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Summarize TestFlight feedback for builds"
    )

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .long, help: "Build ID")
    var buildId: String?

    @Option(name: .long, help: "Version filter")
    var version: String?

    @Option(name: .long, help: "Maximum number of builds to return")
    var limit: Int?

    func run() async throws {
        let buildRepo = try ClientProvider.makeBuildRepository()
        let feedbackRepo = try ClientProvider.makeTestFlightFeedbackRepository()
        print(try await execute(buildRepo: buildRepo, feedbackRepo: feedbackRepo))
    }

    func execute(buildRepo: any BuildRepository, feedbackRepo: any TestFlightFeedbackRepository) async throws -> String {
        let builds = try await loadBuilds(buildRepo: buildRepo, appId: appId, buildId: buildId, version: version, limit: limit)
        let items = try await withThrowingTaskGroup(of: TestFlightFeedbackEntry.self) { taskGroup in
            for build in builds {
                taskGroup.addTask {
                    let submissions = try await feedbackRepo.listScreenshotSubmissions(appId: appId, buildId: build.id, limit: nil).data
                    return TestFlightFeedbackEntry(
                        buildId: build.id,
                        version: build.version,
                        buildNumber: build.buildNumber,
                        feedbackCount: submissions.count,
                        latestComment: latestComment(from: submissions),
                        visibility: build.isUsable ? "visible" : "hidden"
                    )
                }
            }

            var entries: [TestFlightFeedbackEntry] = []
            for try await entry in taskGroup {
                entries.append(entry)
            }
            return entries.sorted { $0.buildId < $1.buildId }
        }

        return try encodeJSON(TestFlightFeedbackSnapshot(appId: appId, items: items), pretty: pretty)
    }
}

struct TestFlightFeedbackExport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export feedback summary to a file"
    )

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .long, help: "Output file path")
    var output: String?

    @Option(name: .long, help: "Maximum number of builds to return")
    var limit: Int?

    func run() async throws {
        let buildRepo = try ClientProvider.makeBuildRepository()
        let feedbackRepo = try ClientProvider.makeTestFlightFeedbackRepository()
        print(try await execute(buildRepo: buildRepo, feedbackRepo: feedbackRepo))
    }

    func execute(buildRepo: any BuildRepository, feedbackRepo: any TestFlightFeedbackRepository) async throws -> String {
        let builds = try await loadBuilds(buildRepo: buildRepo, appId: appId, buildId: nil, version: nil, limit: limit)
        let items = try await withThrowingTaskGroup(of: TestFlightFeedbackEntry.self) { taskGroup in
            for build in builds {
                taskGroup.addTask {
                    let submissions = try await feedbackRepo.listScreenshotSubmissions(appId: appId, buildId: build.id, limit: nil).data
                    return TestFlightFeedbackEntry(
                        buildId: build.id,
                        version: build.version,
                        buildNumber: build.buildNumber,
                        feedbackCount: submissions.count,
                        latestComment: latestComment(from: submissions),
                        visibility: build.isUsable ? "visible" : "hidden"
                    )
                }
            }

            var entries: [TestFlightFeedbackEntry] = []
            for try await entry in taskGroup {
                entries.append(entry)
            }
            return entries.sorted { $0.buildId < $1.buildId }
        }

        let json = try encodeJSON(TestFlightFeedbackSnapshot(appId: appId, items: items), pretty: pretty)
        if let output {
            try json.write(toFile: output, atomically: true, encoding: .utf8)
        }
        return json
    }
}

private struct TestFlightFeedbackSnapshot: Codable {
    let appId: String
    let items: [TestFlightFeedbackEntry]
}

private struct TestFlightFeedbackEntry: Codable {
    let buildId: String
    let version: String
    let buildNumber: String?
    let feedbackCount: Int
    let latestComment: String?
    let visibility: String
}

// MARK: - Crashes

struct TestFlightCrashesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "crashes",
        abstract: "Inspect crash compatibility data",
        subcommands: [TestFlightCrashesList.self, TestFlightCrashesExport.self]
    )
}

struct TestFlightCrashesList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List crash data for TestFlight builds"
    )

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .long, help: "Build ID")
    var buildId: String?

    @Option(name: .long, help: "ISO-8601 lower bound")
    var since: String?

    func run() async throws {
        let buildRepo = try ClientProvider.makeBuildRepository()
        let feedbackRepo = try ClientProvider.makeTestFlightFeedbackRepository()
        print(try await execute(buildRepo: buildRepo, feedbackRepo: feedbackRepo))
    }

    func execute(buildRepo: any BuildRepository, feedbackRepo: any TestFlightFeedbackRepository) async throws -> String {
        let builds = try await loadBuilds(buildRepo: buildRepo, appId: appId, buildId: buildId, version: nil, limit: nil)
        let lowerBound = try since.map(parseISO8601Date(_:))

        let items = try await withThrowingTaskGroup(of: TestFlightCrashEntry.self) { taskGroup in
            for build in builds {
                taskGroup.addTask {
                    let submissions = try await feedbackRepo.listCrashSubmissions(appId: appId, buildId: build.id, limit: nil).data
                    let filtered = filter(submissions, since: lowerBound)
                    return TestFlightCrashEntry(
                        buildId: build.id,
                        version: build.version,
                        buildNumber: build.buildNumber,
                        crashCount: filtered.count,
                        latestComment: latestComment(from: filtered),
                        hasCrashLog: filtered.contains(where: \.hasCrashLog),
                        visibility: build.isUsable ? "visible" : "hidden"
                    )
                }
            }

            var entries: [TestFlightCrashEntry] = []
            for try await entry in taskGroup {
                entries.append(entry)
            }
            return entries.sorted { $0.buildId < $1.buildId }
        }

        return try encodeJSON(TestFlightCrashSnapshot(appId: appId, items: items), pretty: pretty)
    }
}

struct TestFlightCrashesExport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export crash data to a file"
    )

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .long, help: "Build ID")
    var buildId: String?

    @Option(name: .long, help: "ISO-8601 lower bound")
    var since: String?

    @Option(name: .long, help: "Output file path")
    var output: String?

    func run() async throws {
        let buildRepo = try ClientProvider.makeBuildRepository()
        let feedbackRepo = try ClientProvider.makeTestFlightFeedbackRepository()
        print(try await execute(buildRepo: buildRepo, feedbackRepo: feedbackRepo))
    }

    func execute(buildRepo: any BuildRepository, feedbackRepo: any TestFlightFeedbackRepository) async throws -> String {
        let builds = try await loadBuilds(buildRepo: buildRepo, appId: appId, buildId: buildId, version: nil, limit: nil)
        let lowerBound = try since.map(parseISO8601Date(_:))

        let items = try await withThrowingTaskGroup(of: TestFlightCrashEntry.self) { taskGroup in
            for build in builds {
                taskGroup.addTask {
                    let submissions = try await feedbackRepo.listCrashSubmissions(appId: appId, buildId: build.id, limit: nil).data
                    let filtered = filter(submissions, since: lowerBound)
                    return TestFlightCrashEntry(
                        buildId: build.id,
                        version: build.version,
                        buildNumber: build.buildNumber,
                        crashCount: filtered.count,
                        latestComment: latestComment(from: filtered),
                        hasCrashLog: filtered.contains(where: \.hasCrashLog),
                        visibility: build.isUsable ? "visible" : "hidden"
                    )
                }
            }

            var entries: [TestFlightCrashEntry] = []
            for try await entry in taskGroup {
                entries.append(entry)
            }
            return entries.sorted { $0.buildId < $1.buildId }
        }

        let json = try encodeJSON(TestFlightCrashSnapshot(appId: appId, items: items), pretty: pretty)
        if let output {
            try json.write(toFile: output, atomically: true, encoding: .utf8)
        }
        return json
    }
}

private struct TestFlightCrashSnapshot: Codable {
    let appId: String
    let items: [TestFlightCrashEntry]
}

private struct TestFlightCrashEntry: Codable {
    let buildId: String
    let version: String
    let buildNumber: String?
    let crashCount: Int
    let latestComment: String?
    let hasCrashLog: Bool
    let visibility: String
}

// MARK: - Config

struct TestFlightConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Export or import TestFlight compatibility snapshots",
        subcommands: [TestFlightConfigExport.self, TestFlightConfigImport.self]
    )
}

struct TestFlightConfigExport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export beta group and tester configuration"
    )

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .long, help: "Output file path")
    var output: String?

    @Flag(name: .customLong("include-builds"), help: "Include build metadata in the snapshot")
    var includeBuilds: Bool = false

    @Flag(name: .customLong("include-testers"), help: "Include testers in the snapshot")
    var includeTesters: Bool = false

    func run() async throws {
        let testFlightRepo = try ClientProvider.makeTestFlightRepository()
        let buildRepo = try ClientProvider.makeBuildRepository()
        print(try await execute(testFlightRepo: testFlightRepo, buildRepo: buildRepo))
    }

    func execute(testFlightRepo: any TestFlightRepository, buildRepo: any BuildRepository) async throws -> String {
        let groups = try await testFlightRepo.listBetaGroups(appId: appId, limit: nil).data
        let includeTesters = self.includeTesters
        let groupSnapshots: [TestFlightConfigGroupSnapshot] = try await withThrowingTaskGroup(of: TestFlightConfigGroupSnapshot.self) { taskGroup in
            for group in groups {
                taskGroup.addTask {
                    let testers = includeTesters
                        ? try await testFlightRepo.listBetaTesters(groupId: group.id, limit: nil).data.map {
                            TestFlightConfigTesterSnapshot(id: $0.id, email: $0.email, firstName: $0.firstName, lastName: $0.lastName)
                        }
                        : []
                    return TestFlightConfigGroupSnapshot(
                        id: group.id,
                        name: group.name,
                        isInternalGroup: group.isInternalGroup,
                        testers: testers
                    )
                }
            }

            var result: [TestFlightConfigGroupSnapshot] = []
            for try await snapshot in taskGroup {
                result.append(snapshot)
            }
            return result.sorted { $0.id < $1.id }
        }

        let builds = includeBuilds
            ? try await buildRepo.listBuilds(appId: appId, platform: nil, version: nil, limit: nil).data.map {
                TestFlightConfigBuildSnapshot(
                    id: $0.id,
                    version: $0.version,
                    buildNumber: $0.buildNumber,
                    expired: $0.expired,
                    processingState: $0.processingState.rawValue
                )
            }
            : []

        let snapshot = TestFlightConfigSnapshot(appId: appId, groups: groupSnapshots, builds: builds)
        let json = try encodeJSON(snapshot, pretty: pretty)
        if let output {
            try json.write(toFile: output, atomically: true, encoding: .utf8)
        }
        return json
    }
}

struct TestFlightConfigImport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import beta group and tester configuration"
    )

    @Flag(name: .customLong("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .long, help: "Input file path")
    var input: String

    @Flag(name: .customLong("dry-run"), help: "Preview changes without applying them")
    var dryRun: Bool = false

    @Flag(name: .customLong("confirm"), help: "Apply changes")
    var confirm: Bool = false

    func run() async throws {
        let repo = try ClientProvider.makeTestFlightRepository()
        print(try await execute(testFlightRepo: repo))
    }

    func execute(testFlightRepo: any TestFlightRepository) async throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: input))
        let snapshot = try JSONDecoder().decode(TestFlightConfigSnapshot.self, from: data)

        let currentGroups = try await testFlightRepo.listBetaGroups(appId: appId, limit: nil).data
        let currentByGroupId = Dictionary(uniqueKeysWithValues: currentGroups.map { ($0.id, $0) })
        let plannedGroups = snapshot.groups.filter { currentByGroupId[$0.id] == nil }

        let currentTesterEmails: [String: Set<String>] = try await withThrowingTaskGroup(of: (String, Set<String>).self) { taskGroup in
            for group in currentGroups {
                taskGroup.addTask {
                    let testers = try await testFlightRepo.listBetaTesters(groupId: group.id, limit: nil).data
                    return (group.id, Set(testers.compactMap(\.email)))
                }
            }

            var result: [String: Set<String>] = [:]
            for try await entry in taskGroup {
                result[entry.0] = entry.1
            }
            return result
        }

        var plannedAdds: [TestFlightConfigChange] = []
        var plannedRemoves: [TestFlightConfigChange] = []

        for group in snapshot.groups where currentByGroupId[group.id] != nil {
            let currentEmails = currentTesterEmails[group.id] ?? []
            let desiredEmails = Set(group.testers.compactMap(\.email))

            for email in desiredEmails where !currentEmails.contains(email) {
                plannedAdds.append(.tester(groupId: group.id, email: email))
            }
            for email in currentEmails where !desiredEmails.contains(email) {
                plannedRemoves.append(.tester(groupId: group.id, email: email))
            }
        }

        let plan = TestFlightConfigPlan(
            appId: snapshot.appId,
            dryRun: dryRun || !confirm,
            missingGroups: plannedGroups.map(\.id),
            plannedAdds: plannedAdds,
            plannedRemoves: plannedRemoves
        )

        if dryRun || !confirm {
            return try encodeJSON(plan, pretty: pretty)
        }

        for change in plannedAdds {
            guard case let .tester(groupId, email) = change else { continue }
            _ = try await testFlightRepo.addBetaTester(groupId: groupId, email: email, firstName: nil, lastName: nil)
        }

        for change in plannedRemoves {
            guard case let .tester(groupId, email) = change else { continue }
            guard let group = currentGroups.first(where: { $0.id == groupId }) else { continue }
            let testers = try await testFlightRepo.listBetaTesters(groupId: group.id, limit: nil).data
            if let tester = testers.first(where: { $0.email == email }) {
                try await testFlightRepo.removeBetaTester(groupId: group.id, testerId: tester.id)
            }
        }

        return try encodeJSON(TestFlightConfigPlan(
            appId: snapshot.appId,
            dryRun: false,
            missingGroups: plannedGroups.map(\.id),
            plannedAdds: [],
            plannedRemoves: []
        ), pretty: pretty)
    }
}

private struct TestFlightConfigSnapshot: Codable {
    let appId: String
    let groups: [TestFlightConfigGroupSnapshot]
    let builds: [TestFlightConfigBuildSnapshot]

    private enum CodingKeys: String, CodingKey {
        case appId, groups, builds
    }

    init(appId: String, groups: [TestFlightConfigGroupSnapshot], builds: [TestFlightConfigBuildSnapshot]) {
        self.appId = appId
        self.groups = groups
        self.builds = builds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appId = try container.decode(String.self, forKey: .appId)
        groups = try container.decodeIfPresent([TestFlightConfigGroupSnapshot].self, forKey: .groups) ?? []
        builds = try container.decodeIfPresent([TestFlightConfigBuildSnapshot].self, forKey: .builds) ?? []
    }
}

private struct TestFlightConfigGroupSnapshot: Codable {
    let id: String
    let name: String
    let isInternalGroup: Bool
    let testers: [TestFlightConfigTesterSnapshot]

    private enum CodingKeys: String, CodingKey {
        case id, name, isInternalGroup, testers
    }

    init(id: String, name: String, isInternalGroup: Bool, testers: [TestFlightConfigTesterSnapshot]) {
        self.id = id
        self.name = name
        self.isInternalGroup = isInternalGroup
        self.testers = testers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isInternalGroup = try container.decodeIfPresent(Bool.self, forKey: .isInternalGroup) ?? false
        testers = try container.decodeIfPresent([TestFlightConfigTesterSnapshot].self, forKey: .testers) ?? []
    }
}

private struct TestFlightConfigTesterSnapshot: Codable {
    let id: String?
    let email: String?
    let firstName: String?
    let lastName: String?
}

private struct TestFlightConfigBuildSnapshot: Codable {
    let id: String
    let version: String
    let buildNumber: String?
    let expired: Bool
    let processingState: String
}

private enum TestFlightConfigChange: Codable {
    case tester(groupId: String, email: String)

    private enum CodingKeys: String, CodingKey {
        case kind, groupId, email
    }

    private enum Kind: String, Codable {
        case tester
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .tester:
            self = .tester(
                groupId: try container.decode(String.self, forKey: .groupId),
                email: try container.decode(String.self, forKey: .email)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .tester(groupId, email):
            try container.encode(Kind.tester, forKey: .kind)
            try container.encode(groupId, forKey: .groupId)
            try container.encode(email, forKey: .email)
        }
    }
}

private struct TestFlightConfigPlan: Encodable {
    let appId: String
    let dryRun: Bool
    let missingGroups: [String]
    let plannedAdds: [TestFlightConfigChange]
    let plannedRemoves: [TestFlightConfigChange]
    var plannedGroups: [String] { missingGroups }

    private enum CodingKeys: String, CodingKey {
        case appId, dryRun, missingGroups, plannedGroups, plannedAdds, plannedRemoves
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appId, forKey: .appId)
        try container.encode(dryRun, forKey: .dryRun)
        try container.encode(missingGroups, forKey: .missingGroups)
        try container.encode(plannedGroups, forKey: .plannedGroups)
        try container.encode(plannedAdds, forKey: .plannedAdds)
        try container.encode(plannedRemoves, forKey: .plannedRemoves)
    }
}

// MARK: - Shared helpers

private func encodeJSON<T: Encodable>(_ value: T, pretty: Bool) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if pretty {
        encoder.outputFormatting.insert(.prettyPrinted)
    }
    let data = try encoder.encode(value)
    return String(data: data, encoding: .utf8) ?? "{}"
}

private func selectLatestBuild(from builds: [Build]) -> Build? {
    builds.max { isEarlierBuild($0, $1) }
}

private func isEarlierBuild(_ lhs: Build, _ rhs: Build) -> Bool {
    let leftNumber = Int(lhs.buildNumber ?? "") ?? -1
    let rightNumber = Int(rhs.buildNumber ?? "") ?? -1
    if leftNumber != rightNumber {
        return leftNumber < rightNumber
    }

    let leftUploaded = lhs.uploadedDate ?? .distantPast
    let rightUploaded = rhs.uploadedDate ?? .distantPast
    if leftUploaded != rightUploaded {
        return leftUploaded < rightUploaded
    }

    if lhs.version != rhs.version {
        return lhs.version < rhs.version
    }

    return lhs.id < rhs.id
}

private protocol TestFlightTimestampedSubmission {
    var id: String { get }
    var createdDate: Date? { get }
    var comment: String? { get }
}

extension TestFlightFeedbackSubmission: TestFlightTimestampedSubmission {}
extension TestFlightCrashSubmission: TestFlightTimestampedSubmission {}

private func loadBuilds(
    buildRepo: any BuildRepository,
    appId: String,
    buildId: String?,
    version: String?,
    limit: Int?
) async throws -> [Build] {
    if let buildId {
        return [try await buildRepo.getBuild(id: buildId)]
    }

    return try await buildRepo.listBuilds(appId: appId, platform: nil, version: version, limit: limit).data
}

private func parseISO8601Date(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: value) else {
        throw ValidationError("Provide --since as an ISO-8601 timestamp.")
    }
    return date
}

private func filter<T: TestFlightTimestampedSubmission>(_ submissions: [T], since lowerBound: Date?) -> [T] {
    guard let lowerBound else { return submissions }
    return submissions.filter { submission in
        guard let createdDate = submission.createdDate else { return false }
        return createdDate >= lowerBound
    }
}

private func latestComment<T: TestFlightTimestampedSubmission>(from submissions: [T]) -> String? {
    submissions.max { isEarlierSubmission($0, $1) }?.comment
}

private func isEarlierSubmission<T: TestFlightTimestampedSubmission>(_ lhs: T, _ rhs: T) -> Bool {
    switch (lhs.createdDate, rhs.createdDate) {
    case let (left?, right?) where left != right:
        return left < right
    case (nil, _?):
        return true
    case (_?, nil):
        return false
    default:
        break
    }

    return lhs.id < rhs.id
}
