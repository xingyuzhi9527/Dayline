---
name: flutter-riverpod-patterns
description: Flutter Riverpod 实战模式与反模式。用于编写、审查或重构使用 Riverpod 状态管理的 Flutter 代码。覆盖：Riverpod, Provider, NotifierProvider, FutureProvider, ref.watch, ref.read, 状态管理, DataVersionNotifier, 哨兵模式, copyWith, 测试注入, ProviderScope, feature-first, 主题token。
---

# Flutter Riverpod 实战模式与反模式

从真实 Flutter 项目中提炼的 Riverpod 使用模式、常见错误和最佳实践。

## 快速上手：Provider 选型

| 场景 | 用什么 | 示例 |
|------|--------|------|
| 单例服务/配置 | `Provider<T>` | `localDatabaseProvider` |
| 可变状态 + 业务逻辑 | `NotifierProvider<T>` | `flashRecordProvider` |
| 异步只读数据 | `FutureProvider<T>` | `timelineEventsProvider` |
| 参数化异步数据 | `FutureProvider.family<T, P>` | `dashboardForDateProvider(date)` |
| 流式数据 | `StreamProvider<T>` | WebSocket 消息 |

## 常见陷阱

### 陷阱 1：build 中使用 ref.read

**症状**：Provider 变化后 Widget 不重建

**根因**：`ref.read()` 是一次性读取，不会建立依赖关系。

```dart
// 错误 ❌
@override
Widget build(BuildContext context) {
  final data = ref.read(someProvider);  // 不会响应变化
  return Text(data.toString());
}

// 正确 ✅
@override
Widget build(BuildContext context) {
  final data = ref.watch(someProvider);  // 建立依赖，自动重建
  return Text(data.toString());
}
```

**规则**：
- `ref.watch` — 在 `build()` 方法中响应式订阅
- `ref.read` — 在事件回调、生命周期方法中一次性获取
- `ref.listen` — 监听变化执行副作用（如弹 toast、导航）

### 陷阱 2：FutureProvider 中放可变状态

**问题**：`FutureProvider` 用于异步只读数据，如果内部状态需要被修改，必须改用 `NotifierProvider`。

```dart
// 错误 ❌ — 试图修改 FutureProvider 的数据
ref.read(timelineEventsProvider.notifier).update(events);

// 正确 ✅ — 用 NotifierProvider 管理可变状态
@immutable
class FlashRecordState { ... }

class FlashRecordNotifier extends Notifier<FlashRecordState> {
  void startListening() { ... }
  void confirmParsed() { ... }
}
```

### 陷阱 3：DataVersionNotifier 导致不必要的重建

**模式说明**：`DataVersionNotifier` 是一个自增的 `int` 计数器。任何数据变更后 +1，所有 FutureProvider watch 它来自动刷新。

```dart
// 定义
final dataVersionProvider = NotifierProvider<DataVersionNotifier, int>(
  DataVersionNotifier.new,
);

class DataVersionNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void increment() => state = state + 1;
}

// 消费方
final recordsProvider = FutureProvider<List<Record>>((ref) async {
  ref.watch(dataVersionProvider);     // ← 依赖版本号
  return ref.read(recordsRepo).findAll();
});

// 写入方
Future<void> saveRecord(Record r) async {
  await ref.read(recordsRepo).insert(r);
  ref.read(dataVersionProvider.notifier).increment();  // ← 触发全局刷新
}
```

**权衡**：
- 优点：实现简单，不会遗漏刷新
- 缺点：N+1 查询 — 任何数据变更都会触发所有 watch 它的 Provider 重新查询
- 替代方案：对关键 Provider 使用 `ref.invalidate(recordsProvider)` 精确失效

**选择建议**：
- 数据量小（< 1000 条）、Provider 数量少（< 10 个）→ DataVersionNotifier
- 数据量大、Provider 多 → `ref.invalidate` 精确失效

### 陷阱 4：跨 feature 直接引用

**问题**：Feature A 的 Widget 直接 import Feature B 的内部文件。

```dart
// 错误 ❌ — 跨 feature 耦合
import 'package:myapp/features/timeline/timeline_providers.dart';

// 正确 ✅ — 通过共享 Provider 通信
// 把 timelineEventsProvider 放在 core/ 或通过 Provider 暴露接口
```

### 陷阱 5：过度拆分 Provider

每个变量一个 Provider 会导致 Provider 数量爆炸。

```dart
// 不推荐 ❌ — 过度拆分
final isLoadingProvider = Provider<bool>((ref) => ...);
final errorMessageProvider = Provider<String?>((ref) => ...);
final dataProvider = Provider<Data?>((ref) => ...);

// 推荐 ✅ — 用状态对象封装
@immutable
class PageState {
  final bool isLoading;
  final String? errorMessage;
  final Data? data;
  // ...
}

final pageStateProvider = NotifierProvider<PageNotifier, PageState>(...);
```

