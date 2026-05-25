# 2026-05-25 Liflow 2.0.0 backup and restore devlog

## 背景

这次版本围绕“误删软件、重装后选择原文件夹恢复记录”的场景补齐第一版和第二版恢复链路，并顺手优化了项目页待办与最近更新区域。

用户希望 Liflow 在卸载重装后，只要重新选择原来的可见文件夹，就能尽量恢复本地记录。第一版先支持从 Markdown 降级解析恢复；第二版进一步写入结构化快照，让恢复更完整、更稳定。

## 本次完成

- 版本升级到 `2.0.0+9`。
- 新增恢复模块 `lib/features/restore/`。
- 新增 `.liflow/backup_snapshot.json` 结构化快照。
- 快照包含 `records`、`todos`、`projects`、`settings`。
- App 数据变化后会 debounce 写入快照，避免频繁阻塞正常操作。
- 重装后选择原文件夹时，优先读取快照恢复。
- 快照不存在或不可用时，继续降级扫描 Markdown 文件恢复。
- 恢复设置时跳过当前 Markdown 文件夹授权相关 key，避免覆盖用户刚重新选择的目录。
- 恢复弹窗会区分快照和 Markdown，并展示可恢复数量。
- 补充恢复服务单测，覆盖 Markdown 恢复、快照优先、重复恢复去重、待办和设置恢复。

## 项目页调整

- 待办长文本支持折叠和展开。
- 已完成待办自动排到未完成待办下方。
- 最近 7 天待办优先展示，7 天外待办进入收纳框。
- 最近更新保留 10 条直接展示，其余进入收纳框。
- 项目更新内部保留上限扩到 60 条，避免历史更新过早丢失。
- 待办完成点击增加本地乐观反馈，减少用户感知卡顿。

## 日记导出调整

- 日记导出结构升级到 `version: 2`。
- 导出内容补充当天时间线、待办流转和原始记录分组。
- 原始记录包含记录、待办、打卡、专注、消费、身体等条目，便于后续检索和人工查看。

## 恢复策略

恢复优先级：

1. 读取 `.liflow/backup_snapshot.json`。
2. 如果快照 schema 匹配，则按结构化数据恢复。
3. 如果没有快照、快照为空或 schema 不匹配，则扫描 `daily/`、`notes/`、`projects/` 下的 Markdown。
4. 恢复时用内容、日期、创建时间等稳定字段去重，避免重复导入。

设置恢复策略：

- 恢复普通 app 设置。
- 跳过 `projects_state_v1`，项目通过 projects 快照单独合并。
- 跳过 `markdown_root_path`、`markdown_root_tree_uri`、`markdown_root_tree_subdir`、`markdown_root_configured`，保护当前文件夹授权。

## 验证

- `flutter test test\features\restore\markdown_restore_service_test.dart` 通过。
- `flutter analyze` 仍有 4 个既有 warning/info，本次改动没有新增分析问题。
- `flutter build apk --release` 成功。
- 已安装到真机 `3432033034001K3`。
- 真机确认 `versionName=2.0.0`，`versionCode=9`。

## 后续想法

- 快照可以继续扩展媒体附件、打卡、专注、消费和身体记录。
- 可以在设置页增加“立即备份一次”和“查看最近备份时间”。
- 可以给恢复弹窗增加“高级详情”，展示即将恢复的项目和记录样例。
