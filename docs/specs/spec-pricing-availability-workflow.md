# Spec: pricing / availability / workflow / xcode 兼容能力补齐

目标：让 `asc` 能覆盖 Skills 在「定价/可用范围/工作流」路径上的常见调用，以便 release 流水线不因命令不存在而中断。

## 一、能力目标

1. 提供 `pricing` 顶层命令树，覆盖：
   - `pricing availability` 查询和编辑
   - `pricing territories` 查询
   - `subscriptions pricing`
   - `iap pricing`
2. 提供 `app-setup` 兼容入口，用于常见的「分类/可用性」聚合。
3. 提供 `workflow` 入口，支持 `.asc/workflow.json` 文件化工作流的
   `list / validate / run`。
4. 提供 `xcode version` 查询命令别名，映射到现有 `xcode-cloud` 能力。

## 二、命令明细

### 1. `pricing`

#### 1.1 `pricing availability view`
- 参数：
  - `--app APP_ID`（必填）
- 行为：
  - 优先复用 `app-availability get`，将 `app-id` 注入并返回同一模型
- 输出：
  - 使用现有 `OutputFormatter`，支持 `--output`/`--pretty`
- 约束：
  - `app-id` 为空时报 `ValidationError`

#### 1.2 `pricing availability edit`
- 参数：
  - `--app APP_ID`（必填）
  - `--territory <code>`（可重复）
  - `--available true|false`
  - `--available-in-new-territories true|false`
- 行为：
  - 若当前实现缺少写入 API：返回 `missingCapability` 风格错误（`notImplemented` + 当前命令名）
  - 未来可接入 `AppStoreConnect` PATCH；先实现 `--dry-run` 和确认文案（用于可逆性）

#### 1.3 `pricing territories list`
- 无参数。直接调用 `territories list`。
- 约定：输出顺序按 ISO 代码升序（或 API 原顺序，若不稳定则排序）。

### 2. `pricing iap` / `pricing subscriptions`

#### 2.1 `pricing iap view`
- 参数：
  - `--app APP_ID`（必填）
- 行为：
  - 先复用 `iap list --app-id APP_ID --output json`（内部仓库已有 iap 查询）
  - 汇总每个 IAP 的价格状态（只读字段）
- 输出示例字段：
  - `appId / iapId / name / hasPrice / hasTerritoryCoverage / pricingStatus`

#### 2.2 `pricing subscriptions view`
- 参数：
  - `--app APP_ID`（必填）
- 行为：
  - 先复用 `subscriptions list --app-id APP_ID --output json`
  - 汇总订阅价格覆盖/可用性（只读字段）

### 3. `app-setup`

#### 3.1 `app-setup info`
- `--app APP_ID`
- 输出 app 信息：
  - `appId / appName / bundleId / sku / primaryLocale`

#### 3.2 `app-setup categories`
- `--app APP_ID`（只读）
- 复用 `apps info list` + `app-categories list`
- 若提供 `--edit` 参数（实验）：返回 missingCapability 指南

#### 3.3 `app-setup availability`
- `--app APP_ID`
- 内部映射到 `app-availability get --app-id APP_ID`

### 4. `workflow`

#### 4.1 `workflow list`
- 列出 `.asc/workflow.json` 中 `workflows` 所有非私有项（除非 `--all` 显示全部）。

#### 4.2 `workflow validate`
- 参数：
  - `--file <path>`（默认 `.asc/workflow.json`）
- 行为：
  - 校验 JSON/JSONC 语法、结构和占位符写法：`workflows` 必须存在且为字典；`steps` 只能是 string 或 map
  - 任何 malformed placeholder 都返回非 0，并输出可解析的错误数组
- 失败返回非 0，并以 JSON 给出 `valid: false` + `errors`

#### 4.3 `workflow run <name> [key:value ...]`
- 参数：
  - `--file`、`--dry-run`（可选）
- 解析 workflow 文件并生成执行计划，不执行外部 shell 步骤
- `key:value` 覆盖参数必须符合语法；格式错误时直接失败，不会静默忽略
- `run` 输出：
  - `status`、`stepsExecuted`、`failedStep`、`output`（或 `planned`）

### 5. `xcode version`

#### 5.1 `xcode version list`
- `--product-id` 可选
- 复用 `xcode-cloud workflows list --product-id`
- 若未传 product-id 时：
  - 输出提示并不强制报错（允许空结果）或返回最近一条错误提示

## 五、实现要求

- 新命令应默认作为兼容层，不破坏既有命令行为。
- `App`/`Workflow` 模型输出以现有 `OutputFormatter.formatAgentItems` 为主。
- 所有新命令支持 `--output` 与 `--pretty`，并覆盖表格输出。
- 涉及“写入意图但未实现”时必须返回结构化错误，不允许静默成功空操作。

## 六、测试要求

- 在 `Tests/ASCCommandTests/Commands` 新增：
  - `PricingAvailabilityTests`（view/edit 参数边界+repository 调用+输出）
  - `PricingTerritoriesTests`
  - `PricingSubscriptionsTests`
  - `AppSetupCommandTests`
  - `WorkflowListValidateRunTests`
  - `XcodeVersionAliasTests`
- Domain/Infrastructure 测试优先补齐：
  - `workflow` 配置解析器（新增时）需至少 3 条红黄绿用例；
  - `app-setup` 兼容映射器的参数归一化用例（若新增中间服务）

## 七、验收标准

- `asc pricing availability view --app <id>` 不再失败找不到命令。
- `asc workflow validate` 在 `workflow` 文件错误或占位符格式错误时返回可解析的错误数组。
- `asc workflow run` 明确是计划生成器而不是 shell 执行器，且会拒绝格式错误的 override。
- `asc xcode version` 可以发现/列出已有 xcode-cloud 工作流。