## copyWith 哨兵模式

**问题**：如何区分 "将 nullable 字段设为 null" 和 "不修改这个字段"？

```dart
class RecordState {
  final String? parsedText;
  final String? error;

  RecordState copyWith({
    Object? parsedText = _unchanged,  // 用哨兵区分
    Object? error = _unchanged,
  }) {
    return RecordState(
      parsedText: identical(parsedText, _unchanged)
          ? this.parsedText
          : parsedText as String?,
      error: identical(error, _unchanged)
          ? this.error
          : error as String?,
    );
  }

  static const _unchanged = Object();  // 唯一哨兵实例
}
```

**关键点**：
- 哨兵是 `Object()`，用 `identical()` 而非 `==` 判断（保证引用唯一性）
- 哨兵值不会被任何合法的业务值匹配
- 比 `copyWith({String? Function()? parsedText})` 简洁

## 测试注入模式

### 替换数据库

```dart
testWidgets('显示记录列表', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localDatabaseProvider.overrideWithValue(
          LocalDatabase(factory: databaseFactoryFfi),
        ),
      ],
      child: const MyApp(),
    ),
  );
});
```

### 替换 STT 引擎

```dart
testWidgets('语音识别流程', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sttEngineProvider.overrideWithValue(DebugSttEngine()),
      ],
      child: const MyApp(),
    ),
  );
});
```

### 测试 Notifier 状态转移

```dart
test('保存后重置状态', () {
  final container = createContainer();
  final notifier = container.read(flashRecordProvider.notifier);

  notifier.setParsedText('跑步三十分钟');
  notifier.confirmParsed();

  final state = container.read(flashRecordProvider);
  expect(state.parsedText, isNull);   // 已重置
  expect(state.isReady, isTrue);      // STT 状态保留
});
```

## Feature-First 目录结构

```
lib/
  main.dart               # 入口: ProviderScope + runApp
  app.dart                 # MaterialApp.router
  app_router.dart          # GoRouter 路由配置

  core/                    # 共享基础设施（不依赖任何 feature）
    database/              # 数据库 + Repository + Provider
    theme/                 # AppColors, AppSpacing, AppTypography
    parser/                # 通用解析器
    stt/                   # 语音识别抽象层 + 实现
    markdown/              # Markdown 文件服务
    export/                # 导出服务

  features/                # 功能模块（每个自包含）
    flash_record/          # 功能页面
      application/         # Notifier + State
      presentation/        # Page Widget
      widgets/             # 功能专属组件
    timeline/
      timeline_page.dart
      timeline_providers.dart
      widgets/

  shell/                   # App Shell（导航框架）
```

**规则**：
1. `lib/core/` 可以 import 第三方包和自身，但不能 import `lib/features/`
2. `lib/features/<name>/` 可以 import `lib/core/`，但不能 import 其他 feature
3. Feature 之间通过 `core/` 中的 Provider 间接通信

## 主题 Token 化

```dart
// 不在 Widget 中直接写硬编码颜色
Container(color: Color(0xFF2F6F73))  // ❌

// 用语义化 token
Container(color: AppColors.primary)   // ✅
Container(color: AppColors.surface)   // ✅

// Token 定义
class AppColors {
  static const primary = Color(0xFF2F6F73);
  static const surface = Color(0xFFF8FAFB);
  static const ink = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B7280);
  // 按记录类型加语义色
  static const todoTint = Color(0xFF...);
  static const expenseTint = Color(0xFF...);
}

class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 40.0;
  static const xxl = 48.0;
}

class AppTypography {
  static const body = TextStyle(fontFamily: 'Manrope', fontSize: 14, ...);
  static const display = TextStyle(fontFamily: 'Newsreader', fontSize: 32, ...);
}
```

**Material 3 集成**：

```dart
ThemeData _buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    appBarTheme: AppBarTheme(...),
    cardTheme: CardTheme(...),
    inputDecorationTheme: InputDecorationTheme(...),
    // 用 copyWith 覆盖组件主题
  );
}
```

## 反模式清单

| 反模式 | 问题 | 正确做法 |
|--------|------|---------|
| `ref.read` 在 `build()` 中 | 不响应变化 | 用 `ref.watch` |
| `FutureProvider` 中放可变状态 | 设计违背 | 用 `NotifierProvider` |
| 跨 feature import 内部文件 | 紧耦合 | 用 shared Provider |
| 一个变量一个 Provider | 碎片化 | 用状态对象封装 |
| 硬编码颜色/间距值 | 不可维护 | 用 Theme token |
| 在 Provider 中做耗时操作 | 阻塞初始化 | 异步初始化 + loading 状态 |
| 忘记 `ref.onDispose` | 资源泄漏 | 清理 timer/stream/listener |
| 大重构 + 新功能一起做 | 高风险 | 一次只做一件事 |
