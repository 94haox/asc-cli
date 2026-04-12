# Compatibility Commands

Compatibility commands add the top-level command paths expected by `app-store-connect-cli-skills` without breaking the existing `asc` command tree. The implemented surfaces are mixed: many paths execute real repository-backed workflows, while notarization, signing sync, and profile download are explicit local/workspace-backed compatibility flows. The local paths are intentional and documented as such: notarization persists `.asc/notarization/notarizations.json`, signing sync snapshots local certificates and profiles into `.asc/signing-sync/manifest.json`, and profile download resolves against the local provisioning profile store rather than Team Storage or a Notary service.

Detailed contracts for each compatibility family live in the spec set:

- `docs/specs/spec-compatibility-aliases-and-query-commands.md`
- `docs/specs/spec-release-submission-validation-publish.md`
- `docs/specs/spec-pricing-availability-workflow.md`
- `docs/specs/spec-testflight-obs-and-config.md`
- `docs/specs/spec-web-review-privacy.md`
- `docs/specs/spec-metadata-localization-migration.md`
- `docs/specs/spec-notarization-workflow-signing.md`
- `docs/specs/spec-screenshots-automation.md`

## CLI Usage

### Release and Submission

```bash
asc submit preflight --app <APP_ID> --version <VERSION> --platform ios
asc submit create --app <APP_ID> --version <VERSION> --build <BUILD_ID> --confirm
asc submit status --version-id <VERSION_ID>
asc submit cancel --id <SUBMISSION_ID> --confirm
asc validate app --app <APP_ID> --version <VERSION> --platform ios
asc release stage --app <APP_ID> --version <VERSION> [--metadata-dir ./metadata]
asc release run --app <APP_ID> --version <VERSION> --validate --submit --publish --dry-run
asc publish testflight --app <APP_ID> --ipa ./MyApp.ipa --group <GROUP_ID> --version <VERSION> --build-number <BUILD_NUMBER> --wait --confirm
asc publish appstore --app <APP_ID> --ipa ./MyApp.ipa --version <VERSION> --build-number <BUILD_NUMBER> --wait --submit --confirm
```

### Pricing, Setup, Workflow, and Xcode

```bash
asc pricing availability view --app <APP_ID>
asc pricing availability edit --app <APP_ID> --territory USA --available true
asc pricing territories list
asc pricing iap view --app <APP_ID>
asc pricing subscriptions view --app <APP_ID>
asc app-setup info --app <APP_ID>
asc app-setup categories --app <APP_ID>
asc app-setup availability --app <APP_ID>
asc workflow list [--file .asc/workflow.json]
asc workflow validate [--file .asc/workflow.json]
asc workflow run release version:1.2.3 artifact:ipa --dry-run
asc xcode version list --product-id <PRODUCT_ID>
```

Workflow and metadata compatibility notes:

- `workflow validate` rejects malformed placeholder syntax and returns structured validation errors.
- `workflow run` is planner-oriented; malformed override tokens outside `key:value` fail instead of being ignored.
- `web auth capabilities` distinguishes usable, missing, and invalid stored credentials.
- `metadata` and `migrate` validate the canonical workspace layout and ownership, and they surface unsupported delete semantics explicitly.

### TestFlight, Web, Metadata, and Migrate

```bash
asc testflight pre-release create --app-id <APP_ID> --build-id <BUILD_ID> --group-id <GROUP_ID>
asc testflight feedback list --app-id <APP_ID>
asc testflight crashes list --app-id <APP_ID>
asc testflight config export --app-id <APP_ID> --output ./testflight.json
asc web auth capabilities --pretty
asc web privacy pull --app-id <APP_ID> --out privacy.json
asc web privacy apply --app-id <APP_ID> --file privacy.json --dry-run
asc web review subscriptions list --app-id <APP_ID>
asc metadata pull --app <APP_ID> --version <VERSION> --dir ./metadata
asc metadata push --app <APP_ID> --version <VERSION> --dir ./metadata
asc metadata validate --dir ./metadata
asc migrate export --app <APP_ID> --version <VERSION> --output-dir ./fastlane/metadata
asc migrate import --app <APP_ID> --version <VERSION> --fastlane-dir ./fastlane/metadata
asc migrate validate --fastlane-dir ./fastlane/metadata
```

### Query aliases, screenshot automation, and local compatibility flows

