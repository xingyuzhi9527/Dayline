# Dayline 长笔记与 Markdown 笔记目录配置计划书

## 1. 背景

Dayline 当前已经形成三个核心入口：

- `记`：快速记录，一句话、语音、待办进入系统。
- `线`：按时间回看记录和待办。
- `盘`：把当天内容复盘并生成 Markdown 今日笔记。

下一步需要补齐一种新的记录形态：长笔记。

用户有时不是想快速留下一句碎片，而是想写一篇相对完整的内容，例如：

- 一段灵感展开。
- 一篇会议记录。
- 一份学习笔记。
- 一篇当天之外的长文。
- 一份可以长期沉淀进个人数据库的 Markdown 文档。

因此，可以在 `记` 页底部小键盘功能区加入一个“下滑打开长笔记”的入口。打开后进入接近全屏的长笔记编辑窗口，支持自定义标题和 Markdown 内容，保存后生成 `.md` 文件。

同时，由于 `盘` 页也会生成“今日笔记” Markdown，这两个功能都需要统一的笔记目录配置。第一次使用应用时，应引导用户选择或确认 Markdown 保存目录。

## 2. 产品目标

### 目标一：补齐长内容记录能力

`记` 页目前适合短输入，但不适合写长内容。长笔记功能要允许用户直接在 Dayline 内完成一篇 Markdown 文档。

### 目标二：建立统一 Markdown 数据库目录

长笔记和今日复盘笔记都应保存到同一个根目录下，长笔记需自己起名字，而今日笔记默认采用当日时间，形成稳定的个人知识库结构。

### 目标三：为未来 AI 做准备

所有 Markdown 文件应有稳定路径、稳定 front matter、稳定标题结构，方便以后接入 AI 做检索、总结、周报、月报和个人数据库问答。

## 3. 功能边界

### 本次要做

- 第一次使用应用时弹出笔记目录配置。
- 在 `记` 页底部小键盘功能区加入长笔记入口。
- 支持下滑或点击入口打开长笔记编辑器。
- 长笔记窗口接近全屏。
- 支持标题输入。
- 支持 Markdown 正文输入。
- 支持保存和取消。
- 保存后生成 `.md` 文件。
- Markdown 文件写入统一笔记目录。
- 今日复盘 Markdown 也复用同一个目录配置。
- 支持基础 Markdown 语法高亮或语法提示。

### 本次不做

- 不做完整富文本编辑器。
- 不做所见即所得排版。
- 不做复杂表格编辑器。
- 不做云同步。
- 不做文件冲突合并。
- 不做 AI 自动改写。
- 不做多设备实时同步。

本阶段重点是“能稳定写、稳定保存、结构清晰”。

## 4. 信息架构

### 统一 Markdown 根目录

建议默认目录名：

```text
DaylineNotes/
```

目录下分两类：

```text
DaylineNotes/
  daily/
    2026/
      05/
        2026-05-14.md
  notes/
    2026/
      05/
        2026-05-14_会议记录.md
        2026-05-14_灵感草稿.md
```

说明：

- `daily/`：由 `盘` 页生成的每日复盘笔记。
- `notes/`：由 `记` 页长笔记编辑器生成的自定义笔记。

这样可以避免“今日笔记”和“长笔记”混在同一层目录里。

## 5. 第一次使用目录配置

### 触发时机

应用首次启动后，如果没有配置 Markdown 根目录，则弹出配置弹窗。

也可以在用户第一次点击以下功能时弹出：

- `盘` 页生成今日笔记。
- `记` 页打开长笔记保存。

建议策略：

1. 首次启动时弹出轻量配置。
2. 用户可以跳过。
3. 当真正保存 Markdown 时，如果仍未配置，则强制配置。

### 弹窗内容

标题：

```text
设置笔记保存位置
```

说明：

```text
Dayline 会把每日复盘和长笔记保存为 Markdown 文件，方便以后形成你的个人数据库。
```

按钮：

- 使用默认目录
- 选择目录
- 暂不设置

### 默认目录

Android 上建议先使用应用可写目录：

```text
Android/data/<package>/files/DaylineNotes/
```

如果用户希望文件更容易导出，可后续通过系统目录选择器选择外部目录。

### 配置存储

使用现有 `app_settings` 表。

