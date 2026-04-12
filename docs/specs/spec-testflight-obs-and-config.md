# Spec: testflight 观测/配置补齐

目标：补齐 Skills 在 TestFlight 场景常见但缺失的命令入口，保证 `testflight` 分发、预发布、反馈、crash、导入导出配置不阻断。

## 一、能力目标

1. `testflight pre-release`：以版本/构建为目标触发预发布分发流程。
2. `testflight feedback`：读取并导出反馈（测试者意见/备注）。
3. `testflight crashes`：读取 crash 相关信息。
4. `testflight config`：一键导入/导出分发配置（包含组、构建、测试者范围）

## 二、命令明细

### 1. `testflight pre-release`

#### 1.1 `testflight pre-release create`
- 参数：
  - `--app APP_ID`
  - `--build-id BUILD_ID` 或 `--version VERSION`
  - `--group-id GROUP_ID`（可重复）
- 行为：
  - 复用 `builds list` 查 `BUILD_ID`（若仅有 `--version`，按版本与构建顺序确定性选择最新构建）
  - 依次执行：`builds add-groups` + `builds expire`（若仓库已有相应能力）
  - 若无法执行到失效处理，返回可读错误并给出下一步命令
  - 兼容层不再保留死参数 `--token`

#### 1.2 `testflight pre-release status`
- `--build-id` 或 `--app + --version`
- 读取构建的 TestFlight 处理状态并返回：
  - `processingState / expired / upload` 等字段
  - 输出与构建选择顺序保持一致，避免相同版本下的非确定性

### 2. `testflight feedback`

#### 2.1 `testflight feedback list`
- `--app APP_ID`
- `--build-id BUILD_ID`（可选）
- `--limit`
- 行为：
  - 先复用 `testflight groups list`/`builds list` 获取构建集合；
  - 为每条构建输出可见性与测试者提交反馈计数，结果排序保持确定性。

#### 2.2 `testflight feedback export`
- `--app APP_ID`
- `--output ./testflight-feedback.json`
- 输出 JSON 文件。

### 3. `testflight crashes`

#### 3.1 `testflight crashes list`
- `--app APP_ID`
- `--build-id BUILD_ID`（可选）
- `--since <iso8601>`（可选）
- 行为：
  - 若仓库层无原生 Crash API：返回 `missingCapability` + 建议手动路径。
  - 结果排序保持确定性，日期过滤不再依赖隐式空值分支。

#### 3.2 `testflight crashes export`
- `--app APP_ID`
- `--output ./crashes.json`
- 将 `list` 输出落盘。

### 4. `testflight config`

#### 4.1 `testflight config export`
- `--app APP_ID`
- `--output ./testflight.yaml`
- 选项：
  - `--include-builds`/`--include-testers`
- 行为：
  - 合并 `testflight groups list` + `testflight testers list` + 当前可得 build 信息
  - 生成可复用的 YAML（含 `groups/testers/buildIds`）
  - 输出顺序稳定，便于后续 `import --dry-run` 对比

#### 4.2 `testflight config import`
- `--app APP_ID`
- `--input ./testflight.yaml`
- `--dry-run`
- 行为：
- `--dry-run`：打印将执行的差异，不调用 API
- 非 dry-run：按顺序执行新增/更新群组与测试者关系（已存在记录幂等跳过）

## 三、实现要求

- `testflight` 下新增子命令不影响现有 `groups`/`testers` 命令。
- 输出保持 `table`/`json` 兼容；`--pretty` 保持 CLI 默认 JSON。
- 预发布链路中涉及“可能不完整能力”场景统一返回 `missingCapability`，并给出 fallback 命令。

## 四、测试要求

- 新增测试建议：
  - `Tests/ASCCommandTests/Commands/TestFlight/TestFlightPreReleaseTests.swift`
  - `Tests/ASCCommandTests/Commands/TestFlight/TestFlightFeedbackTests.swift`
  - `Tests/ASCCommandTests/Commands/TestFlight/TestFlightCrashesTests.swift`
  - `Tests/ASCCommandTests/Commands/TestFlight/TestFlightConfigTests.swift`
- 覆盖点：
  - 解析兼容参数（`--app`/`--build-id`/`--version`）
  - mock repo 调用次数
  - `--dry-run` 与实际执行分支

## 五、验收标准

- `asc testflight config export/import` 可读写一致（导出后导入 `--dry-run` 不报错）。
- `asc testflight pre-release create` 能够在 `--build-id + --group-id` 情况下完成最小分发动作。
- 所有新增命令在 `--help` 中出现。
