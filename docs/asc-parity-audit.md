# ASC Strict Parity Audit

Date: 2026-04-12

## Scope

This audit checks whether the Swift implementation matches `asc` at the level of:

- command surface
- actual execution behavior
- side effects and data source
- error and preview semantics

Status meanings:

- `full`: command exists and the implemented behavior matches the intended real workflow
- `partial`: command exists, but behavior differs in important ways
- `missing`: intended real capability is not implemented
- `docs-gap`: documented command/example exists without a corresponding implementation
- `missing-doc`: implementation exists but is not documented clearly in the current docs

## Overall Conclusion

The Swift implementation is close to parity on the main resource tree, but it is not at strict 100% parity yet.

- Mainline resource commands are mostly `full`
- The P0-P2 items tracked in this audit are now resolved or explicitly documented as local/workspace-backed behavior
- Remaining gaps are concentrated in a smaller set of compatibility surfaces and doc-only examples

## Resolved Since the Initial Audit

- `notarization`, `signing sync`, and `profiles download`
  - documented as explicit local/workspace-backed compatibility flows rather than remote App Store Notary or team storage semantics
- `workflow validate` / `workflow run`
  - malformed placeholders and malformed override tokens now fail deterministically; `run` is documented as a planner, not an executor
- `testflight pre-release create`
  - the dead `--token` path is no longer documented, and version/build selection is deterministic
- `web auth capabilities`
  - stored credential states are reported as usable, missing, or invalid instead of collapsing everything into a generic success/failure
- `metadata` / `migrate`
  - canonical workspace layout and ownership are enforced, and unsupported delete semantics are surfaced explicitly
- docs alignment
  - `apps view` and `versions view` are documented alongside the existing command tree

## Full Parity

The following groups are broadly aligned and backed by real command implementations plus tests:

- `apps`, `versions`, `version-review-detail`
- `builds`, `build uploads`, build beta-group operations, beta notes
- `testflight` group/tester management
- `beta-review`
- `iap`, `subscriptions`, offer codes, availability, territories
- `reports`
- `code-signing` core resources: bundle IDs, certificates, devices, profiles
- `simulators list|boot|shutdown`
- `app-infos`, `app-categories`, `app-info-localizations`, `age-rating get|update`
- `app-shots` implemented paths: templates, gallery-templates, themes, generate, config
- `app-preview-sets`, `app-previews`
- `reviews`, `review-responses`
- `game-center`
- documented `app-clips` list/create/delete paths
- `iris`
- `perf-metrics`, `diagnostics`, `diagnostic-logs`
- compatibility commands: `submit *`, `pricing *`, `app-setup info`, `app-setup availability`, `xcode version list`, `workflow list`, `metadata pull`, `migrate export`

Key evidence:

- `Sources/ASCCommand/Commands/`
- `Tests/ASCCommandTests/Commands/`
- `docs/features/compatibility-commands.md`

## Partial Parity

### Release and publish

- `release stage`
  - Mostly local compatibility orchestration; not a full remote publish flow
- `release run`
  - Mixed semantics: validation/submission are close to real behavior, publish remains compatibility-oriented
- `publish testflight`
  - Real execution is gated by `--confirm`
- `publish appstore`
  - Real execution is gated by `--confirm`

### Workflow and app setup

- `workflow validate`
  - resolved: validation now rejects malformed placeholders and returns parseable failures
- `workflow run`
  - resolved: planner-only behavior is explicit, and malformed `key:value` overrides fail instead of being ignored
- `app-setup categories`
  - Read path is real
  - Write path is also real, which differs from the earlier compatibility-only expectation in docs/spec wording

### TestFlight compatibility

- `testflight pre-release create`
  - resolved: the dead `--token` path has been removed from the documented surface, and version/build selection is deterministic
- `testflight feedback list`
  - Real aggregation exists
  - Filtering, visibility semantics, and edge-case coverage are incomplete
- `testflight crashes list`
  - Real aggregation exists
  - Date filtering and nil-date handling are not fully aligned
