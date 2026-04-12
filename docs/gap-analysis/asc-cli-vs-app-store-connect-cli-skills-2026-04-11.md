# ASC CLI 与 app-store-connect-cli-skills（r/skills）能力对齐差异

基准时间：2026-04-11。
- 当前能力来自 `.build/debug/asc --help` 与各分支 `--help`。
- Skill 侧能力来自 `https://github.com/rudrankriyam/app-store-connect-cli-skills` 里 `skills/*.md` 示例命令与约定命令名（以 `asc ...` 为前缀）。

## 2026-04-12 Update

以下命令面已经在当前分支补齐为兼容入口，并接到真实的仓库调用或文件工作区流程：

- `submit / validate / release / publish`
- `pricing / app-setup / workflow / xcode version`
- `testflight pre-release / feedback / crashes / config`
- `web auth / privacy / review / apps`
- `metadata / migrate`
- `apps view / apps wall submit / versions view`
- `builds info / next-build-number / add-groups / remove-groups / test-notes`
- `localizations list / download / upload`
- `screenshots capture / run / review / frame / sizes / list-frame-devices`
- `signing sync / notarization / profiles download`

截至 2026-04-12，本轮兼容命令里的占位写路径已经清掉：

- `publish appstore / publish testflight` 已经走真实 upload + build 解析/关联/提交流程
- `metadata / migrate / localizations upload` 已经走真实文件工作区 export/import/create/update/validate
- `testflight feedback / crashes` 已经走真实 App Store Connect beta feedback screenshot / crash submissions
- `web apps availability`、`web review submissions-*`、`submit status/cancel`、`pricing availability edit` 已经走真实仓库调用

当前剩余差异不再是“占位层未实现”，而是兼容面与原 skill 示例之间的范围差异，例如：

- `metadata` 目前提供 canonical JSON 工作区，而不是 `keywords diff/apply/sync` 那套细分命令
- `migrate` 目前复用同一套 JSON 工作区导入导出，不是 fastlane 旧文本布局的完整兼容
- `publish *` 的确认路径当前要求显式提供 `--build-number`，避免依赖 IPA 内部元数据探测

## 0. 现状：当前 CLI 命令树摘要

- 顶层入口（存在）：
`apps / init / versions / version-localizations / screenshot-sets / screenshots / app-infos / app-info-localizations / builds / testflight / auth / version / tui / bundle-ids / certificates / devices / profiles / app-preview-sets / app-previews / iap / iap-localizations / subscription-groups / subscriptions / subscription-localizations / subscription-offers / subscription-offer-codes / subscription-offer-code-custom-codes / subscription-offer-code-one-time-codes / iap-offer-codes / iap-offer-code-custom-codes / iap-offer-code-one-time-codes / app-shots / age-rating / app-categories / version-review-detail / plugins / skills / app-wall / users / user-invitations / xcode-cloud / game-center / app-clips / app-clip-experiences / app-clip-experience-localizations / sales-reports / finance-reports / analytics-reports / reviews / review-responses / perf-metrics / diagnostics / diagnostic-logs / beta-review / app-availability / iap-availability / subscription-availability / territories / web-server / iris / simulators`

- 典型可确认子命令（节选）：
  - `apps`: `list`
  - `versions`: `list create submit set-build check-readiness`
  - `builds`: `list next-number upload archive uploads add-beta-group distribution remove-beta-group update-beta-notes`
  - `testflight`: `groups testers`
  - `bundle-ids / certificates / devices / profiles`: `list create delete`（profiles 无 download）
  - `screenshots`: `list upload import`
  - `iap`: `list create submit price-points prices`
  - `subscriptions`: `list create submit`
  - `subscription-groups`: `list create`
  - `subscription-offer*`/`iap-offer*`: `list create update`
  - `app-wall`: `submit request`
  - `app-shots`: `templates gallery-templates themes generate export config`
  - `pricing`/`workflow`/`release`/`submit`/`validate`/`publish`/`web`/`signing`/`notarization`/`xcode version` 顶层全部不存在。

---

## 1. 技能侧关键能力集合（基于 SKILL 文件中的可执行命令）

### A. 应用与版本查询/编辑别名
- `apps view`
- `apps content-rights view|edit`
- `apps info list|edit`
- `apps wall submit`
- `versions view`
- `versions attach-build`

### B. 构建链路
- `builds info`
- `builds next-build-number`
- `builds add-groups / remove-groups`
- `builds test-notes create|update`
- `builds expire / expire-all`

### C. 元数据与迁移
- `localizations list|download|upload`
- `metadata pull|push|validate|keywords diff|apply|sync`
- `migrate export|validate|import`

### D. 发布与校验
- `submit preflight|create|status|cancel`
- `validate`
- `validate iap`
- `validate subscriptions`
- `release stage|run`
- `publish appstore`
- `publish testflight`
- `workflow list|validate|run`

