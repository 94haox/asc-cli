import ArgumentParser
import Domain
import Foundation

struct ReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Compatibility entrypoint for staged release flow",
        subcommands: [ReleaseStage.self, ReleaseRun.self]
    )
}

struct ReleaseStage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stage",
        abstract: "Prepare a release without mutating remote state"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "App ID") var app: String
    @Option(name: .long, help: "Version string") var version: String
    @Option(name: .long, help: "Metadata directory") var metadataDir: String?
    @Option(name: .long, help: "Copy metadata from directory") var copyMetadataFrom: String?
    @Flag(name: .long, help: "Confirm the stage action") var confirm = false

    func run() async throws {
        print(try await execute(fileManager: .default))
    }

    func execute(fileManager: FileManager = .default) async throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)

        if !confirm {
            let report = ReleaseStageReport(
                id: "\(app):\(version)",
                appId: app,
                version: version,
                metadataDir: metadataDir,
                copyMetadataFrom: copyMetadataFrom,
                confirmed: false,
                mode: "dry-run",
                actions: [
                    .init(name: "prepare-metadata", status: "planned", detail: metadataDir.map { "Use metadata at \($0)" } ?? "No metadata directory provided"),
                    .init(name: "stage-release", status: "planned", detail: "Stage version \(version) for app \(app)")
                ]
            )

            return try ReleaseFlowCompatibilitySupport.render(
                [report],
                formatter: formatter,
                headers: ["App ID", "Version", "Mode"],
                rowMapper: { [$0.appId, $0.version, $0.mode] }
            )
        }

        guard let metadataDir else {
            throw ValidationError("Provide --metadata-dir when confirming release staging.")
        }

        let metadataURL = URL(fileURLWithPath: metadataDir)
        try fileManager.createDirectory(at: metadataURL, withIntermediateDirectories: true)

        var actions: [FlowPlanStep] = [
            .init(name: "prepare-metadata", status: "completed", detail: "Prepared metadata directory at \(metadataDir)")
        ]

        if let copyMetadataFrom {
            let sourceURL = URL(fileURLWithPath: copyMetadataFrom)
            try copyMetadata(from: sourceURL, to: metadataURL, fileManager: fileManager)
            actions.insert(
                .init(name: "copy-metadata", status: "completed", detail: "Copied metadata from \(copyMetadataFrom)"),
                at: 0
            )
        }

        let report = ReleaseStageReport(
            id: "\(app):\(version)",
            appId: app,
            version: version,
            metadataDir: metadataDir,
            copyMetadataFrom: copyMetadataFrom,
            confirmed: true,
            mode: "staged",
            actions: actions
        )

        return try ReleaseFlowCompatibilitySupport.render(
            [report],
            formatter: formatter,
            headers: ["App ID", "Version", "Mode"],
            rowMapper: { [$0.appId, $0.version, $0.mode] }
        )
    }
}

