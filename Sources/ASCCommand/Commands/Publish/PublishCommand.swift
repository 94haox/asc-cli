import ArgumentParser
import Domain
import Foundation

extension BuildUploadPlatform: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(cliArgument: argument)
    }
}

struct PublishCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Compatibility entrypoint for publish flow",
        subcommands: [PublishTestFlight.self, PublishAppStore.self]
    )
}

struct PublishTestFlight: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "testflight",
        abstract: "Publish a build to TestFlight"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "App ID") var app: String
    @Option(name: .long, help: "IPA path") var ipa: String
    @Option(name: .long, help: "Beta group ID") var group: String
    @Option(name: .long, help: "Version string") var version: String?
    @Option(name: .long, help: "Build number") var buildNumber: String?
    @Option(name: .long, help: "Platform") var platform: BuildUploadPlatform?
    @Flag(name: .long, help: "Wait for processing") var wait = false
    @Flag(name: .long, help: "Confirm the publish action") var confirm = false

    func run() async throws {
        print(try await execute())
    }

    func execute() async throws -> String {
        guard FileManager.default.fileExists(atPath: ipa) else {
            throw ValidationError("IPA file not found at \(ipa).")
        }

        if !confirm {
            let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
            let report = PublishTestFlightReport(
                id: "\(app):\(group)",
                appId: app,
                ipa: ipa,
                group: group,
                wait: wait,
                confirmed: false,
                mode: "dry-run",
                actions: [
                    .init(name: "upload", status: "planned", detail: "Upload \(ipa) to App Store Connect"),
                    .init(name: "add-group", status: "planned", detail: "Add build to \(group)")
                ]
            )

            return try ReleaseFlowCompatibilitySupport.render(
                [report],
                formatter: formatter,
                headers: ["App ID", "IPA", "Group"],
                rowMapper: { [$0.appId, $0.ipa, $0.group] }
            )
        }

        return try await execute(
            uploadRepo: try ClientProvider.makeBuildUploadRepository(),
            buildRepo: try ClientProvider.makeBuildRepository(),
            testFlightRepo: try ClientProvider.makeTestFlightRepository()
        )
    }

    func execute(
        uploadRepo: any BuildUploadRepository,
        buildRepo: any BuildRepository,
        testFlightRepo: any TestFlightRepository
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: ipa) else {
            throw ValidationError("IPA file not found at \(ipa).")
        }

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)

        if !confirm {
            let report = PublishTestFlightReport(
                id: "\(app):\(group)",
                appId: app,
                ipa: ipa,
                group: group,
                wait: wait,
                confirmed: false,
                mode: "dry-run",
                actions: [
                    .init(name: "upload", status: "planned", detail: "Upload \(ipa) to App Store Connect"),
                    .init(name: "add-group", status: "planned", detail: "Add build to \(group)")
                ]
            )

            return try ReleaseFlowCompatibilitySupport.render(
                [report],
                formatter: formatter,
                headers: ["App ID", "IPA", "Group"],
                rowMapper: { [$0.appId, $0.ipa, $0.group] }
            )
        }

        guard let version, let buildNumber else {
            throw ValidationError("Provide --version and --build-number when confirming TestFlight publish.")
        }

        let uploadPlatform = platform ?? inferPlatform(forIPAAt: ipa)
        let upload = try await uploadRepo.uploadBuild(
            appId: app,
            version: version,
            buildNumber: buildNumber,
            platform: uploadPlatform,
            fileURL: URL(fileURLWithPath: ipa)
        )

        var actions: [FlowPlanStep] = [
            .init(name: "upload", status: "completed", detail: "Uploaded build \(upload.id) for version \(version)"),
        ]

        if wait {
            let matchingBuild = try await resolveBuild(
                appId: app,
                version: version,
                buildNumber: buildNumber,
                platform: uploadPlatform,
                buildRepo: buildRepo
            )
            guard let matchingBuild else {
                throw ValidationError("Uploaded build is still processing.")
            }
            actions.append(.init(name: "resolve-build", status: "completed", detail: "Resolved build \(matchingBuild.id)"))

            let groups = try await testFlightRepo.listBetaGroups(appId: app, limit: nil).data
            guard groups.contains(where: { $0.id == group }) else {
                throw ValidationError("Beta group \(group) was not found for app \(app).")
            }
            try await buildRepo.addBetaGroups(buildId: matchingBuild.id, betaGroupIds: [group])
            actions.append(.init(name: "add-group", status: "completed", detail: "Added build \(matchingBuild.id) to beta group \(group)"))
        } else {
            actions.append(.init(name: "resolve-build", status: "pending", detail: "Wait for build processing before attaching to beta group"))
            actions.append(.init(name: "add-group", status: "pending", detail: "Beta group attachment will happen after build processing"))
        }

        let report = PublishTestFlightReport(
            id: "\(app):\(group)",
            appId: app,
            ipa: ipa,
            group: group,
            wait: wait,
            confirmed: true,
            mode: "applied",
            actions: actions
        )

        return try ReleaseFlowCompatibilitySupport.render(
            [report],
            formatter: formatter,
            headers: ["App ID", "IPA", "Group"],
            rowMapper: { [$0.appId, $0.ipa, $0.group] }
        )
    }
}

