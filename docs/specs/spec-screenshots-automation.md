# Spec: screenshots automation 命令补齐

目标：补齐 Skills 场景里对截图流水线的入口能力，保证 `asc` 能直接执行“拍摄/分框/查看机型/校验尺寸/审核流程/一键运行”等链路。

## 1. `asc screenshots capture`（缺失入口）

### 1.1 `asc screenshots capture`

- `--bundle-id <id>`（必填）：要测试的 app bundle identifier  
- `--udid <udid>`（可选）：目标模拟器/真机 id；缺省走最近可用设备  
- `--name <scene-name>`（可选）：截图场景名，重复执行时用于目录/批次标识  
- `--plan <path>`（可选）：从 plan json 读取动作序列（默认 `.asc/screenshots.json`）  
- `--output-dir <path>`（默认 `./screenshots/raw`）：输出目录  
- `--app-arguments <args...>`（可选）：传给 app 的额外参数  
- `--wait / --timeout`：对超时类拍摄路径的可选等待参数  

行为：
- 以最小闭环方式实现（若后端能力未落地）：仅做参数归一化与执行计划回显；
- 实际实现可通过底层 `run/xe` 逻辑触发 AXe 任务并落盘。  

返回：
- `--pretty` 输出拍摄计划摘要或执行结果（含 `status`、`captured`）。

## 2. `asc screenshots frame`

### 2.1 `asc screenshots frame`
- `--input <path>`（必填）
- `--output-dir <path>`（默认 `./screenshots/framed`）
- `--device <device-id-or-name>`（必填）
- `--orientation portrait|landscape`
- `--insets <value>`（可选）

行为：
- 将输入截图进行画框，输出目录内落盘；若输入为空列表抛 `ValidationError`。

## 3. `asc screenshots list-frame-devices`

- 无必填参数（输出本命令支持的机型清单）
- 返回 `id/name/family/scale/pixels` 列表。

行为：
- 先尝试读取模拟器配置（本地支持）；缺省时返回固定内置列表，保证无环境依赖情况下命令可跑通。

## 4. `asc screenshots sizes`

- `--platform ios|macos|watchos|tvos`（可选）

行为：
- 输出受支持尺寸集合；支持 `--json/--table` 结构化输出。

## 5. `asc screenshots review-open`

- `--output-dir <path>`（可选，默认 `./screenshots/review`）
- `--server`（可选，启动本地 review 服务）

行为：
- 优先输出 review 页面资源路径；`--server` 时返回访问 URL 与端口信息。

## 6. `asc screenshots review-generate`

- `--framed-dir <path>`（可选，默认 `./screenshots/framed`）
- `--output-dir <path>`（默认 `./screenshots/review`）
- `--title <name>`（可选）

行为：
- 生成 review 清单文件（如 `index.html`）与资源清单，便于人工核验。

## 7. `asc screenshots review-approve`

- `--all-ready`（可选）
- `--all`（可选）
- `--group <group-id>`（可选，逐组）

行为：
- 输出可提交状态；若未达到 `--all-ready` 条件则返回缺失项列表（不强行执行）。

## 8. `asc screenshots run`

- `--plan <path>`（必填，默认 `.asc/screenshots.json`）
- `--udid <udid>`（可选）
- `--output-dir <path>`
- `--capture-output-dir <path>`
- `--framed-output-dir <path>`
- `--review-output-dir <path>`
- `--dry-run`

行为：
- `run` 串起 `capture -> (optional)frame -> review-generate -> upload` 的流水线；
- `--dry-run` 仅输出命令顺序与参数映射，不执行任何 I/O 或 API。

## 9. `asc screenshots upload`（已存在）行为增强（建议）
- 增加 `--source-dir <dir>`（与现有 `--file` 并存）
- 若 `--source-dir` 提供：批量上传目录下支持的图片；
- 返回 `uploaded` 数量与失败项列表。

## 10. 错误与兼容策略

- 无对应底层能力时返回结构化提示，不返回空成功。
- 常用错误字段建议：  
  - `code`: `missingCapability` / `validationError`  
  - `command`: 当前路径  
  - `nextHint`: 可替代命令（如 `asc screenshots list`、`asc screenshots frame`）
- plan 文件解析失败时返回：
  - 文件路径
  - 解析位置
  - 建议修改示例

## 11. 依赖测试

- `Tests/ASCCommandTests/Commands/Screenshots/*`
  - `ScreenshotsCaptureCommandTests.swift`
  - `ScreenshotsFrameCommandTests.swift`
  - `ScreenshotsListFrameDevicesTests.swift`
  - `ScreenshotsSizesTests.swift`
  - `ScreenshotsReviewFlowTests.swift`
- 至少覆盖：
  - 参数解析（`--dry-run`/`--plan`/路径）
  - `--output`/`--pretty` 切换
  - 回退/降级分支（缺少底层能力时不崩溃，给出明确提示）

## 12. 交付标准

- `asc screenshots --help` 出现上面的命令；
- `asc screenshots frame` / `list-frame-devices` / `sizes` 可离线无网络输出；
- 关键路径可执行 `--dry-run`；
- 错误信息结构固定，方便 skill 自动重试或切换替代方案。
