import Foundation
import ArgumentParser
import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct WebAuthCompatibilityTests {

    @Test func `auth capabilities returns structured status from stored credentials`() async throws {
        let storage = MockAuthStorage()
        given(storage).load(name: .any).willReturn(
            AuthCredentials(keyID: "KEY123", issuerID: "ISSUER456", privateKeyPEM: "-----BEGIN PRIVATE KEY-----")
        )
        given(storage).loadAll().willReturn([
            ConnectAccount(name: "primary", keyID: "KEY123", issuerID: "ISSUER456", isActive: true, vendorNumber: "V-1"),
        ])

        let cmd = try WebAuthCapabilities.parse(["--pretty"])
        let output = try await cmd.execute(storage: storage, envProvider: MockAuthProvider())

        #expect(output.contains("\"isValid\" : true"))
        #expect(output.contains("\"source\" : \"file\""))
        #expect(output.contains("\"hasWebFallbackRoutes\" : true"))
    }

    @Test func `auth capabilities reports missing state when auth providers fail`() async throws {
        let storage = MockAuthStorage()
        let envProvider = MockAuthProvider()
        given(storage).load(name: .value(nil)).willReturn(nil)
        given(envProvider).resolve().willThrow(AuthError.missingPrivateKey)

        let cmd = try WebAuthCapabilities.parse(["--pretty"])
        let output = try await cmd.execute(storage: storage, envProvider: envProvider)

        #expect(output.contains("\"state\" : \"missing\""))
        #expect(output.contains("\"isValid\" : false"))
        #expect(output.contains("\"source\" : \"environment\""))
        #expect(output.contains("\"reason\" : \"missingPrivateKey\""))
        #expect(output.contains("\"hasWebFallbackRoutes\" : false"))
        #expect(!output.contains("appsAvailabilityCreate"))
        #expect(!output.contains("privacyPull"))
    }

    @Test func `auth capabilities reports invalid state for malformed stored credentials`() async throws {
        let storage = MockAuthStorage()
        let envProvider = MockAuthProvider()
        given(storage).load(name: .value(nil)).willReturn(
            AuthCredentials(keyID: "", issuerID: "ISSUER456", privateKeyPEM: "-----BEGIN PRIVATE KEY-----")
        )
        given(storage).loadAll().willReturn([
            ConnectAccount(name: "primary", keyID: "", issuerID: "ISSUER456", isActive: true, vendorNumber: nil),
        ])

        let cmd = try WebAuthCapabilities.parse(["--pretty"])
        let output = try await cmd.execute(storage: storage, envProvider: envProvider)

        #expect(output.contains("\"state\" : \"invalid\""))
        #expect(output.contains("\"isValid\" : false"))
        #expect(output.contains("\"source\" : \"file\""))
        #expect(output.contains("\"name\" : \"primary\""))
    }
}

@Suite
struct WebPrivacyCompatibilityTests {

    @Test func `privacy pull writes a snapshot file`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-web-privacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputPath = tempDir.appendingPathComponent("privacy.json").path

        let appInfoRepo = MockAppInfoRepository()
        given(appInfoRepo).listAppInfos(appId: .any).willReturn([
            AppInfo(id: "info-1", appId: "app-1", primaryCategoryId: "6014"),
        ])
        given(appInfoRepo).listLocalizations(appInfoId: .any).willReturn([
            AppInfoLocalization(
                id: "loc-1",
                appInfoId: "info-1",
                locale: "en-US",
                name: "My App",
                subtitle: "Subtitle",
                privacyPolicyUrl: "https://example.com/privacy",
                privacyChoicesUrl: "https://example.com/choices",
                privacyPolicyText: "Privacy text"
            )
        ])

        let cmd = try WebPrivacyPull.parse(["--app-id", "app-1", "--out", outputPath, "--pretty"])
        _ = try await cmd.execute(appInfoRepo: appInfoRepo)

