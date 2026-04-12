# Spec: web / review / privacy 命令族补齐

目标：补齐 `app-store-connect-cli-skills` 中依赖的 Web-session 兼容面向命令，使 `asc` 在首次可用性、review 绑单与 App Privacy 发布等场景可用；缺少时返回结构化降级信息，不阻塞主流程。

## 一、总体目标

新增顶层 `web` 命令树：

- `web auth`：查询鉴权与权限上下文
- `web apps`：应用级 Web-session 辅助操作（尤其首次可用性）
- `web privacy`：App Privacy 的拉取/预览/写入/发布
- `web review`：首批提交（非 API）场景的辅助手段

其中：
- 能直接映射到已有模型/仓库的动作应执行真实调用；
- 暂未具备能力的动作必须返回 `missingCapability` 与可执行替代建议；
- `asc web` 仍应保留为实验性标识（非核心 production path）。

## 二、命令明细

### 1. `asc web auth`

#### 1.1 `asc web auth capabilities`
- 可选：`--key-id`（覆盖当前 auth key）
- 行为：
  - 解析当前凭据上下文（`asc auth status` 已有上下文 + `AuthProvider`）
  - 输出 key 的角色、权限集合、证书路径、会话来源（file/environment）与可调用能力摘要。
  - 明确区分 `usable` / `missing` / `invalid` 的存储凭据状态，不再把所有失败折叠成 generic failure。
- 输出：
  - `roles`, `permissions`, `source`, `isValid`, `expiresAt`, `hasWebFallbackRoutes`.
- 失败：
  - 无有效凭据时返回结构化状态，而不是只给出 generic failure（不泄露私钥）。

### 2. `asc web apps`

#### 2.1 `asc web apps availability create`
- 参数：
  - `--app`（APP_ID）
  - `--territory`（逗号分隔或可重复）
  - `--available-in-new-territories`（true/false）
- 目标：
  - 为首次可用性缺失场景提供一次性创建能力（skill 中的 fallback 入口）。
- 行为：
  - 在可用时通过 web-session 自动化流程创建 availability；
  - 不支持时返回 `missingCapability("web apps availability create")`，建议退回：
    - `asc pricing availability view --app ...`
    - `asc pricing availability edit --app ...`（仅当 availability 已存在）。
- 安全与幂等：
  - 先做 dry-state 检测（是否已有 availability），重复执行给出 idempotent 响应。

#### 2.2 `asc web apps availability update`（实验）
- 与 `create` 参数保持一致；
- 仅在能力可用且用户显式传入 `--confirm` 时执行；
- 默认返回预览计划。

### 3. `asc web privacy`

#### 3.1 `asc web privacy pull`
- `--app APP_ID`（必填）
- `--out` 输出文件（JSON）
- 行为：
  - 拉取当前可见的 privacy 结构化数据到文件。
  - 若 `--out` 未指定，默认输出 JSON 到 stdout。

#### 3.2 `asc web privacy plan`
- `--app APP_ID`（必填）
- `--file` 现有 privacy 文件
- `--out` 计划文件（可选）
- 行为：
  - 基于输入计算变更预览（新增/更新项、删除项、风险等级）
  - 仅预览，不提交。

#### 3.3 `asc web privacy apply`
- `--app APP_ID`（必填）
- `--file` 输入文件（`pull/plan` 输出）
- `--dry-run`（可选）
- 行为：
  - `--dry-run` 打印待执行更新；
  - 未 dry-run 且带 `--confirm` 时执行草稿写入（未发布）；
  - 空名称、缺失字段和排序问题应以确定性错误或确定性计划输出处理，而不是静默成功。

#### 3.4 `asc web privacy publish`
- `--app APP_ID`（必填）
- `--confirm`（必选）
- 行为：
  - 发布已提交草稿；
- 失败时返回：
  - `missingCapability`（当前缺失）或 `dependencyMissing("web privacy publish requires apply stage")`。

### 4. `asc web review`

#### 4.1 `asc web review subscriptions list`
- `--app APP_ID`
- 用于展示首轮提审订阅绑定状态（技能路径中的 `attach-group/attach` 依赖）。

#### 4.2 `asc web review subscriptions attach-group`
- `--app APP_ID`
- `--group-id GROUP_ID`
- `--confirm`（必需）
- 行为：
  - 将订阅组与 review 入口关联（实验）。

#### 4.3 `asc web review subscriptions attach`
- `--app APP_ID`
- `--subscription-id SUB_ID`
- `--confirm`（必需）
- 行为：
  - 将单订阅绑定到当前 review 入口（实验）。

#### 4.4 `asc web review submissions-list` / `asc web review submissions-cancel`
- 列表与取消当前 review 提交（实验），用于与 `asc submission-health` 工作流对齐。
  - 结果与凭据状态一致：可用凭据、缺失凭据和无效凭据返回不同的结构化结果。

## 三、参数和命令兼容性

- 所有 `web` 子命令都支持：
  - `--output table|json`
  - `--pretty`（仅 json）
  - `--paginate`（列表）
  - `--dry-run`（变更命令）
- 与现有 `app-store-connect-cli-skills` 文档关键调用对齐：
  - `asc web apps availability create`
  - `asc web privacy pull|plan|apply|publish`
  - `asc web review subscriptions list|attach-group|attach`
  - `asc web auth capabilities`

## 四、测试要求

- `Tests/ASCCommandTests/Commands/Web/` 新增：
  - `WebAuthCommandTests.swift`
  - `WebAppsCommandTests.swift`
  - `WebPrivacyCommandTests.swift`
  - `WebReviewCommandTests.swift`
- 每组至少覆盖：
  - 参数必填校验（`--app`、`--confirm`、`--out`、`--file`）
  - 实验路径与 `--dry-run` 互斥/兼容逻辑
  - `missingCapability` 的返回结构
- 增加至少一个端到端快照测试：`asc web auth capabilities --output json --pretty`

## 五、验收标准

- `asc web auth capabilities` 在可用凭据下返回结构化能力清单，并对缺失/无效凭据给出可区分状态。
- `asc web privacy pull/plan/apply` 三段链路可形成不提交、预览、提交的闭环（前提是底层能力可用）。
- `asc web review subscriptions attach-group` 在缺失能力时返回明确降级建议（而不是静默失败）。
