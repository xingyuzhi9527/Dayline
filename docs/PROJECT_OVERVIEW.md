# Dayline App — 项目全面说明

> **版本**: 0.1.0+1 | **分支**: main | **最后更新**: 2026-05-03
>
> 面向读者：有长期编程经验的工程师，不需要术语解释。

---

## 1. 项目定位

Dayline 是一个 **local-first 的个人生活记录应用**，用 Flutter 构建。核心理念：

- **本地优先** — 核心数据先存本地 SQLite，不依赖网络。
- **隐私优先** — 默认不上传任何用户数据。没有统计、埋点、广告、第三方 SDK。
- **低摩擦记录** — 用户输入自然语言，App 自动解析意图并分类落库。
- **原始记录不可覆盖** — 用户输入原文保留，AI/整理结果只能作为附加层（目前 AI 层未实现）。

不是社交 App、不是任务管理工具、不是量化自我平台。更像一本"本地智能日记"。

---

## 2. 技术栈

| 层 | 方案 | 版本 |
|---|------|------|
| 框架 | Flutter | >=3.35.0 |
| 语言 | Dart | ^3.9.0 |
| 状态管理 | Riverpod | ^3.3.1 |
| 路由 | go_router (StatefulShellRoute) | ^17.2.2 |
| 本地数据库 | sqflite (裸写 SQL，无代码生成) | ^2.4.2+1 |
| 测试数据库 | sqflite_common_ffi (in-memory) | ^2.3.6 |
| 主题 | Material 3, 自定义 token 体系 | — |
| Lint | flutter_lints | ^6.0.0 |
| 平台 | Android + Web (iOS 目录未配置) | — |

**没有引入的常见依赖**：Drift, Hive, Isar, SharedPreferences, Provider, Bloc, GetX, freezed, Dio/Retrofit, Firebase, 任何 AI/语音 SDK。

---

## 3. 项目结构

```
dayline_app/
├── lib/
│   ├── main.dart                          # Entry: WidgetsFlutterBinding + ProviderScope
│   ├── app.dart                           # MaterialApp.router, theme injection
│   ├── app_routes.dart                    # AppRoute enum (today/timeline/record/review)
│   ├── app_router.dart                    # GoRouter + StatefulShellRoute, 4 branches
│   ├── shell/
│   │   └── dayline_shell.dart             # Scaffold shell, AppBar, 底部导航栏
│   ├── core/
│   │   ├── database/
│   │   │   ├── local_database.dart        # sqflite 生命周期, 8 表 schema (v1)
│   │   │   ├── repositories.dart          # 8 个 Repository 类 + CRUD 基类
│   │   │   └── repository_providers.dart  # Riverpod Provider 定义 + DataVersionNotifier
│   │   ├── parser/
│   │   │   └── lui_lite_parser.dart       # 自然语言解析器, 7 种输入类型
│   │   ├── export/
│   │   │   ├── export_service.dart        # Markdown / JSON 导出
│   │   │   └── export_providers.dart      # 导出 Providers
│   │   └── theme/
│   │       ├── app_colors.dart            # 颜色 token 体系（含 7 种记录类型配色）
│   │       ├── app_spacing.dart           # 间距和圆角常量
│   │       ├── app_typography.dart        # 字体族 + TextTheme 工厂
│   │       └── app_theme.dart             # ThemeData.light() / .dark()
│   ├── features/
│   │   ├── today/                         # "今天" 标签页
│   │   │   ├── today_page.dart
│   │   │   ├── today_providers.dart
│   │   │   └── widgets/today_cards.dart
│   │   ├── record/                        # "记录" 标签页
│   │   │   ├── record_page.dart
│   │   │   ├── record_state.dart
│   │   │   ├── record_notifier.dart
│   │   │   └── widgets/
│   │   │       ├── quick_input_bar.dart     # 快速输入条
│   │   │       └── parser_preview_card.dart # 解析预览确认 UI
│   │   ├── timeline/                      # "时间线" 标签页
│   │   │   ├── timeline_page.dart
│   │   │   ├── timeline_providers.dart
│   │   │   └── widgets/timeline_list.dart
│   │   ├── review/                        # "回顾" 标签页
│   │   │   ├── review_page.dart
│   │   │   ├── review_providers.dart
│   │   │   └── widgets/review_cards.dart
│   │   └── widgets/
│   │       └── empty_tab_page.dart         # 未使用的占位页
├── test/
│   ├── widget_test.dart                   # 3 个 widget tests (tab 切换 + 记录输入)
│   ├── lui_lite_parser_test.dart          # 19 个 parser 单元测试
│   ├── core/database/repositories_test.dart # 6 个 Repository 集成测试
│   └── ui_redesign_test.dart              # 4 个 UI 重设计验证测试
├── android/                               # 标准 Flutter Android shell, 无自定义
├── web/                                   # 标准 Flutter web bootstrap
├── docs/
│   └── dayline-ui-design-brief.md         # UI 设计简报 (中文, 341 行)
├── pubspec.yaml
├── analysis_options.yaml
└── .gitignore
```