        let contents = try String(contentsOfFile: outputPath, encoding: .utf8)
            .replacingOccurrences(of: "\\/", with: "/")
        #expect(contents.contains("privacyPolicyUrl"))
        #expect(contents.contains("https://example.com/privacy"))
    }

    @Test func `privacy apply dry run reports planned changes`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-web-privacy-apply-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let inputPath = tempDir.appendingPathComponent("privacy.json").path
        try """
        {
          "appId": "app-1",
          "appInfoId": "info-1",
          "localizations": [
            {
              "id": "loc-1",
              "locale": "en-US",
              "name": "My App",
              "privacyPolicyUrl": "https://example.com/privacy"
            }
          ]
        }
        """.write(toFile: inputPath, atomically: true, encoding: .utf8)

        let appInfoRepo = MockAppInfoRepository()
        given(appInfoRepo).listAppInfos(appId: .any).willReturn([
            AppInfo(id: "info-1", appId: "app-1"),
        ])
        given(appInfoRepo).listLocalizations(appInfoId: .any).willReturn([])

        let cmd = try WebPrivacyApply.parse(["--app-id", "app-1", "--file", inputPath, "--dry-run", "--pretty"])
        let output = try await cmd.execute(appInfoRepo: appInfoRepo)

        #expect(output.contains("\"dryRun\" : true"))
        #expect(output.contains("\"plannedUpdates\""))
    }

    @Test func `privacy apply refuses to create a localization without a name`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-web-privacy-apply-missing-name-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let inputPath = tempDir.appendingPathComponent("privacy.json").path
        try """
        {
          "appId": "app-1",
          "appInfoId": "info-1",
          "localizations": [
            {
              "locale": "ja-JP",
              "privacyPolicyUrl": "https://example.com/privacy"
            }
          ]
        }
        """.write(toFile: inputPath, atomically: true, encoding: .utf8)

        let appInfoRepo = MockAppInfoRepository()
        given(appInfoRepo).listAppInfos(appId: .any).willReturn([
            AppInfo(id: "info-1", appId: "app-1"),
        ])
        given(appInfoRepo).listLocalizations(appInfoId: .any).willReturn([])

        let cmd = try WebPrivacyApply.parse(["--app-id", "app-1", "--file", inputPath, "--confirm", "--pretty"])

        await #expect(throws: ValidationError.self) {
            _ = try await cmd.execute(appInfoRepo: appInfoRepo)
        }

        verify(appInfoRepo).createLocalization(appInfoId: .any, locale: .any, name: .any).called(.never)
        verify(appInfoRepo).updateLocalization(
            id: .any,
            name: .any,
            subtitle: .any,
            privacyPolicyUrl: .any,
            privacyChoicesUrl: .any,
            privacyPolicyText: .any
        ).called(.never)
    }

    @Test func `privacy apply preview sorts planned locale changes`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asc-web-privacy-apply-sorted-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let inputPath = tempDir.appendingPathComponent("privacy.json").path
        try """
        {
          "appId": "app-1",
          "appInfoId": "info-1",
          "localizations": [
            {
              "locale": "zh-Hans",
              "name": "My App"
            },
            {
              "locale": "de-DE",
              "name": "My App"
            },
            {
              "locale": "fr-FR",
              "name": "Mon App"
            },
            {
              "locale": "en-US",
              "name": "My App"
            }
          ]
        }
        """.write(toFile: inputPath, atomically: true, encoding: .utf8)

        let appInfoRepo = MockAppInfoRepository()
        given(appInfoRepo).listAppInfos(appId: .any).willReturn([
            AppInfo(id: "info-1", appId: "app-1"),
        ])
        given(appInfoRepo).listLocalizations(appInfoId: .any).willReturn([
            AppInfoLocalization(id: "loc-fr", appInfoId: "info-1", locale: "fr-FR", name: "Mon App"),
            AppInfoLocalization(id: "loc-en", appInfoId: "info-1", locale: "en-US", name: "My App"),
        ])

        let cmd = try WebPrivacyApply.parse(["--app-id", "app-1", "--file", inputPath, "--pretty"])
        let output = try await cmd.execute(appInfoRepo: appInfoRepo)

        #expect(output.contains("\"dryRun\" : true"))
        #expect(output.contains("\"toCreate\" : [\n    \"de-DE\",\n    \"zh-Hans\""))
        #expect(output.contains("\"toUpdate\" : [\n    \"en-US\",\n    \"fr-FR\""))
    }

    @Test func `privacy publish confirms current localized privacy data`() async throws {
        let appInfoRepo = MockAppInfoRepository()
        given(appInfoRepo).listAppInfos(appId: .any).willReturn([
            AppInfo(id: "info-1", appId: "app-1"),
        ])
        given(appInfoRepo).listLocalizations(appInfoId: .any).willReturn([
            AppInfoLocalization(
                id: "loc-1",
                appInfoId: "info-1",
                locale: "en-US",
                name: "My App",
                subtitle: "Subtitle",
                privacyPolicyUrl: "https://example.com/privacy"
            )
        ])

        let cmd = try WebPrivacyPublish.parse(["--app-id", "app-1", "--confirm", "--pretty"])
        let output = try await cmd.execute(appInfoRepo: appInfoRepo)

        #expect(output.contains("\"published\" : true"))
        #expect(output.contains("\"publishedLocales\" : ["))
        #expect(output.contains("\"en-US\""))
    }
}