- `testflight config export`
  - Real export exists
  - Behavior is a JSON snapshot, not a fuller config DSL

### Web compatibility

- `web auth capabilities`
  - resolved: credential states are now structured as usable / missing / invalid
- `web privacy pull`
  - Real fetch exists, but output/error behavior is still light
- `web privacy apply`
  - Real apply path exists
  - Confirm/dry-run behavior is present, but creation/update coverage is incomplete
  - Empty-name fallback may produce backend validation failures
- `web review submissions-list`
  - Real list path exists
  - Edge-case coverage is incomplete
- `web review submissions-cancel`
  - Real cancel path exists
  - Open-submission selection rules are present, but test coverage is thin
- `web apps availability create`
  - Real create/update fallback logic exists
  - Preview and edge-case behavior still needs tightening
- `web apps availability update`
  - Confirm/preview semantics exist
  - Some territory/error cases are not fully covered

### Metadata and migrate

- `metadata push`
  - resolved: create/update behavior now validates canonical workspace layout and ownership; unsupported deletes are surfaced explicitly
- `metadata validate`
  - resolved: canonical workspace layout, ownership, and malformed JSON are enforced
- `migrate import`
  - resolved: same strict workspace validation and explicit delete semantics as `metadata push`
- `migrate validate`
  - resolved: strict workspace and ownership validation

### Notarization and signing-like flows

- `notarization status`
  - Reads local simulated state
- `notarization log`
  - Reads local simulated state
- `signing sync push`
  - Local snapshot only, not remote team storage sync
- `signing sync pull`
  - Local restore only, not remote sync
- `profiles download`
  - Copies from local profile stores, not a real remote download flow

## Missing Real Capability

- `notarization submit`
  - Missing as a true external notarization submission flow
  - Current implementation is a local simulated queue under `.asc/notarization/notarizations.json`

## Docs Gap

The following commands appear in docs/examples but do not currently have a corresponding real command implementation:

- `asc simulators stream --udid ...`
- `asc app-shots gallery create ...`
- `asc app-clip-experiences update --experience-id ...`
- `asc app-clip-experiences get --experience-id ...`
- `asc app-clip-advanced-experiences`
- `asc app-clip-experience-localizations update --localization-id ...`
- `asc age-rating territories --app-info-id ...`
- `asc subscription-promotional-offers create ...`

## Missing Doc

No P2 implementation-only docs gaps remain for the command surface covered in this pass.

`asc apps view` and `asc versions view` are now documented in the README and feature docs.

## Priority Fix Order

1. Replace local simulation with real semantics where the command name implies a remote workflow
   - `notarization submit`
   - `signing sync push|pull`
   - `profiles download`
2. Remove or implement the doc-only commands
   - especially `simulators stream` and `app-shots gallery create`
3. Tighten compatibility behavior where commands already exist but still diverge
   - `workflow run`
   - `workflow validate`
   - `testflight pre-release create`
   - `web privacy apply`
4. Clean up documentation mismatch
   - `apps view` and `versions view` are now documented

## Reference Files

- `docs/features/compatibility-commands.md`
- `Sources/ASCCommand/Commands/Submit/SubmitCommand.swift`
- `Sources/ASCCommand/Commands/Release/ReleaseCommand.swift`
- `Sources/ASCCommand/Commands/Publish/PublishCommand.swift`
- `Sources/ASCCommand/Commands/Workflow/WorkflowCommand.swift`
- `Sources/ASCCommand/Commands/TestFlight/TestFlightCompatibilityCommands.swift`
- `Sources/ASCCommand/Commands/Web/WebCompatibilityCommands.swift`
- `Sources/ASCCommand/Commands/Metadata/MetadataCompatibilityCommands.swift`
- `Sources/ASCCommand/Commands/Migrate/MigrateCompatibilityCommands.swift`
- `Sources/ASCCommand/Commands/Notarization/LocalNotarizationRepository.swift`
- `Sources/ASCCommand/Commands/Signing/LocalSigningSyncRepository.swift`
- `Sources/ASCCommand/Commands/Profiles/LocalProfileDownloadRepository.swift`