---

## 4. 数据库设计

### 4.1 Schema (v1)

8 张表，全部在 `LocalDatabase._onCreate()` 中通过原始 SQL 创建。

```sql
-- 核心记录表（文本、备忘、语音元数据）
records (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  date       TEXT NOT NULL,          -- YYYY-MM-DD
  type       TEXT NOT NULL,          -- memo | voice
  content    TEXT NOT NULL,          -- 原始输入/识别文本
  time       TEXT,                   -- HH:MM
  tags       TEXT,                   -- JSON array, e.g. ["工作","阅读"]
  metadata   TEXT,                   -- JSON object, 扩展字段
  created_at INTEGER NOT NULL,       -- ms timestamp
  updated_at INTEGER NOT NULL
)
CREATE INDEX idx_records_date ON records(date)
CREATE INDEX idx_records_type ON records(type)

-- 待办事项
todos (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  date         TEXT NOT NULL,
  title        TEXT NOT NULL,
  note         TEXT,
  due_time     TEXT,
  priority     INTEGER DEFAULT 0,
  is_completed INTEGER DEFAULT 0,
  completed_at INTEGER,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
)
CREATE INDEX idx_todos_date ON todos(date)

-- 打卡项定义（习惯追踪）
trackers (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  name         TEXT NOT NULL,
  unit         TEXT,                 -- e.g. "分钟", "次", "杯"
  target_value REAL,
  color        TEXT,                 -- hex color
  icon         INTEGER,              -- IconData.codePoint
  is_archived  INTEGER DEFAULT 0,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
)

-- 打卡记录
tracker_logs (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  tracker_id INTEGER NOT NULL REFERENCES trackers(id),
  date       TEXT NOT NULL,
  value      REAL NOT NULL,
  note       TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
CREATE INDEX idx_tracker_logs_date ON tracker_logs(date)

-- 专注记录
focus_sessions (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  date            TEXT NOT NULL,
  started_at      TEXT,              -- HH:MM
  ended_at        TEXT,              -- HH:MM
  duration_minutes INTEGER NOT NULL,
  note            TEXT,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL
)
CREATE INDEX idx_focus_sessions_date ON focus_sessions(date)

-- 消费记录
expenses (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  date       TEXT NOT NULL,
  amount     REAL NOT NULL,
  category   TEXT,                   -- e.g. "餐饮", "交通"
  note       TEXT,
  currency   TEXT DEFAULT 'CNY',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
CREATE INDEX idx_expenses_date ON expenses(date)

-- 身体数据记录
body_logs (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  date       TEXT NOT NULL,
  metric     TEXT NOT NULL,          -- e.g. "体重", "BMI"
  value      REAL NOT NULL,
  unit       TEXT,                   -- e.g. "kg"
  note       TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
CREATE INDEX idx_body_logs_date ON body_logs(date)

-- 应用设置 (key-value)
app_settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)
```

### 4.2 Repository 层

- 基类 `Repository` 提供 `insert`, `findById`, `findAll`, `update`, `delete`, `withTimestamps`。
- 每个表一个子类：`RecordsRepository`, `TodosRepository`, `TrackersRepository`, `TrackerLogsRepository`, `FocusSessionsRepository`, `ExpensesRepository`, `BodyLogsRepository`, `AppSettingsRepository`。
- **所有数据以 `Map<String, Object?>` (typedef `DatabaseRow`) 传递**，没有 ORM，没有类型安全的 model 类。
- Repository 通过 Riverpod `Provider` 暴露，从 `localDatabaseProvider` 获取 `LocalDatabase` 实例。
- `LocalDatabase` 的构造函数接受可选的 `DatabaseFactory`，方便测试时注入 in-memory 实现。

### 4.3 缓存刷新机制

`DataVersionNotifier` 是一个 `Notifier<int>`，每次数据变更时调用 `increment()`（自增计数）。所有 `FutureProvider` 都 watch 此值作为 refresh signal，使 UI 在数据变更后自动重新获取。