@Suite
struct WebReviewCompatibilityTests {

    @Test func `review subscriptions list returns groups and subscriptions`() async throws {
        let groupRepo = MockSubscriptionGroupRepository()
        given(groupRepo).listSubscriptionGroups(appId: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                SubscriptionGroup(id: "group-1", appId: "app-1", referenceName: "Premium"),
            ])
        )

        let subscriptionRepo = MockSubscriptionRepository()
        given(subscriptionRepo).listSubscriptions(groupId: .any, limit: .any).willReturn(
            PaginatedResponse(data: [
                Subscription(
                    id: "sub-1",
                    groupId: "group-1",
                    name: "Monthly",
                    productId: "com.example.monthly",
                    subscriptionPeriod: .oneMonth,
                    state: .readyToSubmit
                )
            ])
        )

        let cmd = try WebReviewSubscriptionsList.parse(["--app-id", "app-1", "--pretty"])
        let output = try await cmd.execute(subscriptionGroupRepo: groupRepo, subscriptionRepo: subscriptionRepo)

        #expect(output.contains("\"group-1\""))
        #expect(output.contains("\"sub-1\""))
        #expect(output.contains("\"readyToSubmit\""))
    }

    @Test func `review attach group submits ready subscriptions`() async throws {
        let subscriptionRepo = MockSubscriptionRepository()
        let submissionRepo = MockSubscriptionSubmissionRepository()

        given(subscriptionRepo).listSubscriptions(groupId: .value("group-1"), limit: .any).willReturn(
            PaginatedResponse(data: [
                Subscription(
                    id: "sub-1",
                    groupId: "group-1",
                    name: "Monthly",
                    productId: "com.example.monthly",
                    subscriptionPeriod: .oneMonth,
                    state: .readyToSubmit
                ),
                Subscription(
                    id: "sub-2",
                    groupId: "group-1",
                    name: "Yearly",
                    productId: "com.example.yearly",
                    subscriptionPeriod: .oneYear,
                    state: .approved
                ),
            ])
        )
        given(submissionRepo).submitSubscription(subscriptionId: .value("sub-1")).willReturn(
            SubscriptionSubmission(id: "submission-1", subscriptionId: "sub-1")
        )

        let cmd = try WebReviewSubscriptionsAttachGroup.parse([
            "--app-id", "app-1",
            "--group-id", "group-1",
            "--confirm",
            "--pretty",
        ])

        let output = try await cmd.execute(subscriptionRepo: subscriptionRepo, submissionRepo: submissionRepo)
        #expect(output.contains("\"submittedSubscriptionIds\" : ["))
        #expect(output.contains("\"sub-1\""))
        #expect(output.contains("\"skippedSubscriptionIds\" : ["))
        #expect(output.contains("\"sub-2\""))
    }

    @Test func `review attach group submits subscriptions in deterministic id order`() async throws {
        let subscriptionRepo = MockSubscriptionRepository()
        let submissionRepo = MockSubscriptionSubmissionRepository()

        given(subscriptionRepo).listSubscriptions(groupId: .value("group-1"), limit: .any).willReturn(
            PaginatedResponse(data: [
                Subscription(
                    id: "sub-3",
                    groupId: "group-1",
                    name: "Quarterly",
                    productId: "com.example.quarterly",
                    subscriptionPeriod: .threeMonths,
                    state: .readyToSubmit
                ),
                Subscription(
                    id: "sub-1",
                    groupId: "group-1",
                    name: "Monthly",
                    productId: "com.example.monthly",
                    subscriptionPeriod: .oneMonth,
                    state: .readyToSubmit
                ),
                Subscription(
                    id: "sub-2",
                    groupId: "group-1",
                    name: "Yearly",
                    productId: "com.example.yearly",
                    subscriptionPeriod: .oneYear,
                    state: .approved
                ),
            ])
        )
        given(submissionRepo).submitSubscription(subscriptionId: .value("sub-1")).willReturn(
            SubscriptionSubmission(id: "submission-1", subscriptionId: "sub-1")
        )
        given(submissionRepo).submitSubscription(subscriptionId: .value("sub-3")).willReturn(
            SubscriptionSubmission(id: "submission-3", subscriptionId: "sub-3")
        )

        let cmd = try WebReviewSubscriptionsAttachGroup.parse([
            "--app-id", "app-1",
            "--group-id", "group-1",
            "--confirm",
            "--pretty",
        ])

        let output = try await cmd.execute(subscriptionRepo: subscriptionRepo, submissionRepo: submissionRepo)

        #expect(output.contains("\"submittedSubscriptionIds\" : [\n    \"sub-1\",\n    \"sub-3\""))
        #expect(output.contains("\"skippedSubscriptionIds\" : [\n    \"sub-2\""))
    }

    @Test func `review attach submits the selected subscription`() async throws {
        let submissionRepo = MockSubscriptionSubmissionRepository()
        given(submissionRepo).submitSubscription(subscriptionId: .value("sub-9")).willReturn(
            SubscriptionSubmission(id: "submission-9", subscriptionId: "sub-9")
        )

        let cmd = try WebReviewSubscriptionsAttach.parse([
            "--app-id", "app-1",
            "--subscription-id", "sub-9",
            "--confirm",
            "--pretty",
        ])

        let output = try await cmd.execute(submissionRepo: submissionRepo)
        #expect(output.contains("\"submittedSubscriptionIds\" : ["))
        #expect(output.contains("\"sub-9\""))
    }

    @Test func `review submissions list returns current submissions`() async throws {
        let submissionRepo = MockSubmissionRepository()
        given(submissionRepo).listSubmissions(appId: .value("app-1")).willReturn([
            ReviewSubmission(
                id: "submission-1",
                appId: "app-1",
                appStoreVersionId: "v-1",
                platform: .iOS,
                state: .waitingForReview
            ),
        ])

        let cmd = try WebReviewSubmissionsList.parse(["--app-id", "app-1", "--pretty"])
        let output = try await cmd.execute(submissionRepo: submissionRepo)

        #expect(output.contains("\"submission-1\""))
        #expect(output.contains("\"WAITING_FOR_REVIEW\""))
    }

    @Test func `review submissions cancel cancels current open submission`() async throws {
        let submissionRepo = MockSubmissionRepository()
        given(submissionRepo).listSubmissions(appId: .value("app-1")).willReturn([
            ReviewSubmission(
                id: "submission-1",
                appId: "app-1",
                appStoreVersionId: "v-1",
                platform: .iOS,
                state: .waitingForReview
            ),
        ])
        given(submissionRepo).cancelSubmission(id: .value("submission-1")).willReturn(
            ReviewSubmission(
                id: "submission-1",
                appId: "app-1",
                appStoreVersionId: "v-1",
                platform: .iOS,
                state: .canceling
            )
        )

        let cmd = try WebReviewSubmissionsCancel.parse(["--app-id", "app-1", "--pretty"])
        let output = try await cmd.execute(submissionRepo: submissionRepo)

        #expect(output.contains("\"submission-1\""))
        #expect(output.contains("\"CANCELING\""))
    }
}