struct ReleaseRun: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the release flow"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "App ID") var app: String
    @Option(name: .long, help: "Version string") var version: String
    @Flag(name: .long, help: "Validate before continuing") var validate = false
    @Flag(name: .long, help: "Submit after validation") var submit = false
    @Flag(name: .long, help: "Publish after submission") var publish = false
    @Flag(name: .long, help: "Run without side effects") var dryRun = false

    func run() async throws {
        print(try await execute(
            versionRepo: try ClientProvider.makeVersionRepository(),
            buildRepo: try ClientProvider.makeBuildRepository(),
            appRepo: try ClientProvider.makeAppRepository(),
            reviewDetailRepo: try ClientProvider.makeReviewDetailRepository(),
            localizationRepo: try ClientProvider.makeVersionLocalizationRepository(),
            screenshotRepo: try ClientProvider.makeScreenshotRepository(),
            pricingRepo: try ClientProvider.makePricingRepository(),
            submissionRepo: try ClientProvider.makeSubmissionRepository()
        ))
    }

    func execute(
        versionRepo: any VersionRepository,
        buildRepo: any BuildRepository,
        appRepo: any AppRepository,
        reviewDetailRepo: any ReviewDetailRepository,
        localizationRepo: any VersionLocalizationRepository,
        screenshotRepo: any ScreenshotRepository,
        pricingRepo: any PricingRepository,
        submissionRepo: any SubmissionRepository
    ) async throws -> String {
        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)

        if dryRun {
            let report = ReleaseRunReport(
                id: "\(app):\(version)",
                appId: app,
                version: version,
                validate: validate,
                submit: submit,
                publish: publish,
                dryRun: true,
                mode: "dry-run",
                steps: [
                    .init(name: "validate", status: validate ? "planned" : "skipped", detail: validate ? "Validate before release" : "Validation not requested"),
                    .init(name: "submit", status: submit ? "planned" : "skipped", detail: submit ? "Submit after validation" : "Submission not requested"),
                    .init(name: "publish", status: publish ? "planned" : "skipped", detail: publish ? "Publish after submission" : "Publish not requested")
                ]
            )

            return try ReleaseFlowCompatibilitySupport.render(
                [report],
                formatter: formatter,
                headers: ["App ID", "Version", "Dry Run"],
                rowMapper: { [$0.appId, $0.version, $0.dryRun ? "yes" : "no"] }
            )
        }

        let resolvedVersion = try await ReleaseFlowCompatibilitySupport.loadVersion(
            appId: app,
            versionString: version,
            platform: nil,
            versionRepo: versionRepo
        )
        let build: Build?
        if let buildId = resolvedVersion.buildId {
            build = try await buildRepo.getBuild(id: buildId)
        } else {
            build = nil
        }

        var validationResult: (blockers: [String], warnings: [String], checks: [CompatibilityCheck])? = nil
        var steps: [FlowPlanStep] = []

        if validate {
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
            validationResult = assessment
            if assessment.blockers.isEmpty {
                steps.append(.init(name: "validate", status: "completed", detail: "Validation passed"))
            } else {
                steps.append(.init(name: "validate", status: "failed", detail: assessment.blockers.joined(separator: "; ")))
            }
        } else {
            steps.append(.init(name: "validate", status: "skipped", detail: "Validation not requested"))
        }

        let canSubmit = validationResult?.blockers.isEmpty ?? true
        var submission: ReviewSubmission?

        if submit {
            if canSubmit {
                let createdSubmission = try await submissionRepo.submitVersion(versionId: resolvedVersion.id)
                submission = createdSubmission
                steps.append(.init(name: "submit", status: "completed", detail: "Submitted version \(resolvedVersion.versionString) as \(createdSubmission.id)"))
            } else {
                steps.append(.init(name: "submit", status: "skipped", detail: "Submission blocked by validation issues"))
            }
        } else {
            steps.append(.init(name: "submit", status: "skipped", detail: "Submission not requested"))
        }

        if publish {
            if let submission {
                steps.append(.init(name: "publish", status: "completed", detail: "Recorded publish handoff for submission \(submission.id)"))
            } else if submit && !canSubmit {
                steps.append(.init(name: "publish", status: "skipped", detail: "Publish blocked by validation issues"))
            } else {
                steps.append(.init(name: "publish", status: "skipped", detail: "No submission was created"))
            }
        } else {
            steps.append(.init(name: "publish", status: "skipped", detail: "Publish not requested"))
        }

        let report = ReleaseRunReport(
            id: resolvedVersion.id,
            appId: app,
            version: resolvedVersion.versionString,
            validate: validate,
            submit: submit,
            publish: publish,
            dryRun: false,
            mode: "applied",
            steps: steps
        )

        return try ReleaseFlowCompatibilitySupport.render(
            [report],
            formatter: formatter,
            headers: ["App ID", "Version", "Dry Run"],
            rowMapper: { [$0.appId, $0.version, $0.dryRun ? "yes" : "no"] }
        )
    }
}

private func copyMetadata(from source: URL, to target: URL, fileManager: FileManager) throws {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw ValidationError("Metadata source directory not found at \(source.path).")
    }

    let contents = try fileManager.contentsOfDirectory(
        at: source,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )

    for item in contents {
        let destination = target.appendingPathComponent(item.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey])
        if resourceValues.isDirectory == true {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try copyMetadata(from: item, to: destination, fileManager: fileManager)
        } else {
            try fileManager.copyItem(at: item, to: destination)
        }
    }
}
