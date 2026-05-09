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

  test('primary navigation follows the three-tab order', () {
    expect(AppRoute.values.map((route) => route.label), [
      '线',
      '记',
      '盘',
    ]);
  });

  testWidgets('home screen opens with diary chrome and voice record page', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    // App bar is always present
    expect(find.text('我的日记'), findsOneWidget);
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // Default page is FlashRecordPage with voice button
    expect(find.byIcon(Icons.mic), findsWidgets);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(find.text('时刻准备记录你的灵感'), findsOneWidget);
    expect(find.text('线'), findsOneWidget);
    expect(find.text('记'), findsWidgets);
    expect(find.text('盘'), findsOneWidget);
  });

  testWidgets('dashboard page shows today overview modules', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(reviewSummary: _reviewSummary()));
    await tester.pump(const Duration(milliseconds: 100));

    // Navigate to 盘 tab
    await tester.tap(find.text('盘').first);
    await tester.pump(const Duration(milliseconds: 250));
    await _pumpUntilFound(tester, find.text('分类统计'));

    // Dashboard should contain expected sections
    expect(find.text('分类统计'), findsOneWidget);
    expect(find.text('今日关键词'), findsOneWidget);
    expect(find.text('今日总结'), findsOneWidget);
    expect(find.text('晚间复盘'), findsOneWidget);

    // Evening review prompts
    expect(find.text('今天做得不错的是'), findsOneWidget);
    expect(find.text('今天可以调整的是'), findsOneWidget);
    expect(find.text('明天想关注的是'), findsOneWidget);

    // Export section
    expect(find.text('导出 Markdown'), findsOneWidget);
    expect(find.text('导出 JSON'), findsOneWidget);
  });

  testWidgets('timeline page still accessible via 线 tab', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(reviewSummary: _reviewSummary()));
    await tester.pump(const Duration(milliseconds: 100));

    // Navigate to 线 tab
    await tester.tap(find.text('线').first);
    await tester.pump(const Duration(milliseconds: 250));

    // Timeline page key should be found
    expect(find.byKey(const ValueKey('timeline-page')), findsOneWidget);
  });
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