---

## 5. 四个标签页详解

### 5.1 Today（今天）

路由: `/today` | 图标: `Icons.wb_twilight_rounded`

**组件树**：
```
ListView
├── DateHeaderCard       — 日期 + "Good morning, explorer" + 连续记录天数徽章
├── ProgressCard         — 日出→日落进度条 (当天已过百分比)
├── QuickInputBar        — 快速输入条 (saveImmediately 模式: 输入→保存→完成)
├── StatusInsightCard    — 能量评分/睡眠摘要/AI 建议 (当前为静态 mock 数据)
├── StatsSummaryCard     — 2×2 统计网格 (待办进度/专注时长/打卡/记录数)
├── TodayTrackersCard    — 活跃打卡项 chips, 点击直接打勾
├── TodayTodosCard       — 待办列表, 点击切换完成状态
└── RecentTimelineCard   — 最近 3 条记录预览
```

**数据来源**: 6 个 `FutureProvider` 分别查询当日数据，全部 watch `dataVersionProvider`。

### 5.2 Record（记录）

路由: `/record` | 图标: `Icons.edit_note_rounded`

**两段式流程**：

1. **输入阶段**：`QuickInputBar` (mode=preview)
   - 多行 TextField + 装饰性按钮（图片、麦克风、定位 — 仅有图标无功能）
   - 提交触发 `RecordNotifier.submit()` → `LuiLiteParser.parse()`

2. **预览确认阶段**：`ParserPreviewCard`
   - 显示解析结果：类型、时间、详情、标签
   - 用户可修正：类型下拉菜单、标签编辑
   - 操作：确认保存 / 改为备忘 / 取消重写

**状态机**：`RecordState` (immutable) — `inputText` → 解析 → `parsedInput`(preview) → 落库 → reset

### 5.3 Timeline（时间线）

路由: `/timeline` | 图标: `Icons.view_timeline_rounded`

- 日期选择器（前后翻页 + 回到今天）
- 该日所有事件按时间轴展示：记录、待办、打卡、专注、消费、身体数据
- `TimelineEvent` 是统一事件模型，从各个 Repository 合并并按时间戳排序
- 每种事件类型有不同颜色和图标的圆点标记

### 5.4 Review（回顾）

路由: `/review` | 图标: `Icons.auto_awesome_rounded`

- 日期选择器
- 每日摘要卡片（模板拼装的中文摘要文本，非 AI 生成）
- 统计网格（记录数/待办完成数/专注分钟/消费总计）
- 活动热度图（按小时的柱状图）
- 热门标签
- 导出按钮：Markdown / JSON，保存到 sqflite 数据库目录

---

## 6. 解析器设计 (`LuiLiteParser`)

### 6.1 输入类型枚举

| 类型 | 关键词/模式 | 置信度 |
|------|-----------|--------|
| `todo` | `todo`, `待办`, `任务`, `记得`, `要做` | 0.95 |
| `focus` | `番茄`, `专注`, `focus`, `pomodoro` | 0.90 |
| `expense` | `元`, `块`, `¥`, `￥`, `RMB` | 0.88 |
| `body` | `体重`, `weight` | 0.86 |
| `sleep` | `睡觉`, `入睡`, `醒来`, `起床` | 0.82 |
| `tracker` | `跑步`, `运动`, `健身`, `喝水`, `吃药`, `冥想`, `阅读` 等 | 0.78 |
| `memo` | 无匹配时的兜底 | 0.50 |

### 6.2 解析策略

纯正则 + 规则匹配，无 NLP 模型。按优先级顺序尝试匹配：

1. 提取 `#hashtag` → `tags[]`
2. 提取时间 (`HH:MM`, `H:MM`, `H点`, `H点半`) → `time`
3. 按置信度从高到低检查前缀/关键词
4. 提取数量（时长 `25min`/`30分钟` 或金额 `¥35`/`35元`）
5. 兜底 → `memo`, confidence=0.5

### 6.3 已知局限

- 无上下文理解（"今天跑步" vs "昨天跑步今天我休息" 无法区分）
- 无同义词扩展（hardcoded 关键词列表）
- 无法处理复合输入（一条输入包含多个事件）
- 无多语言支持（仅中文关键词 + 少数英文）

---

## 7. 状态管理架构

### 7.1 Riverpod 使用模式

```
Providertype        用途                    示例
─────────────────────────────────────────────────────
Provider<T>         单例/配置            localDatabaseProvider, appRouterProvider
NotifierProvider    可变状态             recordNotifierProvider, reviewDateProvider
FutureProvider      异步只读数据          todayRecordCountProvider, timelineEventsProvider
```