@Suite
struct WebAppsCompatibilityTests {

    @Test func `apps availability create creates availability when missing`() async throws {
        let repo = MockAppAvailabilityRepository()
        given(repo).getAppAvailability(appId: .value("app-1")).willThrow(APIError.notFound("missing"))
        given(repo).createAvailability(
            appId: .value("app-1"),
            isAvailableInNewTerritories: .value(true),
            territoryIds: .value(["USA"])
        ).willReturn(
            AppAvailability(
                id: "avail-1",
                appId: "app-1",
                isAvailableInNewTerritories: true,
                territories: [
                    AppTerritoryAvailability(
                        id: "ta-usa",
                        territoryId: "USA",
                        isAvailable: true,
                        releaseDate: nil,
                        isPreOrderEnabled: false,
                        contentStatuses: [.available]
                    ),
                ]
            )
        )

        let cmd = try WebAppsAvailabilityCreate.parse([
            "--app-id", "app-1",
            "--territory", "USA",
            "--available-in-new-territories",
            "--pretty",
        ])
        let output = try await cmd.execute(appAvailabilityRepo: repo)

        #expect(output.contains("\"operation\" : \"created\""))
        #expect(output.contains("\"avail-1\""))
    }

    @Test func `apps availability update applies selected territories`() async throws {
        let repo = MockAppAvailabilityRepository()
        given(repo).getAppAvailability(appId: .value("app-1")).willReturn(
            AppAvailability(
                id: "avail-1",
                appId: "app-1",
                isAvailableInNewTerritories: false,
                territories: [
                    AppTerritoryAvailability(
                        id: "ta-usa",
                        territoryId: "USA",
                        isAvailable: true,
                        releaseDate: nil,
                        isPreOrderEnabled: false,
                        contentStatuses: [.available]
                    ),
                ]
            )
        )
        given(repo).updateAvailability(
            appId: .value("app-1"),
            territoryIds: .value(["CAN"]),
            isAvailable: .value(false)
        ).willReturn(
            AppAvailability(
                id: "avail-1",
                appId: "app-1",
                isAvailableInNewTerritories: false,
                territories: [
                    AppTerritoryAvailability(
                        id: "ta-can",
                        territoryId: "CAN",
                        isAvailable: false,
                        releaseDate: nil,
                        isPreOrderEnabled: false,
                        contentStatuses: [.cannotSellRestrictedRating]
                    ),
                ]
            )
        )

        let cmd = try WebAppsAvailabilityUpdate.parse([
            "--app-id", "app-1",
            "--territory", "CAN",
            "--available", "false",
            "--confirm",
            "--pretty",
        ])
        let output = try await cmd.execute(appAvailabilityRepo: repo)

        #expect(output.contains("\"operation\" : \"updated\""))
        #expect(output.contains("\"CAN\""))
        #expect(output.contains("\"isAvailable\" : false"))
    }

    @Test func `apps availability update preview sorts selected territories`() async throws {
        let repo = MockAppAvailabilityRepository()
        let cmd = try WebAppsAvailabilityUpdate.parse([
            "--app-id", "app-1",
            "--territory", "USA",
            "--territory", "CAN",
            "--pretty",
        ])
        let output = try await cmd.execute(appAvailabilityRepo: repo)

        #expect(output.contains("\"confirmed\" : false"))
        #expect(output.contains("\"territories\" : [\n    \"CAN\",\n    \"USA\""))
        #expect(output.contains("\"nextHint\" : \"Re-run with --confirm to apply.\""))
    }
}
