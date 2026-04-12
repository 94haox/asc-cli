import ArgumentParser
import Domain

struct SubmitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submit",
        abstract: "Compatibility entrypoint for release submission flow",
        subcommands: [SubmitPreflight.self, SubmitCreate.self, SubmitStatus.self, SubmitCancel.self]
    )
}

struct SubmitPreflight: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preflight",
        abstract: "Check whether an app version is ready for submission"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "App ID") var app: String
    @Option(name: .long, help: "Version string") var version: String
    @Option(name: .long, help: "Platform") var platform: AppStorePlatform = .iOS

    func run() async throws {
        print(try await execute(
            appRepo: ClientProvider.makeAppRepository(),
            versionRepo: ClientProvider.makeVersionRepository(),
            buildRepo: ClientProvider.makeBuildRepository(),
            reviewDetailRepo: ClientProvider.makeReviewDetailRepository(),
            localizationRepo: ClientProvider.makeVersionLocalizationRepository(),
            screenshotRepo: ClientProvider.makeScreenshotRepository(),
            pricingRepo: ClientProvider.makePricingRepository()
        ))
    }

    func execute(
        appRepo: any AppRepository,
        versionRepo: any VersionRepository,
        buildRepo: any BuildRepository,
        reviewDetailRepo: any ReviewDetailRepository,
        localizationRepo: any VersionLocalizationRepository,
        screenshotRepo: any ScreenshotRepository,
        pricingRepo: any PricingRepository
    ) async throws -> String {
        let resolvedVersion = try await ReleaseFlowCompatibilitySupport.loadVersion(
            appId: app,
            versionString: version,
            platform: platform,
            versionRepo: versionRepo
        )
        let build: Build?
        if let buildId = resolvedVersion.buildId {
            build = try await buildRepo.getBuild(id: buildId)
        } else {
            build = nil
        }

        let assessment = try await ReleaseFlowCompatibilitySupport.assess(
            appId: app,
            version: resolvedVersion,
            build: build,
            appRepo: appRepo,
            buildRepo: buildRepo,
            reviewDetailRepo: reviewDetailRepo,
            localizationRepo: localizationRepo,
            screenshotRepo: screenshotRepo,
            pricingRepo: pricingRepo
        )

        let report = PreflightReport(
            id: resolvedVersion.id,
            appId: app,
            version: resolvedVersion.versionString,
            versionId: resolvedVersion.id,
            platform: resolvedVersion.platform,
            eligible: assessment.blockers.isEmpty,
            blockingIssues: assessment.blockers,
            warnings: assessment.warnings,
            checks: assessment.checks
        )

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try ReleaseFlowCompatibilitySupport.render(
            [report],
            formatter: formatter,
            headers: ["ID", "App ID", "Version", "Eligible"],
            rowMapper: { (item: PreflightReport) in [item.id, item.appId, item.version, item.eligible ? "yes" : "no"] }
        )
    }
}

