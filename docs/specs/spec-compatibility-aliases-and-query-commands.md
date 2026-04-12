# Spec: 兼容别名与查询型命令补齐

目标：补齐 `asc` 现有命令树与 `app-store-connect-cli-skills` 常见调用路径之间的“语义兼容层”，优先保证自动化流程不因命令名差异失败。

## 涉及能力
- `asc apps view`
- `asc apps wall submit`
- `asc versions view`
- `asc builds info`
- `asc builds next-build-number`
- `asc builds add-groups / remove-groups`
- `asc builds test-notes create / update`
- `asc localizations` 的别名兼容（由 `asc version-localizations` 与 `asc app-info-localizations` 兼容）

## 实现范围

### 1) `asc apps view`
- 现状：`AppsCommand` 只有 `list`。
- 实现：新增 `AppsView`（`commandName: "view"`）
- 选项：
  - `--id`（必填）：App ID。
- 行为：调用 `AppRepository.getApp(id:)`。
- 输出：`formatAgentItems([app])`。
- 兼容要求：输出字段与现有 `asc apps list` 一致。

### 2) `asc apps wall submit`
- 现状：目前命令是 `asc app-wall submit`。
- 实现：新增 `AppsWall` namespace 或直接挂在 `AppsCommand` 下 `wall` 分组。
- 路径：
  - `app-wall` 原子能力不变，保留现有 `AppWallSubmit`。
  - `AppsWallSubmit` 仅转调已有逻辑。
- 选项：`--app` / `--link` / `--name` / `--dry-run` / `--confirm` / `--token`。
- 兼容要求：生成的 `--help` 示例与 `app-wall submit` 一致，方便 Skills 直接复用。

### 3) `asc versions view`
- 现状：`VersionsCommand` 只有 `list/create/submit/set-build/check-readiness`。
- 实现：新增 `VersionsView`（`commandName: "view"`）。
- 选项：`--version-id`（必填）。
- 行为：调用 `VersionRepository.getVersion(id:)`。
- 输出：与 `versions list` 的字段/affordance 同步。

### 4) `asc builds info`
- 现状：`BuildsCommand` 只有 `list/next-number/upload/archive/...`。
- 实现：新增 `BuildsInfo`（`commandName: "info"`）。
- 选项：
  - `--build-id`（优先）
  - `--app` + `--latest` + 可选 `--platform`
  - `--app` + `--version` + 可选 `--platform`
- 行为：
  - 有 `build-id` 时：`BuildRepository.getBuild(id:)`。
  - 无 `build-id` 且带 `--app --latest` 时：取 `BuildRepository.listBuilds(appId:platform:version:nil:)` 排序后取首条；
    若带 `--version`，在列表过滤的基础上取首条。
  - 失败时给出明确错误（未找到 build / 参数不完整）。
- 输出：同 `builds list` 的字段 + `appId/buildId` 兼容 affordance。

### 5) `asc builds next-build-number`
- 现状：存在 `next-number`。
- 实现：新增 `commandName: "next-build-number"`，作为 `next-number` 的兼容别名。
- 参数与输出与 `next-number` 一致。

### 6) `asc builds add-groups` / `remove-groups`
- 现状：`add-beta-group/remove-beta-group` 存在。
- 实现：新增 `add-groups/remove-groups` 子命令。
- 参数：
  - `--build-id`
  - `--group`（逗号分隔或重复参数；至少支持技能常见单个值）
  - `--confirm`（对 remove 建议要求）
- 行为：统一映射到现有 `add-beta-groups/remove-beta-groups`。

### 7) `asc builds test-notes create / update`
- 现状：`update-beta-notes` 存在。
- 实现：
  - `builds test-notes create` -> 复用 `beta-build-localizations upsert` 行为
  - `builds test-notes update` -> 与 `create` 行为一致（幂等 update）
- 选项：
  - `--build-id`
  - `--locale`
  - `--whats-new`（或 `--notes` 兼容别名）
- 验证：
  - `notes/whats-new` 至少一个必填。
  - locale 必填。

### 8) `asc localizations` 别名入口
- 现状：无命令 `localizations`，skills 入口大量使用该名前缀。
- 实现：新增 `localizations` 命令及 `list/download/upload` 子命令，按 `--type` 分流。
  - `--type version`（默认）：映射到 `version-localizations`
  - `--type app-info`：映射到 `app-info-localizations`
- 对应行为与参数见 `spec-metadata-localization-migration.md`。

## 约束与优先级
- P0：`apps view`、`apps wall submit`、`versions view`、`builds info`
- P1：兼容别名（`builds next-build-number`、`add-groups/remove-groups`、`test-notes`）
- P2：`asc localizations` 兼容层（与 metadata spec 联动）

## 测试要求
- 使用 `@Testing` 在 `Tests/ASCCommandTests/Commands` 增加：
  - `AppsViewTests`
  - `VersionsViewTests`
  - `BuildsInfoTests`
  - `BuildsNextBuildNumberAliasTests`
  - `BuildsGroupAliasTests`
  - `BuildsTestNotesAliasTests`
- 每个命令需要：
  - parser 参数映射测试
  - 对应 `Mock*Repository` 调用断言
  - JSON 输出字段快照测试（`--pretty`）

## 交付验收
- `asc --help` 下可见所有新兼容命令名。
- 不破坏原有 `app-wall`、`builds update-beta-notes`、`next-number` 行为。
