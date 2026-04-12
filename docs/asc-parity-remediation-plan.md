# ASC Parity Remediation Plan

Date: 2026-04-12

## Goal

Close the strict parity gaps identified in [`docs/asc-parity-audit.md`](/Users/tao.wu/github/asc-cli/docs/asc-parity-audit.md) and make the remaining differences explicit where parity is intentionally not provided.

Strict parity here means:

- command exists
- behavior matches the intended workflow
- side effects match the command name
- preview and execution semantics are explicit
- docs and implementation describe the same surface

## Execution Rules

- Fix semantic gaps before polishing docs
- Prefer real remote behavior over local simulation when the command name implies a remote service
- If a command is intentionally local-only, rename or document it clearly instead of preserving ambiguous behavior
- Do not leave doc-only commands in examples
- Add tests for every behavior change that affects execution, preview, validation, or error handling

## P0

### 1. Replace fake remote notarization with real semantics

Status: completed

Scope:

- `notarization submit`
- `notarization status`
- `notarization log`

Current state:

- The command is documented as a local queue under `.asc/notarization/notarizations.json`
- The help and docs now make the local/workspace-backed semantics explicit instead of implying a remote Notary service

Primary files:

- [ClientProvider.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/ClientProvider.swift)
- [LocalNotarizationRepository.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Notarization/LocalNotarizationRepository.swift)
- [NotarizationSubmit.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Notarization/NotarizationSubmit.swift)
- [NotarizationStatus.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Notarization/NotarizationStatus.swift)
- [NotarizationLog.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Notarization/NotarizationLog.swift)

Done means:

- `submit` is explicitly documented as local simulation
- `status` reads local submission state
- `log` reports local submission log output
- No simulated time-based progression is presented as remote service behavior

Suggested tests:

- successful submit
- submit failure from upstream service
- status polling for in-progress and terminal states
- log retrieval for a completed submission

### 2. Replace local signing sync semantics with real remote semantics or rename the feature

Status: completed

Scope:

- `signing sync push`
- `signing sync pull`

Current state:

- The commands snapshot and restore local files
- Command naming and docs now state that this is a workspace-backed compatibility flow, not remote team-level synchronization

Primary files:

- [LocalSigningSyncRepository.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Signing/LocalSigningSyncRepository.swift)
- [SigningSyncPush.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Signing/SigningSyncPush.swift)
- [SigningSyncPull.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Signing/SigningSyncPull.swift)

Done means:

- The docs no longer imply team storage semantics
- Push/pull remain explicitly local compatibility behavior

Suggested tests:

- dry-run produces no mutation
- confirmed push writes to the intended backend
- pull restores the same materialized profiles/certificates

### 3. Replace local `profiles download` semantics with true download behavior or rename the command

Status: completed

Current state:

- The command copies from local profile stores instead of downloading from a remote source
- The docs now call out that behavior directly

Primary files:

- [ProfilesDownload.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Profiles/ProfilesDownload.swift)
- [LocalProfileDownloadRepository.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Profiles/LocalProfileDownloadRepository.swift)

Done means:

- The current command name is documented as a local profile resolution flow

Suggested tests:

- remote hit path
- missing profile path
- output hashing and size reporting

### 4. Remove doc-only commands or implement them

Status: completed

Commands:

- `asc simulators stream --udid ...`
- `asc app-shots gallery create ...`
- `asc app-clip-experiences update --experience-id ...`
- `asc app-clip-experiences get --experience-id ...`
- `asc app-clip-advanced-experiences`
- `asc app-clip-experience-localizations update --localization-id ...`
- `asc age-rating territories --app-info-id ...`
- `asc subscription-promotional-offers create ...`

Primary files:

- [docs/features/simulators.md](/Users/tao.wu/github/asc-cli/docs/features/simulators.md)
- [docs/features/app-shots.md](/Users/tao.wu/github/asc-cli/docs/features/app-shots.md)
- [docs/features/app-clips.md](/Users/tao.wu/github/asc-cli/docs/features/app-clips.md)
- [docs/features/age-rating.md](/Users/tao.wu/github/asc-cli/docs/features/age-rating.md)
- [docs/features/iap-subscriptions.md](/Users/tao.wu/github/asc-cli/docs/features/iap-subscriptions.md)

Done means:

- Every documented command is implemented and tested, or removed from docs/examples and extension sections

## P1

### 5. Tighten workflow semantics

Status: completed

Scope:

- `workflow validate`
- `workflow run`

Current state:

- Validation now rejects malformed placeholders
- `run` is documented as a planner, not an executor
- malformed override tokens fail deterministically

