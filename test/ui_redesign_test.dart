import 'package:dayline_app/app.dart';
import 'package:dayline_app/app_routes.dart';
import 'package:dayline_app/core/database/local_database.dart';
import 'package:dayline_app/features/review/review_providers.dart';
import 'package:dayline_app/core/theme/app_colors.dart';
import 'package:dayline_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('Serene Log theme uses the redesigned paper surfaces', () {
    final theme = AppTheme.light();
    final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;

    expect(theme.scaffoldBackgroundColor, AppColors.canvas);
    expect(theme.colorScheme.primary, const Color(0xFF2F6F73));
    expect(theme.cardTheme.color, AppColors.surface);
    expect(cardShape.borderRadius, BorderRadius.circular(20));
  });

  test('primary navigation follows the redesigned tab order', () {
    expect(AppRoute.values.map((route) => route.label), [
      '今日',
      '时间线',
      '记录',
      '复盘',
    ]);
  });

  testWidgets('home screen opens with redesigned diary chrome and Today hero', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('我的日记'), findsOneWidget);
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.text('早上好，探索者'), findsOneWidget);
    expect(find.text('连续记录 4 天'), findsOneWidget);
    expect(find.text('状态洞察'), findsOneWidget);
  });

  testWidgets('record parsing preview uses the bento confirmation layout', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('记录').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '9:30 跑步 30分钟 #健康');
    await tester.pump();
    await tester.tap(find.text('整理'));
    await tester.pumpAndSettle();

    expect(find.text('原始记录'), findsOneWidget);
    expect(find.text('"9:30 跑步 30分钟 #健康"'), findsOneWidget);
    expect(find.text('类别'), findsOneWidget);
    expect(find.text('时间'), findsOneWidget);
    expect(find.text('时长'), findsOneWidget);
    expect(find.text('标签'), findsOneWidget);
    expect(find.text('30 分钟'), findsOneWidget);
    expect(find.text('#健康'), findsWidgets);
  });

  testWidgets(
    'review page keeps one scroll surface and reaches export actions',
    (tester) async {
      await tester.pumpWidget(_testApp(reviewSummary: _reviewSummary()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('复盘').last);
      await tester.pump(const Duration(milliseconds: 250));
      await _pumpUntilFound(tester, find.text('今日复盘'));

      expect(find.byType(Scrollable), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('导出 Markdown'),
        400,
        scrollable: find.byType(Scrollable),
        maxScrolls: 8,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('导出 Markdown'), findsOneWidget);
      expect(find.text('导出 JSON'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  expect(finder, findsOneWidget);
}

Widget _testApp({LocalDatabase? database, DailySummary? reviewSummary}) {
  return ProviderScope(
    overrides: [
      localDatabaseProvider.overrideWithValue(
        database ??
            LocalDatabase(
              databaseFactory: databaseFactoryFfi,
              databasePath: inMemoryDatabasePath,
            ),
      ),
      if (reviewSummary != null)
        dailySummaryProvider.overrideWith((ref) async => reviewSummary),
    ],
    child: const DaylineApp(),
  );
}

DailySummary _reviewSummary() => const DailySummary(
  date: '2026-05-01',
  recordCount: 3,
  totalTodos: 2,
  completedTodos: 1,
  trackerCount: 2,
  focusMinutes: 45,
  expenseTotal: 20,
  topTags: ['日常', '健康'],
  activeHourRange: '09:00 - 21:00',
  summaryText: '今天共记录 3 条内容，完成 1/2 个待办，打卡 2 次，专注 45 分钟。',
);