struct PublishAppStore: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appstore",
        abstract: "Publish a build to the App Store"
    )

    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "App ID") var app: String
    @Option(name: .long, help: "IPA path") var ipa: String
    @Option(name: .long, help: "Version string") var version: String
    @Option(name: .long, help: "Build number") var buildNumber: String?
    @Option(name: .long, help: "Platform") var platform: BuildUploadPlatform?
    @Flag(name: .long, help: "Wait for processing") var wait = false
    @Flag(name: .long, help: "Submit the version for review after upload") var submit = false
    @Flag(name: .long, help: "Confirm the publish action") var confirm = false

    func run() async throws {
        print(try await execute())
    }

    func execute() async throws -> String {
        guard FileManager.default.fileExists(atPath: ipa) else {
            throw ValidationError("IPA file not found at \(ipa).")
        }

        if !confirm {
            let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)
            let report = PublishAppStoreReport(
                id: "\(app):\(version)",
                appId: app,
                ipa: ipa,
                version: version,
                wait: wait,
                submit: submit,
                confirmed: false,
                mode: "dry-run",
                actions: [
                    .init(name: "upload", status: "planned", detail: "Upload \(ipa) to App Store Connect"),
                    .init(name: "link-version", status: "planned", detail: "Associate upload with version \(version)"),
                    .init(name: "submit", status: submit ? "planned" : "skipped", detail: submit ? "Submit the version after upload" : "Submission not requested")
                ]
            )

            return try ReleaseFlowCompatibilitySupport.render(
                [report],
                formatter: formatter,
                headers: ["App ID", "IPA", "Version"],
                rowMapper: { [$0.appId, $0.ipa, $0.version] }
            )
        }

        return try await execute(
            uploadRepo: try ClientProvider.makeBuildUploadRepository(),
            buildRepo: try ClientProvider.makeBuildRepository(),
            versionRepo: try ClientProvider.makeVersionRepository(),
            submissionRepo: try ClientProvider.makeSubmissionRepository()
        )
    }

    func execute(
        uploadRepo: any BuildUploadRepository,
        buildRepo: any BuildRepository,
        versionRepo: any VersionRepository,
        submissionRepo: any SubmissionRepository
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: ipa) else {
            throw ValidationError("IPA file not found at \(ipa).")
        }

        let formatter = OutputFormatter(format: globals.outputFormat, pretty: globals.pretty)

        if !confirm {
            let report = PublishAppStoreReport(
                id: "\(app):\(version)",
                appId: app,
                ipa: ipa,
                version: version,
                wait: wait,
                submit: submit,
                confirmed: false,
                mode: "dry-run",
                actions: [
                    .init(name: "upload", status: "planned", detail: "Upload \(ipa) to App Store Connect"),
                    .init(name: "link-version", status: "planned", detail: "Associate upload with version \(version)"),
                    .init(name: "submit", status: submit ? "planned" : "skipped", detail: submit ? "Submit the version after upload" : "Submission not requested")
                ]
            )

            return try ReleaseFlowCompatibilitySupport.render(
                [report],
                formatter: formatter,
                headers: ["App ID", "IPA", "Version"],
                rowMapper: { [$0.appId, $0.ipa, $0.version] }
            )
        }

        guard let buildNumber else {
            throw ValidationError("Provide --build-number when confirming App Store publish.")
        }

        let uploadPlatform = platform ?? inferPlatform(forIPAAt: ipa)
        let upload = try await uploadRepo.uploadBuild(
            appId: app,
            version: version,
            buildNumber: buildNumber,
            platform: uploadPlatform,
            fileURL: URL(fileURLWithPath: ipa)
        )

        var actions: [FlowPlanStep] = [
            .init(name: "upload", status: "completed", detail: "Uploaded build \(upload.id) for version \(version)")
        ]

        var matchedVersion: AppStoreVersion?
        var resolvedBuild: Build?

        if wait {
            resolvedBuild = try await resolveBuild(
                appId: app,
                version: version,
                buildNumber: buildNumber,
                platform: uploadPlatform,
                buildRepo: buildRepo
            )
            guard let resolvedBuild else {
                throw ValidationError("Uploaded build is still processing.")
            }
            actions.append(.init(name: "resolve-build", status: "completed", detail: "Resolved build \(resolvedBuild.id)"))

            let versions = try await versionRepo.listVersions(appId: app)
            matchedVersion = versions.first(where: {
                $0.versionString == version && $0.platform == uploadPlatform.appStorePlatform
            })
            guard let matchedVersion else {
                throw ValidationError("No App Store version \(version) found for app \(app).")
            }

            if matchedVersion.buildId != resolvedBuild.id {
                try await versionRepo.setBuild(versionId: matchedVersion.id, buildId: resolvedBuild.id)
            }
            actions.append(.init(name: "link-version", status: "completed", detail: "Linked build \(resolvedBuild.id) to version \(matchedVersion.id)"))

            if submit {
                let submission = try await submissionRepo.submitVersion(versionId: matchedVersion.id)
                actions.append(.init(name: "submit", status: "completed", detail: "Submitted version \(matchedVersion.id) as \(submission.id)"))
            } else {
                actions.append(.init(name: "submit", status: "skipped", detail: "Submission not requested"))
            }
        } else {
            actions.append(.init(name: "resolve-build", status: "pending", detail: "Wait for build processing before linking the version"))
            actions.append(.init(name: "link-version", status: "pending", detail: "Version will be linked after build processing"))
            actions.append(.init(name: "submit", status: submit ? "pending" : "skipped", detail: submit ? "Submission will happen after build processing" : "Submission not requested"))
        }

        let report = PublishAppStoreReport(
            id: "\(app):\(version)",
            appId: app,
            ipa: ipa,
            version: version,
            wait: wait,
            submit: submit,
            confirmed: true,
            mode: "applied",
            actions: actions
        )

        return try ReleaseFlowCompatibilitySupport.render(
            [report],
            formatter: formatter,
            headers: ["App ID", "IPA", "Version"],
            rowMapper: { [$0.appId, $0.ipa, $0.version] }
        )
    }
}

private extension BuildUploadPlatform {
    var appStorePlatform: AppStorePlatform {
        switch self {
        case .iOS: return .iOS
        case .macOS: return .macOS
        case .tvOS: return .tvOS
        case .visionOS: return .visionOS
        }
    }
}

private func inferPlatform(forIPAAt ipaPath: String) -> BuildUploadPlatform {
    ipaPath.lowercased().hasSuffix(".pkg") ? .macOS : .iOS
}

private func resolveBuild(
    appId: String,
    version: String,
    buildNumber: String,
    platform: BuildUploadPlatform,
    buildRepo: any BuildRepository
) async throws -> Build? {
    let response = try await buildRepo.listBuilds(appId: appId, platform: platform, version: version, limit: nil)
    return response.data.first { build in
        build.buildNumber == buildNumber && build.platform == platform
    }
}