struct SubmitCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Associate a build and submit the version for review"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "App ID") var app: String
    @Option(name: .long, help: "Version string") var version: String
    @Option(name: .long, help: "Build ID") var build: String
    @Flag(name: .long, help: "Run the command without changing server state") var dryRun = false
    @Flag(name: .long, help: "Confirm the action") var confirm = false

    func run() async throws {
        let versionRepo = try ClientProvider.makeVersionRepository()
        let buildRepo = try ClientProvider.makeBuildRepository()
        let submissionRepo = try ClientProvider.makeSubmissionRepository()
        print(try await execute(
            versionRepo: versionRepo,
            buildRepo: buildRepo,
            submissionRepo: submissionRepo
        ))
    }

    func execute(
        versionRepo: any VersionRepository,
        buildRepo: any BuildRepository,
        submissionRepo: any SubmissionRepository
    ) async throws -> String {
        guard dryRun || confirm else {
            throw ValidationError("Provide --confirm or --dry-run for submit create.")
        }

        let resolution = try await ReleaseFlowCompatibilitySupport.loadVersionAndBuild(
            appId: app,
            versionString: version,
            buildId: build,
            versionRepo: versionRepo,
            buildRepo: buildRepo
        )

        if dryRun {
            let plan = ReleaseRunReport(
                id: resolution.version.id,
                appId: app,
                version: version,
                validate: true,
                submit: true,
                publish: false,
                dryRun: true,
                mode: "dry-run",
                steps: [
                    .init(name: "link-build", status: "planned", detail: "Link \(build) to \(resolution.version.id)"),
                    .init(name: "submit", status: "planned", detail: "Submit \(resolution.version.id) for review")
                ]
            )
            let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
            return try ReleaseFlowCompatibilitySupport.render(
                [plan],
                formatter: formatter,
                headers: ["ID", "App ID", "Version", "Mode"],
                rowMapper: { [$0.id, $0.appId, $0.version, $0.mode] }
            )
        }

        if resolution.version.buildId != build {
            try await versionRepo.setBuild(versionId: resolution.version.id, buildId: build)
        }
        let submission = try await submissionRepo.submitVersion(versionId: resolution.version.id)
        let result = SubmitCreateResult(
            id: submission.id,
            submissionId: submission.id,
            appId: submission.appId,
            versionId: resolution.version.id,
            version: resolution.version.versionString,
            buildId: build,
            state: submission.state
        )

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try ReleaseFlowCompatibilitySupport.render(
            [result],
            formatter: formatter,
            headers: ["Submission ID", "App ID", "Version ID", "Build ID"],
            rowMapper: { [$0.submissionId, $0.appId, $0.versionId, $0.buildId] }
        )
    }
}

struct SubmitStatus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check submission status"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "Submission ID") var id: String?
    @Option(name: .long, help: "App Store Version ID") var versionId: String?

    func run() async throws {
        let versionRepo = try ClientProvider.makeVersionRepository()
        let submissionRepo = try ClientProvider.makeSubmissionRepository()
        print(try await execute(versionRepo: versionRepo, submissionRepo: submissionRepo))
    }

    func execute(
        versionRepo: any VersionRepository,
        submissionRepo: any SubmissionRepository
    ) async throws -> String {
        guard id != nil || versionId != nil else {
            throw ValidationError("Provide --id or --version-id.")
        }

        let submission: ReviewSubmission
        if let id {
            submission = try await submissionRepo.getSubmission(id: id)
        } else if let versionId {
            let version = try await versionRepo.getVersion(id: versionId)
            let submissions = try await submissionRepo.listSubmissions(appId: version.appId)
            guard let match = submissions.first(where: { $0.appStoreVersionId == versionId }) else {
                throw ValidationError("No review submission found for version \(versionId).")
            }
            submission = match
        } else {
            throw ValidationError("Provide --id or --version-id.")
        }

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try ReleaseFlowCompatibilitySupport.render(
            [submission],
            formatter: formatter,
            headers: ["ID", "App ID", "Version ID", "Platform", "State"],
            rowMapper: { [
                $0.id,
                $0.appId,
                $0.appStoreVersionId ?? "-",
                $0.platform.displayName,
                $0.state.displayName
            ] }
        )
    }
}

struct SubmitCancel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cancel",
        abstract: "Cancel a submission"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "Submission ID") var id: String
    @Flag(name: .long, help: "Confirm the action") var confirm = false

    func run() async throws {
        let repo = try ClientProvider.makeSubmissionRepository()
        print(try await execute(submissionRepo: repo))
    }

    func execute(submissionRepo: any SubmissionRepository) async throws -> String {
        guard confirm else {
            throw ValidationError("Provide --confirm to cancel submission \(id).")
        }
        let submission = try await submissionRepo.cancelSubmission(id: id)
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
        return try ReleaseFlowCompatibilitySupport.render(
            [submission],
            formatter: formatter,
            headers: ["ID", "App ID", "Version ID", "Platform", "State"],
            rowMapper: { [
                $0.id,
                $0.appId,
                $0.appStoreVersionId ?? "-",
                $0.platform.displayName,
                $0.state.displayName
            ] }
        )
    }
}