建议 key：

```text
markdown_root_path
markdown_root_configured
markdown_note_naming_mode
```

示例：

```json
{
  "markdown_root_path": ".../DaylineNotes",
  "markdown_root_configured": "true",
  "markdown_note_naming_mode": "date_title"
}
```

## 6. `记` 页长笔记入口设计

### 入口位置

放在 `记` 页底部小键盘胶囊的功能区。

当前小胶囊主要承担“打开文本输入”的作用。可以扩展为：

- 点击键盘图标：打开短文本输入。
- 在胶囊区域下滑：打开长笔记。
- 或点击展开后的功能按钮：打开长笔记。

### 推荐交互

为了避免误触，第一阶段建议不要只依赖“下滑手势”，而是提供明确入口：

1. 用户点击小键盘胶囊，打开短文本输入。
2. 输入框上方或旁边出现一个轻量功能按钮：长笔记。
3. 用户也可以在小胶囊上向下滑动直接打开长笔记。

原因：

- 下滑手势不够显性。
- 用户第一次不一定知道。
- 明确按钮利于测试和可访问性。

### 视觉建议

小胶囊功能区保持 `记` 页当前语言：

- 图标优先。
- 少文字。
- 胶囊按钮。
- 轻阴影。
- 不使用重卡片。

长笔记入口图标建议：

- `Icons.article_outlined`
- `Icons.notes_rounded`
- `Icons.edit_note_rounded`

## 7. 长笔记编辑窗口

### 打开形态

接近全屏的 bottom sheet 或 full-screen dialog。

建议第一阶段使用 full-screen dialog：

- 更适合长文本。
- 键盘适配更稳定。
- 顶部操作更清晰。
- 不受底部导航影响。

页面结构：

```text
顶部栏：
  取消        长笔记        保存

标题输入：
  笔记标题

Markdown 工具条：
  H1 H2 B I - [ ] 表格 引用 代码

正文编辑区：
  Markdown 文本输入

底部状态：
  字数 / 自动保存状态 / 文件名预览
```

### 操作按钮

顶部左侧：

- 取消

顶部右侧：

- 保存

保存按钮规则：

- 标题为空且正文为空：禁用。
- 正文不为空但标题为空：自动用当前时间生成标题。
- 保存中：显示 loading。
- 保存成功：关闭窗口或显示成功状态。

### 取消规则

如果内容为空：

- 直接关闭。

如果有未保存内容：

- 弹出确认：

```text
放弃这篇笔记？
```

按钮：

- 继续编辑
- 放弃

## 8. Markdown 编辑能力

### 第一阶段能力

支持 Markdown 原文编辑，不做富文本渲染。

但要提供基础语法辅助：

- 标题：`# `、`## `
- 加粗：`**文字**`
- 斜体：`*文字*`
- 待办：`- [ ] `
- 列表：`- `
- 引用：`> `
- 代码块：```` ``` ````
- 表格模板：

```md
| 项目 | 内容 |
| --- | --- |
|  |  |
```

### 语法高亮策略

Flutter 原生 `TextField` 不适合复杂高亮。建议分阶段：

#### 阶段 1：语法工具条 + 原文编辑

先用普通多行 `TextField`。

用户通过工具条插入 Markdown 指令。

优点：

- 稳定。
- 好实现。
- 键盘适配简单。

#### 阶段 2：轻量 Markdown 高亮

引入或自研一个高亮编辑控件。

高亮内容：

- 标题行。
- 代码块。
- 引用。
- 表格分隔线。
- 粗体标记。

原则：

- 高亮只是辅助，不改变 Markdown 原文。
- 不做所见即所得。

#### 阶段 3：预览模式

增加“编辑 / 预览”切换。

第一阶段可以先不做预览，避免范围过大。

## 9. Markdown 文件命名

### 默认命名

长笔记默认：

```text
2026-05-14_23-40.md
```

如果用户输入标题：

```text
2026-05-14_会议记录.md
```

如果用户选择“时间 + 自定义标题”：

```text
2026-05-14_23-40_会议记录.md
```

### 命名模式

支持三种：

1. 日期

```text
2026-05-14.md
```

2. 日期 + 标题

```text
2026-05-14_标题.md
```

3. 日期时间 + 标题

```text
2026-05-14_23-40_标题.md
```

长笔记建议默认使用第三种，避免同一天多篇笔记冲突。

今日复盘笔记建议固定使用第一种：

```text
daily/2026/05/2026-05-14.md
```

## 10. 长笔记 Markdown 模板

```md
---
type: note
source: dayline
created_at: 2026-05-14T23:40:00+08:00
updated_at: 2026-05-14T23:40:00+08:00
title: 会议记录
tags: []
---

