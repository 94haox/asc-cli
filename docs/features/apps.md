# Apps

List and inspect App Store Connect apps. `asc apps view` is the detail entry point for app-level workflows.

## CLI Usage

### `asc apps list`

List accessible apps.

```bash
asc apps list
asc apps list --pretty
```

### `asc apps view`

View a single app by App ID.

```bash
asc apps view --app-id <id>
asc apps view --app-id <id> --pretty
```

**Behavior**

- Returns the app record for the given App ID.
- Includes affordances that lead into version workflows.
- Uses the standard `asc` output formatter.

## Typical Workflow

```bash
# 1. List apps you can access
asc apps list --pretty

# 2. Open the app you want to work on
asc apps view --app-id <id> --pretty

# 3. Jump into version workflows
asc versions list --app-id <id>
```

## Related Commands

- `asc versions list`
- `asc versions view`
- `asc versions create`
- `asc versions set-build`
- `asc versions check-readiness`
- `asc versions submit`
