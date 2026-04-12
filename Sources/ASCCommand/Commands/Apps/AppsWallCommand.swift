import ArgumentParser
import Domain
import Foundation

struct AppsWallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wall",
        abstract: "Compatibility namespace for app wall operations",
        subcommands: [AppsWallSubmit.self]
    )
}

struct AppsWallSubmit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submit",
        abstract: "Submit an app wall entry"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Developer display name")
    var developer: String?

    @Option(name: .long, help: "Legacy fallback name alias")
    var name: String?

    @Option(name: .long, help: "Developer/seller ID")
    var developerId: String?

    @Option(name: .long, help: "GitHub username")
    var github: String?

    @Option(name: .long, help: "X handle")
    var x: String?

    @Option(name: .long, help: "App Store Connect app ID (repeatable)")
    var appId: [String] = []

    @Option(name: .long, help: "App Store URLs")
    var app: [String] = []

    @Option(name: .long, help: "Legacy URL alias")
    var link: [String] = []

    @Option(name: .long, help: "GitHub token")
    var githubToken: String?

    @Option(name: .long, help: "Legacy token alias")
    var token: String?

    func run() async throws {
        let repo = ClientProvider.makeAppWallRepository(token: try resolveGitHubToken())
        print(try await execute(repo: repo))
    }

    func execute(repo: any AppWallRepository) async throws -> String {
        let appIdURLs = appId.map { "https://apps.apple.com/app/id\($0)" }
        let allApps = app + link + appIdURLs
        let wallApp = AppWallApp(
            developer: developer ?? name,
            developerId: developerId,
            github: github,
            x: x,
            apps: allApps.isEmpty ? nil : allApps
        )

        guard wallApp.hasAppSource else {
            throw ValidationError("Provide --developer-id, --app-id, --app, or --link so your apps appear on the wall.")
        }

        let submission = try await repo.submit(app: wallApp)
        let normalizedSubmission = AppWallSubmission(
            prNumber: submission.prNumber,
            prUrl: submission.prUrl,
            title: submission.title,
            developer: wallApp.developer ?? submission.developer
        )
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        switch globals.outputFormat {
        case .json:
            return try formatter.format(DataResponse(data: [normalizedSubmission]))
        case .table:
            return try formatter.formatItems(
                [normalizedSubmission],
                headers: ["PR #", "Title", "URL"],
                rowMapper: { [String($0.prNumber), $0.title, $0.prUrl] }
            )
        case .markdown:
            return try formatter.formatItems(
                [normalizedSubmission],
                headers: ["PR #", "Title", "URL"],
                rowMapper: { [String($0.prNumber), $0.title, $0.prUrl] }
            )
        }
    }

    private func resolveGitHubToken() throws -> String {
        if let githubToken, !githubToken.isEmpty { return githubToken }
        if let token, !token.isEmpty { return token }
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty { return token }
        if let token = runGHAuthToken(), !token.isEmpty { return token }
        throw ValidationError("GitHub token required. Pass --github-token, --token, set GITHUB_TOKEN, or run `gh auth login`.")
    }

    private func runGHAuthToken() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "token"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
