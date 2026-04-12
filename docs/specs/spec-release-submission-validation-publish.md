# Spec: release / submit / validate / publish 流程命令

目标：补齐提交发布链路，提供“先检查再预发布再提交/发布”的可复用入口，满足 Skills 中 release-flow 与 submission-health 场景。

## 1. `asc submit`

新增 `submit` 命令族：
- `asc submit preflight`
- `asc submit create`
- `asc submit status`
- `asc submit cancel`

### 1.1 `submit preflight --app APP_ID --version VERSION --platform IOS`
- 行为：在可能时使用 review-submission API 的 readiness 检测；当前可基于：
  - app 是否存在/可提交版本
  - 版本状态是否可提交
  - 版本与构建关联完整性
- 返回：JSON 包含 `eligible`, `blockingIssues`, `warnings`, `versionId`, `platform`, `appId`。
- 表现：无阻断即 `eligible=true`；有阻断返回 `eligible=false`。

### 1.2 `submit create --app APP_ID --version VERSION --build BUILD_ID [--confirm]`
- 现有 `versions submit` 与 `submissions submitVersion` 能力不足以接收 version 字符串，优先做解析：
  - 先用 `AppRepository.getApp` + `VersionRepository.listVersions(appId:)` 解析到 `versionId`；
  - 需要 `--confirm` 或 `--dry-run` 之一；默认需确认。
- 行为：完成关联构建（如已无构建关联则可返回清晰错误）后创建/提交 review submission。
- 返回 ReviewSubmission（含 state/affordance）。

### 1.3 `submit status`
- 支持两种入口：
  - `--id SUBMISSION_ID`：按提交 id 查询
  - `--version-id VERSION_ID`：按版本 id 推导/检索提交
- 返回 submission 当前状态。

### 1.4 `submit cancel --id SUBMISSION_ID --confirm`
- 如 API 支持调用取消 mutation，执行取消。
- 无法取消时返回可解释错误（状态不可取消）。

## 2. `asc validate`

新增 `validate` 命令族：
- `asc validate --app APP_ID --version VERSION --platform IOS`
- `asc validate iap --app APP_ID`
- `asc validate subscriptions --app APP_ID`

### 2.1 app/version 验证
- 基于已有能力（版本/构建/提交资格）与基础元数据规则返回：
  - `ok`, `blockers`, `warnings`, `checks`
- 输出 JSON 时保留字段级详情；table 时压缩为状态列表。

### 2.2 iap / subscriptions 验证
- 新增 `InAppPurchase` 与 `Subscription` 可读性校验：
  - 价格覆盖
  - 可见性/定价计划
  - 可用性
  - 审核关键素材（review screenshots / images）
- 返回命令行友好列表（支持 `--output table|json|markdown`）。

## 3. `asc release`

新增 `release` 命令族：
- `asc release stage`
- `asc release run`

### 3.1 `release stage`
- 目标：做“提交前准备”检查并可选写入 metadata/source：
  - `--app`、`--version`
  - `--metadata-dir` 或 `--copy-metadata-from`
  - `--confirm`（真正落库）
- 默认展示计划，不改状态；`--confirm` 才执行变更。

### 3.2 `release run`
- 目标：全流程执行（可加 `--dry-run`）：
  - 可选 `--validate`
  - 可选 `--submit`
  - 可选 `--publish`（与 `publish` 命令联动）
- 失败快速汇总，支持 `--continue-on-warn`（预留）和 `--stop-on-error`（默认）。

## 4. `asc publish`

新增 `publish` 命令族：
- `asc publish testflight`
- `asc publish appstore`

### 4.1 `publish testflight`
- 输入：`--app APP_ID --ipa ./xxx.ipa --group GROUP_ID [--wait] [--confirm]`
- 行为：通过现有 `builds upload` + `builds add-groups` 做最短路径。
- 若无 `--confirm`，输出执行计划。

### 4.2 `publish appstore`
- 输入：`--app APP_ID --ipa ./xxx.ipa --version VERSION --wait --submit --confirm`
- 行为：
  - 上传
  - 检测/设置目标版本与构建关系
  - 可选 `--submit` 触发 `submit create`

## 测试要求
- 在 `Tests/ASCCommandTests/Commands` 增加：
  - `SubmitPreflightTests`
  - `SubmitCreateTests`
  - `SubmitStatusTests`
  - `SubmitCancelTests`
  - `ValidateAppTests`
  - `ValidateIAPTests`
  - `ValidateSubscriptionsTests`
  - `ReleaseStageTests`
  - `ReleaseRunTests`
  - `PublishTestflightTests`
  - `PublishAppStoreTests`
- 每个测试需覆盖：
  - `--pretty/--output table`
  - `--app/+id+version` 解析边界
  - `--dry-run`/`--confirm` 分支

## 约束与验收
- 若某些检查暂不可用，应返回 `missingCapability`（明确引用缺失能力）而不是静默跳过。
- 与现有 `submissions` 命令保持可共存；不删除现有 `versions submit`。
