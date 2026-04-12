import ArgumentParser
import Domain

struct BuildsInfo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "View a build or resolve the latest build for an app"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Build ID")
    var buildId: String?

    @Option(name: .long, help: "App ID")
    var app: String?

    @Option(name: .long, help: "Version string")
    var version: String?

    @Option(name: .long, help: "Platform (ios, macos, tvos, visionos)")
    var platform: String?

    @Flag(name: .long, help: "Use the latest build for the app")
    var latest: Bool = false

    func run() async throws {
        let repo = try ClientProvider.makeBuildRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any BuildRepository) async throws -> String {
        let selected: (build: Build, appId: String?)
        if let buildId {
            selected = (try await repo.getBuild(id: buildId), nil)
        } else {
            guard let app else {
                throw ValidationError("Provide --build-id or --app.")
            }
            guard latest || version != nil else {
                throw ValidationError("When using --app, provide --latest or --version.")
            }
            let response = try await repo.listBuilds(
                appId: app,
                platform: try parsePlatform(),
                version: version,
                limit: nil
            )
            guard let build = response.data.max(by: buildSortPredicate) else {
                throw ValidationError("No builds found for app \(app).")
            }
            selected = (build, app)
        }

        let payload = BuildInfoPayload(build: selected.build, appId: selected.appId)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        switch globals.outputFormat {
        case .json:
            return try formatter.format(SingleDataResponse(data: WithAffordances(payload)))
        case .table:
            return compatibleTable(headers: BuildInfoPayload.tableHeaders, rows: [payload.tableRow])
        case .markdown:
            return compatibleMarkdown(headers: BuildInfoPayload.tableHeaders, rows: [payload.tableRow])
        }
    }

    private func parsePlatform() throws -> BuildUploadPlatform? {
        guard let platform else { return nil }
        guard let parsed = BuildUploadPlatform(cliArgument: platform) else {
            throw ValidationError("Invalid platform '\(platform)'. Use: ios, macos, tvos, visionos")
        }
        return parsed
    }

    private func buildSortPredicate(_ lhs: Build, _ rhs: Build) -> Bool {
        (Int(lhs.buildNumber ?? "") ?? Int.min, lhs.id) < (Int(rhs.buildNumber ?? "") ?? Int.min, rhs.id)
    }
}

struct BuildsNextBuildNumber: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "next-build-number",
        abstract: "Compatibility alias for next-number"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "App ID")
    var appId: String

    @Option(name: .long, help: "Version string")
    var version: String

    @Option(name: .long, help: "Platform (ios, macos, tvos, visionos)")
    var platform: String

    func run() async throws {
        let repo = try ClientProvider.makeBuildRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any BuildRepository) async throws -> String {
        var command = BuildsNextNumber()
        command.globals = globals
        command.appId = appId
        command.version = version
        command.platform = platform
        return try await command.execute(repo: repo)
    }
}

struct BuildsAddGroups: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add-groups",
        abstract: "Compatibility alias for add-beta-group"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Build ID")
    var buildId: String

    @Option(name: .long, help: "Beta group ID (repeatable or comma-separated)")
    var group: [String] = []

    func run() async throws {
        let repo = try ClientProvider.makeBuildRepository()
        try await execute(repo: repo)
    }

    func execute(repo: any BuildRepository) async throws {
        try await repo.addBetaGroups(buildId: buildId, betaGroupIds: normalizedGroups(group))
    }
}

struct BuildsRemoveGroups: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove-groups",
        abstract: "Compatibility alias for remove-beta-group"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Build ID")
    var buildId: String

    @Option(name: .long, help: "Beta group ID (repeatable or comma-separated)")
    var group: [String] = []

    @Flag(name: .long, help: "Confirm removal")
    var confirm: Bool = false

    func run() async throws {
        let repo = try ClientProvider.makeBuildRepository()
        try await execute(repo: repo)
    }

    func execute(repo: any BuildRepository) async throws {
        try await repo.removeBetaGroups(buildId: buildId, betaGroupIds: normalizedGroups(group))
    }
}

struct BuildsTestNotesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-notes",
        abstract: "Compatibility namespace for beta notes",
        subcommands: [BuildsTestNotesCreate.self, BuildsTestNotesUpdate.self]
    )
}