### 7.2 数据流

```
用户输入
  → RecordNotifier.submit(text)
    → LuiLiteParser.parse(text) → ParsedInput (preview)
  → 用户确认
    → RecordNotifier.confirm()
      → XxxRepository.create() → INSERT
        → ref.read(dataVersionProvider.notifier).increment()
          → 所有 FutureProvider 自动重新获取
            → UI 自动更新
```

### 7.3 RecordState 设计

```dart
class RecordState {
  final String inputText;
  final ParsedInput? parsedInput;  // null = 还没解析, non-null = 预览模式
  final bool isSaving;
  final String? errorMessage;

  bool get hasPreview => parsedInput != null;
  bool get canSubmit => hasPreview && !isSaving;
}
```

`copyWith` 使用 sentinel 模式区分 `null` 和"未提供"：
```dart
static const _unchanged = Object();
RecordState copyWith({Object? parsedInput = _unchanged, ...})
```

---

## 8. 路由设计

```dart
GoRouter(
  initialLocation: '/today',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, __, navigationShell) => DaylineShell(navigationShell),
      branches: [
        StatefulShellBranch(routes: [GoRoute('/today',    builder: TodayPage)]),
        StatefulShellBranch(routes: [GoRoute('/timeline', builder: TimelinePage)]),
        StatefulShellBranch(routes: [GoRoute('/record',   builder: RecordPage)]),
        StatefulShellBranch(routes: [GoRoute('/review',   builder: ReviewPage)]),
      ],
    ),
  ],
)
```

- `StatefulShellRoute.indexedStack` 保证切换 tab 时页面状态保留
- `DaylineShell` 包含 AppBar + 自定义底部导航栏 `_DiaryNavigationBar`
- 导航栏项来自 `AppRoute` 枚举，通过 `navigationShell.goBranch(index)` 切换
- 不支持深层嵌套路由（当前每个 tab 只有一个页面）

---

## 9. 主题系统

### 9.1 Color Token 体系

```dart
AppColors {
  // 语义色
  seed, primary, primaryDark, primaryPressed,
  primaryContainer, primaryFixed,
  secondary, secondaryContainer,
  accent, tertiary,

  // 表面色
  ink, muted, canvas, surface, surfaceLow, surfaceVariant,
  border, outline, outlineVariant, softShadow,

  // 暗色主题
  darkCanvas, darkSurface, darkInk,

  // 7 种记录类型专用色
  focus, todo, tracker, expense, body, sleep,
}
```

### 9.2 Typography

- Body font: **Manrope**（无衬线，可读性好）
- Display font: **Newsreader**（衬线，温暖、适合日记场景）
- Scale: display=32, headline=24, title=18, body=16, label=14, caption=12

### 9.3 ThemeData 构建

`ThemeData.light()` / `ThemeData.dark()` 通过 `ColorScheme.fromSeed()` 生成基础配色，然后由 `_theme()` 方法统一应用 Material 3 各组件的主题覆盖（AppBar, NavigationBar, Card, InputDecoration, FilledButton, OutlinedButton, TextButton, Chip）。

---

## 10. 测试

### 10.1 测试文件

| 文件 | 类型 | 数量 | 覆盖范围 |
|------|------|------|---------|
| `lui_lite_parser_test.dart` | 单元测试 | 19 | 全部解析类型 + 边界条件 |
| `repositories_test.dart` | 集成测试 | 6 | 所有 Repository CRUD + app_settings |
| `widget_test.dart` | Widget 测试 | 3 | Tab 切换 + 输入保留 + 焦点释放 |
| `ui_redesign_test.dart` | Widget 测试 | 4 | 主题验证 + Tab 顺序 + 各页渲染 |

### 10.2 测试基础设施

- Repository 测试用 `sqflite_common_ffi` + `databaseFactoryFfi` + `inMemoryDatabasePath`，无需真实设备
- Widget 测试用 `ProviderScope` 包裹，可通过 `overrides` 注入 mock
- 解析器测试为纯 Dart 单元测试，无依赖

### 10.3 已知缺口

- 无 Inte gra tion 测试（`integration_test/` 目录不存在）
- What to do 测试未覆盖 `RecordNotifier` 状态转换
- 无错误路径测试（数据库写入失败、解析异常）
- 无性能测试

---

## 11. 导出功能

`ExportService` 提供两种导出：

