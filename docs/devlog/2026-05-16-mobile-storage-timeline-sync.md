# 开发日志：真机存储、长笔记、消费同步与盘页面稳定性

**日期**: 2026-05-15 ~ 2026-05-16  
**项目**: Liflow  
**工作区**: `E:\codexapp\Dayline\dayline_app`  
**真机设备**: `V2154A / 3432033034001K3`  
**云端提交**: `4fddb4f Improve mobile storage and timeline sync`

---

## 1. 背景

这一轮主要围绕真机使用暴露出来的问题做闭环：

- 首次进入 App 时，Markdown 笔记存储目录不够明确，用户仍需要自己去文件管理器里找。
- Android 权限页没有显示文件权限，导致“应用到底怎么写入文件”不透明。
- 长笔记阅读能识别 Markdown 标题，但编辑页回车换行不稳定。
- 线页面切换/保存后容易回到顶部。
- 消费卡片修改后，外层显示与实际金额不同步。
- 盘页面消费统计需要拆成日消费和月消费，并减少对日常文本的重复计算。
- 盘页面点击待办后会触发刷新，滚动位置回弹顶部。

---

## 2. Android Markdown 存储授权

### 改动

- Android 端接入 `ACTION_OPEN_DOCUMENT_TREE`，通过系统文件夹选择器获取 SAF 目录授权。
- `MainActivity.kt` 新增 MethodChannel：`liflow/markdown_storage`。
- 支持：
  - `pickDirectory`
  - `hasTreeAccess`
  - `writeTextFile`
  - `readTextFile`
- `MarkdownStorageService` 统一封装本地路径与 SAF tree uri 的读写。
- 首次启动或旧配置缺失 SAF 授权时，自动弹出 Liflow 笔记库选择流程。
- Android 上不再默认走应用私有目录，避免文件管理器/Obsidian 找不到笔记。
- 默认目录名统一为 `Liflow`。

### 结论

Android 普通“应用权限”页不会显示 SAF 文件夹授权；真正的写入授权来自系统文件夹选择器里的“使用此文件夹”。这次改动让 App 启动时主动引导用户完成这个授权。

---

## 3. 长笔记编辑与阅读

### 改动

- 长笔记正文输入框显式设置：
  - `keyboardType: TextInputType.multiline`
  - `textInputAction: TextInputAction.newline`
- 修复在真机输入法里 Markdown 标题后无法稳定换行的问题。
- 新增 `markdown_document_parser.dart`，统一解析 front matter、标题和正文。
- 长笔记阅读页和编辑页共用解析后的标题/正文，避免读取、编辑、保存时内容漂移。
- Markdown reader 增强：
  - 标题
  - 加粗/斜体
  - 列表
  - 引用
  - 代码块
  - 表格

### 测试

- 新增 `test/features/long_note_editor_page_test.dart`，确保正文框保持多行输入并保留换行。

---

## 4. 线页面滚动与编辑体验

### 改动

- 线页面进入时可滚到最新记录，避免手动找底部最新内容。
- `TimelineBody` 改为保留缓存数据，刷新时不再因为 Future loading 闪烁导致列表跳动。
- 长笔记保存后回到阅读/线页面时，减少回弹顶部的概率。
- 普通记录编辑保留内容和标签，删除仍走软删除。

---

## 5. 消费数据同步

### 改动

- 新增 `expense_note_cleaner.dart`，把备注里的旧金额清掉。
- 创建/编辑消费时，金额归金额，备注归备注，避免备注残留旧金额。
- 时间线消费卡片描述使用清洗后的 note。
- 修改消费金额后，卡片标题和备注显示不再互相打架。

### 记录转消费/待办

在每条普通日常记录下增加快捷操作：

- `消费`
- `待办`

点击 `消费` 后：

- 解析记录中的金额。
- 创建对应消费卡片。
- 给原记录 metadata 写入 `linkedExpenseId`。
- 给原记录补上 `消费` 标签。
- 盘页面日/月消费统计直接读取 `expenses` 表。

点击 `待办` 后：

- 创建对应待办。
- 给原记录 metadata 写入 `linkedTodoId`。
- 给原记录补上 `待办` 标签。

后续如果修改这条原始日常记录：

- 已关联消费：同步更新消费金额、分类、备注。
- 已关联待办：同步更新待办标题和时间。

### 设计取舍

盘页面不再反复全文扫描日常记录来猜金额，而是只统计结构化的消费卡片。漏掉的记录由用户通过快捷按钮补成消费卡片，这样计算量更小，数据也更可控。

---

## 6. 盘页面消费统计与滚动稳定

### 日/月消费

- `ExpensesRepository` 新增 `sumAmountByMonth`。
- `DashboardSummary` 新增 `monthExpenseTotal`。
- 盘页面展开态将消费拆成：
  - 日消费
  - 月消费
- 数值显示精确到小数点后一位。

### 待办点击回弹顶部

问题原因：

- 点击待办完成/恢复后触发 `dataVersion`。
- `dashboardSummaryProvider` 重新加载时，盘页面可能短暂切到 loading。
- 展开页的 `SingleChildScrollView` 被替换，滚动位置丢失。

修复：

- `DashboardPage` 缓存上一份 `DashboardSummary`。
- 刷新时继续显示旧 summary，不再把页面拆掉换成 loading。
- 展开页滚动容器改为 `PageStorageKey('dashboard-expanded-scroll')`，保留滚动位置。

---

## 7. 构建、安装与推送记录

### 本地验证

执行过的关键验证：

```powershell
flutter test test\core\database\repositories_test.dart test\features\dashboard\dashboard_providers_test.dart test\widget_test.dart test\ui_redesign_test.dart test\expense_note_cleaner_test.dart test\lui_lite_parser_test.dart
flutter test test\features\long_note_editor_page_test.dart test\expense_note_cleaner_test.dart test\lui_lite_parser_test.dart
flutter build apk
```

构建产物：

```text
E:\codexapp\Dayline\dayline_app\build\app\outputs\flutter-apk\app-release.apk
```

### 真机安装

安装命令：

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

最终安装成功：

```text
Performing Streamed Install
Success
```

### Git

已提交并推送：

```text
4fddb4f Improve mobile storage and timeline sync
```

推送目标：

```text
origin/main -> https://github.com/2478643035/Dayline.git
```

推送时发现全局 Git 代理指向 `127.0.0.1:6984`，但本地代理未运行。实际推送使用一次性参数临时绕过代理，未修改全局 Git 配置。

---

## 8. 后续观察点

- SAF 授权丢失时，是否能稳定重新弹出目录选择。
- 记录转消费后，修改原记录金额是否在所有入口同步刷新。
- 盘页面待办点击后，真机上是否完全消除滚动回弹。
- 长笔记编辑页在不同输入法下，标题、列表、引用后的换行是否都稳定。
- 旧包 `com.example.dayline_app` 仍在设备上，后续可考虑清理，避免和新包 `com.example.liflow_app` 混淆。