struct BuildsTestNotesCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create beta notes")

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "Build ID") var buildId: String
    @Option(name: .long, help: "Locale") var locale: String
    @Option(name: .long, help: "Notes text") var notes: String?
    @Option(name: .long, help: "What's new alias") var whatsNew: String?

    func run() async throws {
        let repo = try ClientProvider.makeBetaBuildLocalizationRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any BetaBuildLocalizationRepository) async throws -> String {
        let loc = try await repo.upsertBetaBuildLocalization(buildId: buildId, locale: locale, whatsNew: try resolvedNotes())
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems(
            [loc],
            headers: ["ID", "Locale", "What's New"],
            rowMapper: { [$0.id, $0.locale, $0.whatsNew ?? ""] }
        )
    }

    private func resolvedNotes() throws -> String {
        guard let text = notes ?? whatsNew, !text.isEmpty else {
            throw ValidationError("Provide --notes or --whats-new.")
        }
        return text
    }
}

struct BuildsTestNotesUpdate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update beta notes")

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "Build ID") var buildId: String
    @Option(name: .long, help: "Locale") var locale: String
    @Option(name: .long, help: "Notes text") var notes: String?
    @Option(name: .long, help: "What's new alias") var whatsNew: String?

    func run() async throws {
        let repo = try ClientProvider.makeBetaBuildLocalizationRepository()
        print(try await execute(repo: repo))
    }

    func execute(repo: any BetaBuildLocalizationRepository) async throws -> String {
        let loc = try await repo.upsertBetaBuildLocalization(buildId: buildId, locale: locale, whatsNew: try resolvedNotes())
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try formatter.formatAgentItems(
            [loc],
            headers: ["ID", "Locale", "What's New"],
            rowMapper: { [$0.id, $0.locale, $0.whatsNew ?? ""] }
        )
    }

    private func resolvedNotes() throws -> String {
        guard let text = notes ?? whatsNew, !text.isEmpty else {
            throw ValidationError("Provide --notes or --whats-new.")
        }
        return text
    }
}

private struct BuildInfoPayload: Encodable, AffordanceProviding, Identifiable {
    let build: Build
    let appId: String?

    static let tableHeaders = ["Build ID", "Version", "Build Number", "Platform", "State", "Expired"]

    var id: String { build.id }
    var buildId: String { build.id }
    var affordances: [String : String] { build.affordances }
    var tableRow: [String] {
        [buildId, build.version, build.buildNumber ?? "-", build.platform?.rawValue ?? "-", build.processingState.rawValue, build.expired ? "true" : "false"]
    }

    private enum CodingKeys: String, CodingKey {
        case appId
        case buildId
        case buildNumber
        case expired
        case id
        case platform
        case processingState
        case version
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appId, forKey: .appId)
        try container.encode(buildId, forKey: .buildId)
        try container.encode(build.buildNumber, forKey: .buildNumber)
        try container.encode(build.expired, forKey: .expired)
        try container.encode(build.id, forKey: .id)
        try container.encodeIfPresent(build.platform, forKey: .platform)
        try container.encode(build.processingState, forKey: .processingState)
        try container.encode(build.version, forKey: .version)
    }
}

private func normalizedGroups(_ values: [String]) -> [String] {
    values
        .flatMap { $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } }
        .filter { !$0.isEmpty }
}

private func compatibleTable(headers: [String], rows: [[String]]) -> String {
    var widths = headers.map(\.count)
    for row in rows {
        for (index, value) in row.enumerated() where index < widths.count {
            widths[index] = max(widths[index], value.count)
        }
    }

    var lines: [String] = []
    lines.append(headers.enumerated().map { index, value in
        value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
    }.joined(separator: "  "))
    lines.append(widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "))
    for row in rows {
        lines.append(row.enumerated().map { index, value in
            value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
        }.joined(separator: "  "))
    }
    return lines.joined(separator: "\n")
}

private func compatibleMarkdown(headers: [String], rows: [[String]]) -> String {
    var lines: [String] = []
    lines.append("| " + headers.joined(separator: " | ") + " |")
    lines.append("| " + headers.map { _ in "---" }.joined(separator: " | ") + " |")
    for row in rows {
        lines.append("| " + row.joined(separator: " | ") + " |")
    }
    return lines.joined(separator: "\n")
}