Primary files:

- [WorkflowCommand.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Workflow/WorkflowCommand.swift)

Done means:

- `validate` enforces placeholder syntax and fails clearly
- `run` is explicitly documented as a plan command
- invalid `key:value` overrides produce deterministic failures

Suggested tests:

- placeholder syntax rejection
- bad override rejection
- real execution path if implemented
- dry-run/plan path if preserved

### 6. Tighten TestFlight compatibility semantics

Status: completed

Scope:

- `testflight pre-release create`
- `testflight feedback list`
- `testflight crashes list`
- `testflight config export`

Current state:

- The dead `--token` path has been removed from the documented surface
- build/version selection and output ordering are deterministic
- remaining edge-case coverage is documented separately in the feature notes

Primary files:

- [TestFlightCompatibilityCommands.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/TestFlight/TestFlightCompatibilityCommands.swift)

Done means:

- dead parameters are removed or implemented
- filtering and export semantics are deterministic and covered
- docs describe actual output shape

Suggested tests:

- build-id vs version selection
- unused parameter removal or execution path
- export with builds and testers
- error handling for missing build/group

### 7. Tighten web compatibility semantics

Status: completed

Scope:

- `web auth capabilities`
- `web privacy pull`
- `web privacy apply`
- `web review submissions-list`
- `web review submissions-cancel`
- `web apps availability create|update`

Current state:

- credential handling now distinguishes usable / missing / invalid stored credentials
- preview/apply semantics are documented as explicit plan or apply flows
- deterministic error and no-op handling is documented for the relevant commands

Primary files:

- [WebCompatibilityCommands.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Web/WebCompatibilityCommands.swift)

Done means:

- invalid/missing credentials produce structured output or explicit failure semantics
- `confirm` and `dry-run` behavior is fully specified and tested
- no-op and fallback-create behavior is deterministic

Suggested tests:

- invalid credential path
- create vs update path
- dry-run with no mutation
- missing app info or submission cases

### 8. Strengthen metadata/migrate validation

Status: completed

Scope:

- `metadata push`
- `metadata validate`
- `migrate import`
- `migrate validate`

Current state:

- validation now enforces canonical workspace layout and resource ownership
- delete semantics are unsupported but explicitly surfaced
- malformed JSON fails clearly

Primary files:

- [MetadataCompatibilityCommands.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Metadata/MetadataCompatibilityCommands.swift)
- [MetadataWorkflowSupport.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Metadata/MetadataWorkflowSupport.swift)
- [MetadataFileSupport.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Metadata/MetadataFileSupport.swift)
- [MigrateCompatibilityCommands.swift](/Users/tao.wu/github/asc-cli/Sources/ASCCommand/Commands/Migrate/MigrateCompatibilityCommands.swift)

Done means:

- malformed inputs fail clearly
- validation checks schema and ownership more strongly
- docs state whether delete semantics are intentionally unsupported

Suggested tests:

- invalid JSON file
- orphaned locale file
- mismatched app-info directory
- dry-run plan vs apply behavior

## P2

### 9. Align docs with implemented commands

Status: completed

Scope:

- add `asc apps view`
- add `asc versions view`

Primary files:

- [README.md](/Users/tao.wu/github/asc-cli/README.md)
- relevant feature docs for apps and versions

Done means:

- docs match the current implemented surface
- there are no implementation-only commands in the parity matrix

### 10. Normalize preview and execution terminology across compatibility commands

Status: completed

Current state:

- Commands now describe whether they preview, plan, or execute
- `workflow run` is documented as planner-only
- `web privacy apply` and publish-style commands make `--confirm` semantics explicit

Done means:

- command help and docs clearly describe whether a command previews, executes, or supports both
- output fields make execution state machine visible where needed

Suggested schema additions:

- `executionMode`
- `executionGuard`
- `applied`

## Recommended Delivery Order

1. P0.1 notarization
2. P0.2 signing sync
3. P0.3 profiles download
4. P0.4 doc-only commands
5. P1.5 workflow
6. P1.6 testflight compatibility
7. P1.7 web compatibility
8. P1.8 metadata/migrate validation
9. P2.9 missing docs
10. P2.10 preview/execution terminology cleanup

## Definition of Done

The parity effort is complete for the P0-P2 scope in this plan when all of the following are true:

- no `docs-gap` commands remain for the surfaces covered in P0-P2
- no simulated local behavior is described as a real remote workflow
- preview/apply semantics are explicit in the docs
- strict parity audit contains only intentional `partial` entries, each documented with rationale
- README and feature docs match the implemented command surface
