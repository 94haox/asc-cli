# Versions

Inspect and manage App Store versions for an app. `asc versions view` is the detail entry point for version-level workflows.

## CLI Usage

### `asc versions list`

List versions for an app.

```bash
asc versions list --app-id <id>
asc versions list --app-id <id> --pretty
```

### `asc versions view`

View a single version by Version ID.

```bash
asc versions view --version-id <id>
asc versions view --version-id <id> --pretty
```

**Behavior**

- Returns the version record and its current state.
- Includes affordances for `set-build`, `check-readiness`, `submit`, and review-detail workflows.
- Uses the standard `asc` output formatter.

## Typical Workflow

```bash
# 1. List versions for the app
asc versions list --app-id <id> --pretty

# 2. Inspect the version you want to ship
asc versions view --version-id <id> --pretty

# 3. Link a build, check readiness, and submit
asc versions set-build --version-id <id> --build-id <id>
asc versions check-readiness --version-id <id>
asc versions submit --version-id <id>
```

## Related Commands

- `asc version-review-detail get`
- `asc version-review-detail update`
