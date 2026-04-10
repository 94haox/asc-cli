# Go asc -> Swift asc 命令迁移计划

## 1) 背景与目标

目标：把 `rudrankriyam/App-Store-Connect-CLI` 中 Chordo 依赖的命令契约迁移到 Swift 版 `tddworks/asc-cli`，优先保证 skill 可跑、输出契约稳定、再补齐高级能力。

## 2) 已完成动作

- 已 Fork：`https://github.com/94haox/asc-cli`
- 本地克隆路径：`/tmp/asc_research/asc-cli-swift-fork`
- 已抓取并比对两边 `asc --help` 顶层命令

## 3) 顶层命令差异（摘要）

- Go 顶层命令：73
- Swift 顶层命令：53
- 共同：21
- Go 独有（Swift 缺失）：52

其中对 Chordo + skills 迁移最关键的缺口：

- `submit`
- `release`
- `validate`
- `workflow`
- `metadata`
- `pricing`
- `signing`
- `encryption`
- `migrate`
- `app-setup`
- `notarization`

## 4) 迁移分层策略

### Layer A: 契约兼容层（CLI Surface Compatibility）

先补命令路径与参数，保证 skills 不因命令不存在而失败。

- 先实现与 skill 直接关联的子命令（见 P0/P1）
- 输出 JSON 字段尽量与 Go 行为对齐（至少保持可机器解析）
- 保留 `--output json/table/markdown` 行为一致性

### Layer B: 编排层（Orchestration）

把 Go 里高层流程（release/submit/validate/workflow）转成 Swift 版编排，不强依赖私有 API。

- 优先使用已有 Swift 仓库/Domain/Infrastructure 能力组合
- 必要时新增 `Domain/*` 的 Orchestrator 与 Result DTO

### Layer C: 深能力层（Domain + Infra）

对尚无底层能力的命令（如 notarization、encryption declarations）补仓储与 API 实现。

## 5) 里程碑与优先级

## P0（1-2 周）：让技能可跑通

### 要实现的命令

1. `asc submit`
   - `status`
   - `cancel`
   - （兼容 alias）`preflight` -> 路由到 `validate`

2. `asc release`
   - `stage`
   - `run`

3. `asc validate`
   - root validate
   - `iap`
   - `subscriptions`

4. `asc workflow`
   - `validate`
   - `list`
   - `run`

### 实现建议

- 新目录：`Sources/ASCCommand/Commands/{Submit,Release,Validate,Workflow}`
- 在 `ASC.swift` 注册命令树
- Orchestration 复用已有 `Versions/Builds/Localizations/Reviews` 仓储
- 先保守实现：不引入 web/private session

### 验收

- 命令存在且 `--help` 可用
- 至少 1 个 golden JSON 测试/子命令
- dry-run 与 non-dry-run 路径可区分

## P1（1-2 周）：补 skills 高频缺口

### 要实现的命令

5. `asc metadata`
   - `pull`
   - `apply`
   - `push`
   - `validate`
   - （可后补）`keywords`

6. `asc pricing`
   - `availability view`
   - `availability edit`

7. `asc app-setup`
   - `info set`
   - `categories set`

8. `asc migrate`
   - `import`
   - `export`
   - `validate`

### 验收

- 与 `.asc/workflow.json` 可串联
- 关键参数支持与 Go 命令兼容（至少保持同名 flags）
- 对 skills 中已有示例命令能直接执行（或仅替换极少 flag）

## P2（2+ 周）：深能力与长尾

### 要实现的命令

9. `asc signing`
   - `sync pull`
   - `sync push`

10. `asc encryption`
   - `declarations list/create/assign-builds/exempt-declare`

11. `asc notarization`
   - `submit/status/log/list`

### 风险说明

- notarization / encryption 涉及较强领域逻辑与凭据处理
- 若依赖 private/web 流程，需明确“实验特性”标签

## 6) 代码落点建议（Swift 仓库）

- CLI 入口注册：`Sources/ASCCommand/ASC.swift`
- 命令实现：`Sources/ASCCommand/Commands/<Family>/`
- 协议与模型：`Sources/Domain/...`
- API 适配：`Sources/Infrastructure/...`
- 输出契约：`Sources/ASCCommand/OutputFormatter.swift`

## 7) 迁移执行顺序（建议）

1. 建立 `submit/release/validate/workflow` 命令骨架 + help
2. 打通 `validate`（root/iap/subscriptions）
3. 打通 `release stage/run`（先 dry-run）
4. 打通 `workflow validate/list/run`
5. 再补 `metadata/pricing/app-setup/migrate`
6. 最后补 `signing/encryption/notarization`

## 8) 测试与回归

- 每个新命令至少包含：
  - 参数解析测试
  - JSON 输出 schema 测试
  - 失败路径（缺 app id / 资源不存在 / 权限错误）测试
- 增加兼容测试：抽取 skill 示例命令作为 smoke tests

## 9) Definition of Done

- P0 完成后：Chordo 当前要用的 skills 主流程可跑
- P1 完成后：skills 仓库中高频命令无需大改
- P2 完成后：可逐步将 Go 版 skills 完整迁移到 Swift 版