### E. 计价/可用范围/定价树
- `pricing availability view|edit`
- `pricing territories list`
- `subscriptions pricing ...`
- `iap pricing ...`

### F. App 侧设置
- `app-setup info set`
- `app-setup categories set`
- `app-setup availability view|edit`

### G. TestFlight 扩展
- `testflight pre-release create|status`
- `testflight feedback list|export`
- `testflight crashes list|export`
- `testflight config export|import`

### H. Web-session 辅助
- `web auth capabilities`
- `web apps availability create`
- `web privacy pull|plan|apply|publish`
- `web review subscriptions list|attach|attach-group`

### I. 代码签名与安全
- `bundle-ids capabilities list|add`
- `profiles download`
- `signing sync push|pull`
- `notarization submit|list|log|status`

### J. 兼容别名与资源命名层
- `subscription` 命令树下的 `groups/list/create`
- `review` 命令树（`review details-*` / `review submissions-*`）
- `performance diagnostics list|view` 与 `performance download`
- `xcode version view|edit|bump`

### K. 截图
- `screenshots capture`
- `screenshots frame`
- `screenshots list-frame-devices`
- `screenshots sizes`
- `screenshots review-open|review-generate|review-approve`
- `screenshots run`

### L. 其它已覆盖但应补齐的高频能力
- `subscriptions setup`、`iap setup`
- `app-infos localizations` 的归一化提示（目前分拆为 `app-info-localizations`）

---

## 2. 按当前 CLI 缺失命令做差异分组

### 2.1 P0（直接阻断 skill 调用）
1) `apps view`
2) `versions view`
3) `builds info`
4) `builds next-build-number`
5) `apps wall submit`
6) `localizations *`（`localizations` 作为通用入口）
7) `metadata *` + `migrate *`
8) `submit preflight/create/status/cancel`
9) `validate [app|iap|subscriptions]`
10) `release stage/run`
11) `publish testflight/appstore`
12) `workflow list/validate/run`

### 2.2 P1（高频流程中断）
1) `publish`/`release`/`validate` 的前后衔接别名与缺省参数兼容
2) `pricing territories`
3) `notarization` 全量命令
4) `signing sync`
5) `testflight pre-release/*`
6) `testflight feedback` / `crashes`
7) `screenshots capture/frame/list-frame-devices/sizes`
8) `xcode version`
9) `review` 根命令兼容层（与现有 `reviews|review-responses|beta-review` 映射）

### 2.3 P2（能力完整性/语义对齐）
1) `apps content-rights`、`apps info`
2) `builds` 组/测试说明兼容别名
3) `subscriptions` 下分组与本地化的兼容入口（现有独立 `subscription-*`）
4) `performance` 根命令 alias 到 `perf-metrics/diagnostics`
5) `bundle-ids capabilities`, `profiles download`

---

## 3. spec 拆分建议（供 Sub-Agent 并行实现）

| 目标能力簇 | 现状状态 | 对应 spec |
|---|---|---|
| 应用/版本/构建基础别名（`apps view`、`apps wall`、`versions view`、`builds next-build-number`、`add-groups/remove-groups`、`test-notes`、`review` 兼容入口、`performance` 兼容入口、`apps info/content-rights`） | 已有 1 个 spec，但缺口未完整覆盖 | `docs/specs/spec-compatibility-aliases-and-query-commands.md`（增补） |
| 元数据与迁移（`localizations/metadata/migrate`） | 已有 | `docs/specs/spec-metadata-localization-migration.md` |
| 提交流（`submit`/`validate`/`release`/`publish`） | 已有 | `docs/specs/spec-release-submission-validation-publish.md` |
| 价格/可用性/工作流/Xcode 兼容（`pricing`/`app-setup`/`workflow`/`xcode version`） | 已有 | `docs/specs/spec-pricing-availability-workflow.md` |
| TestFlight 扩展（`testflight pre-release/feedback/crashes/config`） | 已有 | `docs/specs/spec-testflight-obs-and-config.md` |
| Web 会话能力（`web privacy`/`web apps`/`web auth`/`web review`） | 已有 | `docs/specs/spec-web-review-privacy.md` |
| Notarization + signing 同步 | 未覆盖 | **新增** `docs/specs/spec-notarization-workflow-signing.md` |
| Screenshots 自动化链路 | 未覆盖 | **新增** `docs/specs/spec-screenshots-automation.md` |

---

## 4. 预期验收口径

1. `asc --help` 与以上 skill 示例命令形成“可解析路径”的一致性；不存在命令名误差导致工作流直接中断。
2. 对每个 P0/P1 命令簇，实现命令级别返回码与字段结构稳定，不因参数差异造成子流程挂起。
3. 兼容层命令返回前，应先做参数归一化：优先复用现有功能（如 `set-build`, `update-beta-notes`, `app-infos`, `app-info-localizations`），未实现路径返回结构化 `missing-capability`，而非空执行。