- **Markdown**: 日记风格的回顾文档，包含日期、摘要、时间线、待办、备忘、专注、消费、身体数据
- **JSON**: 全量结构化数据（dailySummary + records + todos + trackerLogs + focusSessions + expenses + bodyLogs）

文件保存到 sqflite 数据库目录（`getDatabasesPath()`），通过 `exportMarkdownToFile()` / `exportJsonToFile()` 一键导出。

---

## 12. 平台配置

### Android

- 标准 Flutter Android shell
- Impeller 已禁用 (`EnableImpeller = false`)
- `PROCESS_TEXT` Intent 已声明（接收系统"选中文字→分享到Dayline"）
- `MainActivity` 是标准 `FlutterActivity`，无自定义平台通道
- Release 签名使用 debug keystore（占位）

### iOS

- **未配置**。`ios/` 目录不存在，无法构建 iOS 版本。

### Web

- 标准 Flutter web bootstrap，用 `flutter_bootstrap.js`
- manifest.json 已配置 PWA 属性

---

## 13. 未实现（但 UI 预留了接口）

| 功能 | 现状 |
|------|------|
| 语音输入 | `QuickInputBar` 有麦克风图标，无 onPressed |
| 图片附件 | `QuickInputBar` 有图片图标，无 onPressed |
| 定位标记 | `QuickInputBar` 有定位图标，无 onPressed |
| AI 摘要/标签 | `StatusInsightCard` 和 Review 页有 mock 数据 |
| 搜索 | 无 |
| 数据备份/恢复 | 仅有导出，无导入 |
| 隐私模式 | 数据库有计划字段，UI 未做 |
| 多语言 | 全中文硬编码 |
| 云端同步 | 无计划（违反 local-first 原则） |
| 设置页 | `DaylineShell` AppBar 有 settings 图标，无 onPressed |

---

## 14. 代码质量观察

### 14.1 值得保留的模式

- **Feature-first 目录结构**：每个 feature 自包含 page + providers + widgets
- **Riverpod 使用规范**：Provider/NotifierProvider/FutureProvider 使用场景清晰
- **测试数据库注入**：`LocalDatabase(DatabaseFactory)` 支持测试覆盖
- **Token-based 主题**：颜色/间距/字体统一管理，不硬编码值
- **Immutable state**：`RecordState.copyWith` 的 sentinel 模式处理 nullable 字段

### 14.2 值得改进的地方

- **无类型化的 data model**：所有 DB 数据以 `Map<String, Object?>` 传递，编译器无法检查字段拼写或类型。如果要扩展，建议引入 `freezed` 或手写 model class。
- **类型定义重复**：7 种记录类型的 label/icon/color 映射在 `today_cards.dart`, `timeline_list.dart`, `parser_preview_card.dart` 三处重复定义。应该统一到一个地方。
- **SQL 裸写**：当前表不多还好，但后续 Migration 会越来越难管。可考虑迁移到 Drift。
- **无 API 抽象层**：如果要接 AI/语音，建议先定义 `abstract class AiService` 和 `abstract class SpeechService`，页面不要直接依赖具体实现。
- **无错误边界**：FutureProvider 的错误处理在各 widget 里各自 `AsyncValue.when`，没有全局错误处理策略。

---

## 15. 本地开发命令

```bash
# 安装依赖
flutter pub get

# 静态分析
flutter analyze

# 格式化检查
dart format --set-exit-if-changed lib/ test/

# 运行测试（需先 flutter pub get）
flutter test

# 运行指定测试文件
flutter test test/lui_lite_parser_test.dart

# Android debug 构建
flutter build apk --debug

# Web 构建
flutter build web

# 在连接设备上运行
flutter run
```

---

## 16. 后续开发原则

记录在此，帮助新加入的开发者理解项目偏好：

1. **Local-first** — 新功能默认离线可用。网络是增强，不是基础。
2. **Privacy-first** — 任何涉及数据离开本机的功能，必须给用户明确的选择开关，默认关闭。
3. **Raw data never overwritten** — 用户原始输入永远保留。AI 结果单独存储，可删除可重算。
4. **Don't add deps lightly** — 现有技术栈经过选择。引入新依赖前确认没有现有替代方案。
5. **Don't mix refactoring with features** — 修 bug 就修 bug，加功能就加功能，不要混。
6. **Verify before claiming done** — `flutter analyze` + `flutter test` 全绿再报告完成。
7. **Android skills only for android/** — Flutter 业务代码不要用 Android 原生的模式去改。
8. **Export support is mandatory** — 个人数据库类 App 数据导出能力不能少，避免数据锁死。
