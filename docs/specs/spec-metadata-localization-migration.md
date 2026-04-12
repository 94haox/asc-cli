# Spec: metadata / localizations / migrate 系列命令

目标：补齐 Skills 常用元数据命令并兼容 fastlane legacy 流程，确保文案更新与本地化同步可自动化执行。

## 1. `asc localizations`

新增命令族：`localizations list/download/upload`，并通过 `--type` 区分对象类型。

### 1.1 list
- `asc localizations list --version VERSION_ID`
- `asc localizations list --version VERSION_ID --type version`
  - 映射到 `version-localizations list --version-id VERSION_ID`
- `asc localizations list --app APP_ID --type app-info --app-info APP_INFO_ID`
  - 映射到 `app-info-localizations list --app-info-id APP_INFO_ID`

### 1.2 download
- `asc localizations download --version VERSION_ID --path ./localizations`
  - 读取 `VersionLocalization`，生成每语言 `.strings`（或已存在格式）。
- `asc localizations download --app APP_ID --type app-info --app-info APP_INFO_ID --path ./app-info-localizations`
  - 读取 `AppInfoLocalization`，支持同一目录下按 locale 文件写入。

### 1.3 upload
- `asc localizations upload --version VERSION_ID --path ./localizations`
  - 按 locale 文件创建/更新 version localization。
  - 缺少本地 `locale.strings` 时给出清晰错误。
- `asc localizations upload --app APP_ID --type app-info --app-info APP_INFO_ID --path ./app-info-localizations`
  - 按 locale 更新 app-info localizations（`name`、`subtitle`、`privacyPolicyUrl` 等）。

### 数据格式约定（metadata）
支持以下字段（至少）：  
- version 本地化：`whatsNew`、`description`、`keywords`、`marketingUrl`、`supportUrl`、`promotionalText`  
- app-info 本地化：`name`、`subtitle`、`privacyPolicyUrl`、`privacyChoicesUrl`、`privacyPolicyText`

### `localizations` 与现有命令映射策略
- `--type version`（默认）仅依赖 `VersionLocalizationRepository`。
- `--type app-info` 仅依赖 `AppInfoLocalization` 对应操作。
- 输出采用统一 `formatAgentItems`；遇到不支持字段写入时返回校验错误。

## 2. `asc metadata`

新增 `metadata` 命令族：`pull/push/validate/keywords/diff/apply/sync`。

### 2.1 `metadata pull --app APP_ID --version VERSION --dir ./metadata`
- 先解析 app/version，复用 `localizations download` 产物。
- 输出 canonical 目录结构（与 `asc metadata keywords`/ASO skill 兼容）。

### 2.2 `metadata push --app APP_ID --version VERSION --dir ./metadata [--dry-run]`
- 本地字段预检查后逐文件调用 `localizations upload`。
- `--dry-run`：输出确定性的差异摘要，并显式标记不支持的 delete 语义，而不是静默跳过。
- 非 `--dry-run`：对 canonical workspace layout 和 ownership 做严格校验，失败时返回结构化错误。

### 2.3 `metadata validate --dir ./metadata`
- 静态校验：
  - 必填项存在性
  - 字符长度上限（whatsNew/description/keywords 等）
  - locale 文件可读性与字段合法性
  - canonical workspace layout：`version-localizations/<locale>.json` 与 `app-info-localizations/<appInfoId>/<locale>.json`
  - decoded locale / versionId / appInfoId 必须与路径和父资源一致
  - malformed JSON 和 ownership mismatch 必须失败
- 返回结构化报告（成功 exit 0；失败 exit 非0）

### 2.4 `metadata keywords diff|apply|sync`
- `diff`：对比 `metadata pull/push` 的当前树与目标版本本地化数据；
- `apply`：把 `diff` 后的变更写回文件并（可选）提交至 ASC；遇到不支持的 delete 语义时，必须显式报告 `delete-unsupported`
- `sync`：支持从 `--input` CSV 更新关键词（按 locale + app/version 粒度）。

## 3. `asc migrate`

新增命令族：`migrate export/validate/import`

### 3.1 `migrate export`
- `asc migrate export --app APP_ID --version-id VERSION_ID --output-dir ./fastlane`
- 兼容 fastlane layout：各 locale 单文件、`metadata.xml`/`description.txt` 等主流布局。

### 3.2 `migrate validate`
- `asc migrate validate --fastlane-dir ./fastlane`
- 校验 legacy 目录完整性、字段长度、canonical workspace ownership 和文件名布局。
- malformed JSON、孤立 locale 文件与 ownership mismatch 必须返回清晰错误。

### 3.3 `migrate import`
- `asc migrate import --app APP_ID --version-id VERSION_ID --fastlane-dir ./fastlane`
- `--dry-run`：仅输出即将提交改动摘要，并标记 `planned-delete-unsupported`。
- 非 `--dry-run`：执行实际更新、返回影响条目，并显式报告 `delete-unsupported`。

## 测试要求
- `Tests/ASCCommandTests/Commands/Localizations*`：
  - `LocalizationsListTests`
  - `LocalizationsDownloadTests`
  - `LocalizationsUploadTests`
- `Tests/ASCCommandTests/Commands/Metadata*`
  - `MetadataPullTests` / `MetadataPushTests` / `MetadataValidateTests`
  - `MetadataKeywordsTests`
- `Tests/ASCCommandTests/Commands/Migrate*`
  - `MigrateExportTests` / `MigrateValidateTests` / `MigrateImportTests`

## 风险与边界
- `localizations upload` 应避免自动覆盖缺失文件中的已有值（仅更新当前文件定义字段）。
- 读写路径需安全限制在指定目录，不允许路径逃逸（`..`）。
- 删除语义如果不在当前兼容层支持范围内，必须在计划和执行阶段都显式暴露出来。