```bash
asc apps view --app-id <APP_ID>
asc versions view --version-id <VERSION_ID>
asc screenshots list-frame-devices
asc screenshots sizes --platform ios
asc screenshots capture --bundle-id com.example.app --plan ./screenshots-plan.json --output-dir ./captured
asc screenshots frame --input ./captured --output-dir ./framed --device iphone-16-pro-max --orientation portrait
asc screenshots review-generate --framed-dir ./framed --output-dir ./review --title "1.2.3 Review"
asc screenshots review-open --output-dir ./review
asc screenshots review-approve --output-dir ./review --all-ready
asc screenshots run --plan ./screenshots-plan.json --capture-output-dir ./captured --framed-output-dir ./framed --review-output-dir ./review --output-dir ./upload --dry-run
asc notarization submit --file ./MyApp.pkg --wait
asc notarization list --limit 10
asc notarization status --id <SUBMISSION_ID>
asc notarization log --id <SUBMISSION_ID>
asc signing sync push --pretty
asc signing sync pull --confirm
asc profiles download --id <PROFILE_ID> --output ./profiles/MyProfile.mobileprovision
```

Additional compatibility notes:

- `apps view` and `versions view` are strict query aliases over the existing app and version detail flows.
- `screenshots capture` and `screenshots run` are planner-oriented helpers that validate the screenshots plan and emit local execution steps; they do not drive simulators directly.
- `screenshots frame`, `review-generate`, `review-open`, and `review-approve` operate on local image and review-bundle directories.
- `signing sync push` defaults to a preview of the workspace manifest change; use `--confirm` when you want an apply-mode snapshot or restore.
- `profiles download` exports the resolved local provisioning profile artifact to `./profiles/` by default.

## Typical Workflow

```bash
asc submit preflight --app "$APP_ID" --version "$VERSION" --platform ios --pretty
asc pricing availability view --app "$APP_ID"
asc pricing subscriptions view --app "$APP_ID"
asc release run --app "$APP_ID" --version "$VERSION" --validate --submit --publish --dry-run --pretty
asc testflight config export --app-id "$APP_ID" --output ./testflight.json --include-testers
asc web privacy pull --app-id "$APP_ID" --out ./privacy.json --pretty
```

## Architecture

```text
ASCCommand compatibility layer
    |
    +-- Reuse existing Domain repositories
    |     - AppRepository / VersionRepository / BuildRepository
    |     - TestFlightRepository / AppAvailabilityRepository
    |     - SubscriptionRepository / InAppPurchaseRepository
    |     - XcodeCloudWorkflowRepository / AppInfoRepository
    |
    +-- Output-only compatibility models
    |     - PreflightReport / ValidateAppReport / ReleaseRunReport
    |     - PricingIAPSummary / PricingSubscriptionSummary
    |     - TestFlightConfigPlan / WebPrivacyApplyPlan
    |
    +-- File-backed compatibility workflows
          - metadata / migrate workspace sync
          - signing sync / notarization / profile download
```

These commands mostly live in `ASCCommand`, with a small number of added Domain and Infrastructure repositories where the compatibility surface now maps to real App Store Connect data such as review submissions, app availability, and TestFlight beta feedback.

## Domain Models

This feature mostly emits output-only models from `ASCCommand`:

- `PreflightReport` / `ValidateAppReport`
  - submission readiness snapshots
- `ReleaseStageReport` / `ReleaseRunReport`
  - dry-run and applied release orchestration results
- `PricingIAPSummary` / `PricingSubscriptionSummary`
  - read-only coverage summaries for skill-driven pricing checks
- `TestFlightFeedbackSubmission` / `TestFlightCrashSubmission`
  - beta feedback screenshot and crash submissions mapped from App Store Connect SDK responses
- `TestFlightConfigSnapshot` / `TestFlightConfigPlan`
  - import/export compatibility payloads
- `WebPrivacySnapshot` / `WebPrivacyApplyPlan`
  - web-session style privacy snapshots and dry-run changes
- `LocalNotarizationRepository`
  - local manifest-backed notarization queue with status progression and logs; not a remote Notary service
- `LocalSigningSyncRepository`
  - local signing snapshot manifest that can push/pull provisioning profiles from the workspace; not team storage sync
- `LocalProfileDownloadRepository`
  - resolves provisioning profiles from the local provisioning profile store; not a remote download flow

The commands reuse existing Domain models for real data loading, including `App`, `AppStoreVersion`, `Build`, `AppAvailability`, `InAppPurchase`, `Subscription`, `BetaGroup`, `BetaTester`, and `XcodeCloudWorkflow`.

## File Map

```text
Sources/ASCCommand/Commands/
├── Submit/
├── Validate/
├── Release/
├── Publish/
├── Pricing/
├── AppSetup/
├── Workflow/
├── Xcode/
├── TestFlight/TestFlightCompatibilityCommands.swift
├── Web/WebCompatibilityCommands.swift
├── Metadata/MetadataCommand.swift
└── Migrate/MigrateCommand.swift

Tests/ASCCommandTests/Commands/
├── Submit/
├── Validate/
├── Release/
├── Publish/
├── Pricing/
├── AppSetup/
├── Workflow/
├── Xcode/
├── TestFlight/
├── Web/
├── Metadata/
└── Migrate/
```

