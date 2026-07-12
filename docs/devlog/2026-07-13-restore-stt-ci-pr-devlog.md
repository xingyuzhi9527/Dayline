# Dayline 开发日志：恢复补救、离线 STT 与 PR 流程

日期：2026-07-13  
分支：`restore-stt-fix`  
核心提交：

- `92428d4 Fix restore fallback and offline STT packaging`
- `f351f70 Use Flutter 3.44.6 in CI`

## 1. 背景

本轮问题来自一次新旧 APK 切换后的数据恢复异常：

- 新版导入已有 Markdown 文件时，项目文件有遗漏。
- 语音功能不可用，需要确认离线 STT 资源是否真的打进 APK。
- 回装旧版后，待办和月账单在界面里消失，只剩项目内待办。
- 旧的恢复流程过度依赖 `.liflow/backup_snapshot.json`，当快照里的 `todos` / `expenses` 为空或被覆盖时，不会继续从 Markdown 镜像里补救。

Dayline 的存储设计是 SQLite + Markdown 双层结构。SQLite 是主查询表，Markdown 是用户可见镜像。换机、卸载、回装之后，恢复流程必须能在结构化快照缺失时重新从 Markdown 抢回关键数据。

## 2. 已完成修复

### 2.1 结构化快照扩展

备份快照升级到 schema v4，覆盖更多 SQLite 表和项目文件：

- `records`
- `todos`
- `trackers`
- `tracker_logs`
- `focus_sessions`
- `expenses`
- `body_logs`
- `daily_reviews`
- `media_attachments`
- `project_files`
- `projects`
- `settings`

项目附件也会写入 `.liflow/project_files/...`，恢复时会尝试校验大小和 sha256 后还原。

### 2.2 Markdown 恢复补救

当没有可用快照，或快照存在但 `todos` / `expenses` 为空时，恢复器会继续扫描 Markdown：

- 从 `daily/*.md` 的 `## 待办`、`## 待办流转`、`### 已完成`、`### 未完成` 恢复待办。
- 从 `daily/*.md` 的 `### 消费`、`### 支出`、`### 消费明细` 恢复消费。
- 从月账单 Markdown 恢复消费：`projects/月消费账本.../months/YYYY-MM.md` 内的 `## 每日明细`。

这样即使 `.liflow/backup_snapshot.json` 里的结构化表为空，只要原始 Markdown 还在，待办和月账单仍可以重新落回 SQLite。

### 2.3 资料库入口

资料库页面增加手动恢复入口，方便在已配置 Markdown 根目录后主动触发恢复，不必依赖首次引导。

### 2.4 离线 STT 打包

确认新版 arm64 APK 包含：

- `assets/stt/sense_voice_small_zh.tar.bz2`
- `sherpa_onnx` / `onnxruntime` Android native libs

旧的 `assets/stt/dayline-stt-v2.zip` 已移除。新增兼容逻辑会识别旧安装目录中的 `model.int8.onnx` + `tokens.txt`，必要时补写 `integrity.json`，避免旧模型资源因为缺少完整性文件而被误判不可用。

### 2.5 CI 修复

GitHub Actions 原先固定 Flutter `3.35.0`，对应 Dart `3.9.0`。当前依赖解析需要更高 SDK，因此 CI 的 Flutter 版本已升级为 `3.44.6`。

后续 Flutter 3.44.6 触发了新的弃用提示：

- `ReorderableListView.onReorder` 已弃用。
- 应改用 `onReorderItem`。
- `onReorderItem` 会自动调整 `newIndex`，所以旧逻辑里的 `if (insertionIndex > oldIndex) insertionIndex -= 1;` 必须一起删除。

## 3. 验证记录

本地已通过：

- `flutter test test\features\restore\markdown_restore_service_test.dart`
- `flutter analyze`
- `flutter build apk --release --split-per-abi`

生成的 arm64 release APK：

`E:\codex\codexapp\Dayline\dayline_app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`

## 4. GitHub 分支策略

远端 `main` 有仓库规则保护：

- 禁止直接 push 到 `main`
- 所有变更必须通过 Pull Request

因此正确流程是：

1. 在本地 `restore-stt-fix` 分支提交修复。
2. 推送 `restore-stt-fix` 到远端。
3. 在 GitHub 创建 `restore-stt-fix -> main` 的 PR。
4. 等 CI 全绿后合并 PR。
5. 合并后本地同步 `main`。

## 5. 风险与后续注意

- 如果用户手机上的 Markdown 根目录本身已经丢失，恢复器无法凭空找回待办和账单。
- 如果 `.liflow/backup_snapshot.json` 被旧版覆盖为空，新版会尝试从 Markdown 补救，但前提仍是 `daily` 和 `projects/月消费账本.../months` 文件存在。
- CI 升级 Flutter 后，未来可能继续暴露新版本 analyzer 的弃用提示，需要逐项修掉，不建议把 lint 降级绕过去。
- 本地 release 签名配置 `android/key.properties` 不应提交。