# 会议记录

正文内容...
```

如果标题为空：

```md
---
type: note
source: dayline
created_at: 2026-05-14T23:40:00+08:00
updated_at: 2026-05-14T23:40:00+08:00
title: 2026-05-14 23:40
tags: []
---

# 2026-05-14 23:40

正文内容...
```

## 11. 今日复盘 Markdown 与长笔记的关系

二者都保存为 Markdown，但职责不同。

### 今日复盘笔记

来源：

- `盘` 页。

特点：

- 一天一篇。
- 自动聚合当天数据。
- 包含时间线、节奏、洞察、晚间复盘。
- 文件路径固定。

路径：

```text
DaylineNotes/daily/2026/05/2026-05-14.md
```

### 长笔记

来源：

- `记` 页。

特点：

- 用户主动创建。
- 一天可以多篇。
- 标题和正文由用户决定。
- 不自动混入今日复盘。

路径：

```text
DaylineNotes/notes/2026/05/2026-05-14_23-40_标题.md
```

### 是否进入时间线

建议保存长笔记后，在 SQLite 中也写一条轻量记录：

```text
type = long_note
content = 标题
metadata = {
  "path": "...",
  "title": "...",
  "wordCount": 1234
}
```

这样：

- `线` 页能看到这篇长笔记发生在什么时候。
- `盘` 页能统计“今天写了一篇长笔记”。
- 以后 AI 可以同时读取 Markdown 文件和数据库索引。

## 12. 数据结构建议

### app_settings

继续使用现有表：

```text
key: markdown_root_path
value: /.../DaylineNotes

key: markdown_note_naming_mode
value: datetime_title
```

### records

保存长笔记索引：

```json
{
  "type": "long_note",
  "content": "会议记录",
  "tags": [],
  "metadata": {
    "path": ".../DaylineNotes/notes/2026/05/2026-05-14_23-40_会议记录.md",
    "title": "会议记录",
    "wordCount": 1280
  }
}
```

### 可选：long_notes 表

第一阶段不建议新增表，先用 Markdown 文件 + records 索引即可。

后续如果需要管理长笔记列表、编辑历史、草稿恢复，再新增：

```sql
CREATE TABLE long_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  file_path TEXT NOT NULL,
  date TEXT NOT NULL,
  word_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