Top-level registration happens in `Sources/ASCCommand/ASC.swift`.

## API Reference

| Compatibility command | Reused repository path |
| --- | --- |
| `submit preflight` / `validate app` | `AppRepository`, `VersionRepository`, `BuildRepository`, `ReviewDetailRepository`, `VersionLocalizationRepository`, `ScreenshotRepository`, `PricingRepository` |
| `submit create` | `VersionRepository.setBuild`, `SubmissionRepository.submitVersion` |
| `submit status` | `VersionRepository.getVersion`, `SubmissionRepository.getSubmission`, `SubmissionRepository.listSubmissions` |
| `submit cancel` | `SubmissionRepository.cancelSubmission` |
| `pricing availability view` / `app-setup availability` | `AppAvailabilityRepository.getAppAvailability` |
| `pricing availability edit` | `AppAvailabilityRepository.getAppAvailability`, `AppAvailabilityRepository.createAvailability`, `AppAvailabilityRepository.updateAvailability` |
| `pricing iap view` | `InAppPurchaseRepository.listInAppPurchases`, `InAppPurchasePriceRepository.listPricePoints`, `InAppPurchaseAvailabilityRepository.getAvailability` |
| `pricing subscriptions view` | `SubscriptionGroupRepository.listSubscriptionGroups`, `SubscriptionRepository.listSubscriptions`, `SubscriptionAvailabilityRepository.getAvailability` |
| `testflight pre-release` | `BuildRepository.getBuild`, `BuildRepository.listBuilds`, `BuildRepository.addBetaGroups` |
| `release stage` / `release run` | local file staging plus `VersionRepository`, `SubmissionRepository`, and existing release validation repositories |
| `publish testflight` / `publish appstore` | `BuildUploadRepository.uploadBuild`, `BuildRepository.listBuilds`, `BuildRepository.addBetaGroups`, `VersionRepository.setBuild`, `SubmissionRepository.submitVersion` |
| `testflight feedback` / `testflight crashes` | `BuildRepository.getBuild`, `BuildRepository.listBuilds`, `TestFlightFeedbackRepository.listScreenshotSubmissions`, `TestFlightFeedbackRepository.listCrashSubmissions` |
| `testflight config` | `TestFlightRepository.listBetaGroups`, `TestFlightRepository.listBetaTesters`, `TestFlightRepository.addBetaTester`, `TestFlightRepository.removeBetaTester` |
| `web apps availability create/update` | `AppAvailabilityRepository.getAppAvailability`, `AppAvailabilityRepository.createAvailability`, `AppAvailabilityRepository.updateAvailability` |
| `web privacy` | `AppInfoRepository.listAppInfos`, `AppInfoRepository.listLocalizations`, `AppInfoRepository.updateLocalization`, `AppInfoRepository.createLocalization` |
| `web review submissions-list/submissions-cancel` | `SubmissionRepository.listSubmissions`, `SubmissionRepository.cancelSubmission` |
| `xcode version list` | `XcodeCloudWorkflowRepository.listWorkflows` |
| `screenshots capture/frame/review/run` | local file planning helpers in `ScreenshotsFileSupport`; no App Store Connect API calls |
| `notarization` | local notarization manifest under `.asc/notarization/notarizations.json` |
| `signing sync` | local signing manifest under `.asc/signing-sync/manifest.json` plus `profiles/` workspace restore |
| `profiles download` | local provisioning profile scan under `profiles/` and `~/Library/MobileDevice/Provisioning Profiles/` |

## Testing

Targeted compatibility coverage:

```bash
swift test --filter 'SubmitCompatibilityTests|ValidateCompatibilityTests|ReleaseCompatibilityTests|PublishCompatibilityTests|PricingAvailabilityTests|PricingTerritoriesTests|PricingIAPTests|PricingSubscriptionTests|AppSetupCommandTests|WorkflowCommandTests|XcodeVersionAliasTests|TestFlightPreReleaseCompatibilityTests|TestFlightFeedbackCompatibilityTests|TestFlightCrashCompatibilityTests|TestFlightConfigCompatibilityTests|WebAuthCompatibilityTests|WebPrivacyCompatibilityTests|WebReviewCompatibilityTests|WebAppsCompatibilityTests|MetadataCommandTests|MigrateCommandTests'
```

This suite verifies 43 compatibility tests across 22 suites.

## Extending

- Extend `metadata` and `migrate` only if you need additional on-disk layouts beyond the canonical JSON workspace.
- Add richer publish-time IPA metadata extraction only if you need to avoid explicit `--build-number` input.
- Promote more compatibility snapshot types into shared Domain models only when they become part of the stable CLI surface.
