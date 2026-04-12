# Spec: local notarization / signing sync / profile download semantics

## 目标

记录当前命令树的真实行为，避免把它们误读成远端、团队存储或 Notary API 能力。

## 1. `asc notarization`

当前实现是 local manifest-backed 队列，不调用外部 Notary 服务。

### 1.1 `notarization submit`
- `--file <path>`（必填）：待处理的包或应用文件
- `--wait`（可选）：同步等待本地状态推进
- `--poll-interval`, `--timeout`
- 行为：验证文件存在后，将提交记录写入 `.asc/notarization/notarizations.json`，返回本地生成的 submission ID 与状态。

### 1.2 `notarization list`
- `--limit`（可选）
- 输出本地 manifest 中的 notarization 提交列表。

### 1.3 `notarization log`
- `--id <submission-id>`（必填）
- 返回本地记录的日志行与当前派生状态。

### 1.4 `notarization status`
- `--id <submission-id>`（必填）
- 返回状态快照（eligible、status、startedAt、updatedAt、failureReason 等），状态由本地记录和时间推导。

## 2. `asc signing`

当前实现是 workspace-backed signing snapshot，同步目标是本地 `profiles/` 目录和 `.asc/signing-sync/manifest.json`。

### 2.1 `signing sync`
- `signing sync pull`
  - 从本地 manifest 恢复 profiles 到本地目录
- `signing sync push`
  - 捕获本地 profiles 与 certificates，写入 workspace manifest
- 兼容 `--dry-run` 与 `--confirm`，默认 `dry-run`

## 3. `asc profiles download`

当前实现不是远端下载，而是从本地 provisioning profile store 解析并复制。

- `--id <profile-id>`（必填）
- `--output <path>`（可选，默认 `./profiles/<name>.mobileprovision`）
- 行为：从 `profiles/` 与 `~/Library/MobileDevice/Provisioning Profiles/` 查找匹配项，写入目标路径并输出摘要。

## 4. 错误与输出策略

- 文件 I/O 错误使用 `ValidationError` 或 `CommandFallback.fileWriteError`，并保留路径与原因。
- 不返回 `missingCapability` / `notImplemented` 这类远端能力缺失结构，因为当前实现本来就是本地路径。
- `--help` 和命令 abstract 应明确写出 local / workspace / manifest 语义，避免出现 `Team Storage` 或 `current account` 之类远端暗示。

## 5. 测试要求

- `Tests/ASCCommandTests/Commands/NotarizationCommandTests.swift`
  - 断言 help abstract 体现 local manifest 语义
- `Tests/ASCCommandTests/Commands/SigningSyncCommandTests.swift`
  - 断言 help abstract 体现 workspace-backed 语义
- `Tests/ASCCommandTests/Commands/Profiles/ProfilesDownloadTests.swift`
  - 断言 help abstract 与输出路径语义为 local store

## 6. 交付标准

- `asc notarization`、`asc signing`、`asc profiles download` 的 `--help` 不再暗示 Team Storage 或远端 Notary API。
- 子命令在 json/table 输出上维持现有字段，但帮助文本与文档描述必须和实际本地实现一致。