```

## 13. 文件保存服务

建议新增：

```text
lib/core/markdown/markdown_directory_service.dart
lib/core/markdown/markdown_note_service.dart
lib/core/markdown/markdown_filename.dart
```

职责：

### MarkdownDirectoryService

- 读取保存目录。
- 初始化默认目录。
- 判断目录是否存在。
- 处理目录选择结果。
- 提供 `ensureMarkdownRoot()`。

### MarkdownNoteService

- 保存长笔记。
- 保存今日复盘笔记。
- 创建年月目录。
- 处理文件覆盖。
- 返回保存路径。

### MarkdownFilename

- 清理非法文件名字符。
- 根据日期、时间、标题生成文件名。
- 保证 `.md` 后缀。

## 14. UI 组件建议

新增：

```text
lib/features/markdown_setup/markdown_directory_dialog.dart
lib/features/flash_record/widgets/long_note_entry.dart
lib/features/long_note/long_note_editor_page.dart
lib/features/long_note/widgets/markdown_toolbar.dart
lib/features/long_note/long_note_notifier.dart
lib/features/long_note/long_note_state.dart
```

### MarkdownDirectoryDialog

负责首次配置目录。

### LongNoteEntry

放在 `记` 页小键盘功能区。

### LongNoteEditorPage

接近全屏编辑器。

### MarkdownToolbar

插入 Markdown 指令。

### LongNoteNotifier

处理标题、正文、保存中、错误、已保存路径等状态。

## 15. 权限与平台注意事项

Android 文件写入要注意：

- 应用私有目录最稳。
- 选择公共目录需要系统文件选择器或存储访问框架。
- 不建议直接申请广泛存储权限。

第一阶段建议：

- 默认使用应用文档目录。
- 设置页后续再提供“导出/更换目录”。

如果要让用户直接选文件夹：

- 需要评估 Flutter 插件。
- 需要真机测试不同 Android 版本。

## 16. 实施步骤

### 第 1 步：目录配置基础

交付：

- Markdown 根目录配置服务。
- 默认目录初始化。
- `app_settings` 保存路径。
- 首次弹窗。

测试：

- 未配置时返回默认目录。
- 配置后读取用户目录。
- 目录不存在时自动创建。

### 第 2 步：长笔记保存服务

交付：

- 文件名生成。
- Markdown front matter。
- 保存 `.md` 文件。
- 返回文件路径。

测试：

- 标题为空时使用时间标题。
- 标题含非法字符时能清理。
- 同一天多篇不会覆盖。
- 文件内容包含 front matter 和正文。

### 第 3 步：`记` 页入口

交付：

- 小键盘功能区增加长笔记入口。
- 支持点击打开。
- 可选支持下滑打开。

测试：

- 点击入口打开编辑器。
- 下滑手势不会影响普通短文本输入。

### 第 4 步：长笔记编辑器

交付：

- 全屏编辑页。
- 标题输入。
- 正文输入。
- 保存/取消。
- 未保存退出确认。

测试：

- 空内容保存禁用。
- 输入标题和正文后保存成功。
- 取消有确认。
- 键盘不遮挡输入区域。

### 第 5 步：Markdown 工具条

交付：

- 标题、加粗、列表、待办、引用、代码块、表格模板插入。

测试：

- 光标处插入语法。
- 选中文本时包裹语法。
- 插入表格模板不破坏已有内容。

### 第 6 步：写入时间线索引

交付：

- 保存长笔记后，在 `records` 表插入 `type = long_note`。
- `线` 页展示为一条长笔记记录。

测试：

- 保存后 `线` 页可见。
- metadata 中包含文件路径。

### 第 7 步：复盘 Markdown 复用目录

交付：

- `盘` 页生成今日笔记时使用同一 Markdown 根目录。
- 今日笔记保存到 `daily/YYYY/MM/`。

测试：

- 长笔记和今日笔记保存到不同子目录。
- 首次保存时如果没有目录配置，会先弹配置。

## 17. 验收标准

### 产品验收

- 用户能从 `记` 页进入长笔记。
- 长笔记编辑器接近全屏，写长文不局促。
- 用户能自定义标题。
- 用户能写 Markdown 原文。
- 用户能保存为 `.md` 文件。
- 用户能取消且不会误丢内容。
- 今日复盘和长笔记使用同一个根目录。

### 工程验收

- Markdown 保存逻辑有单元测试。
- 文件名生成逻辑有单元测试。
- 长笔记入口有 widget test。
- 编辑器保存/取消有 widget test。
- 真机验证通过。

### 数据验收

- Markdown 文件真实存在。
- 文件名符合规则。
- front matter 正确。
- 保存后 `records` 有索引。
- `线` 页能看到长笔记记录。

## 18. 风险与处理

### 风险一：目录权限复杂

处理：

- 第一阶段默认应用私有目录。
- 后续再做用户自选目录。

### 风险二：Markdown 高亮复杂

处理：

- 第一阶段做工具条，不做复杂高亮。
- 第二阶段再做轻量高亮。

### 风险三：入口手势不明显

处理：

- 下滑作为快捷方式。
- 同时提供明确按钮入口。

### 风险四：今日笔记和长笔记混乱

处理：

- 用 `daily/` 和 `notes/` 分目录。
- front matter 中用 `type: daily` 和 `type: note` 区分。

## 19. 最终方向

这个功能可以让 Dayline 的记录体系更完整：

- 碎片：用 `记` 的短输入。
- 长文：用 `记` 的长笔记。
- 回看：用 `线`。
- 收束：用 `盘`。
- 沉淀：全部进入 Markdown 文件夹。

一句话：

> Dayline 不只记录“发生了什么”，也允许用户在同一个系统里写下“我如何理解它”。

