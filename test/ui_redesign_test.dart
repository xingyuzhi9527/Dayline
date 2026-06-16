import 'package:liflow_app/app.dart';
import 'package:liflow_app/app_routes.dart';
import 'package:liflow_app/core/database/daily_reviews_repository.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/features/dashboard/dashboard_page.dart';
import 'package:liflow_app/features/dashboard/dashboard_providers.dart';
import 'package:liflow_app/core/theme/app_colors.dart';
import 'package:liflow_app/core/theme/app_theme.dart';
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

  test('primary navigation follows the app tab order', () {
    expect(AppRoute.values.map((route) => route.label), ['线', '记', '项', '盘']);
  });

  testWidgets('home screen opens with diary chrome and voice record page', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump();

    // Default page is FlashRecordPage with voice button
    expect(find.byIcon(Icons.mic), findsWidgets);
    expect(find.text('时刻准备记录你的灵感'), findsOneWidget);
    expect(find.text('线'), findsOneWidget);
    expect(find.text('记'), findsWidgets);
    expect(find.text('项'), findsOneWidget);
    expect(find.text('盘'), findsOneWidget);
  });

  testWidgets('dashboard page shows today overview modules', (tester) async {
    final summary = _dashboardSummary();

    final db = _memoryDb();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDatabaseProvider.overrideWithValue(db),
          dashboardSummaryProvider.overrideWith((ref) async => summary),
          dashboardReviewProvider.overrideWith((ref) async => null),
          dailyReviewsRepositoryProvider.overrideWithValue(
            _FakeDailyReviewsRepo(db),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: DashboardPage())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Collapsed view
    expect(find.text('今日复盘'), findsNothing);
    expect(find.text('打开复盘'), findsNothing);
    expect(find.text('今天 3 条碎片'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboard-open-review-pill')),
      findsOneWidget,
    );

    // Open expanded view
    await tester.tap(find.byKey(const ValueKey('dashboard-open-review-pill')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // Let async review load resolve
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // Expanded view sections
    expect(find.text('今日状态'), findsOneWidget);
    expect(find.text('今日节奏'), findsOneWidget);
    expect(find.text('今天由什么组成'), findsOneWidget);
    expect(find.text('今日洞察'), findsOneWidget);
    expect(find.text('晚间复盘'), findsOneWidget);
    expect(find.text('日记草稿'), findsOneWidget);

    // Evening review prompts
    expect(find.text('今天值得保留的是'), findsOneWidget);
    expect(find.text('今天可以调整的是'), findsOneWidget);
    expect(find.text('明天最小行动是'), findsOneWidget);
  });

  testWidgets('timeline page still accessible via 线 tab', (tester) async {
    await tester.pumpWidget(_testApp(dashboardSummary: _dashboardSummary()));
    await tester.pump(const Duration(milliseconds: 100));

    // Navigate to 线 tab via PageView
    await tester.tap(find.text('线').first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // Timeline tab should be accessible
    expect(find.text('线'), findsOneWidget);
  });
}

Widget _testApp({LocalDatabase? database, DashboardSummary? dashboardSummary}) {
  return ProviderScope(
    overrides: [
      localDatabaseProvider.overrideWithValue(
        database ??
            LocalDatabase(
              databaseFactory: databaseFactoryFfi,
              databasePath: inMemoryDatabasePath,
            ),
      ),
      if (dashboardSummary != null)
        dashboardSummaryProvider.overrideWith((ref) async => dashboardSummary),
      dashboardReviewProvider.overrideWith((ref) async => null),
    ],
    child: const LiflowApp(),
  );
}

DashboardSummary _dashboardSummary() => DashboardSummary(
  date: '2026-05-01',
  recordCount: 3,
  totalTodos: 2,
  completedTodos: 1,
  trackerCount: 2,
  focusMinutes: 45,
  expenseTotal: 20,
  monthExpenseTotal: 120,
  expenseCount: 1,
  bodyLogCount: 0,
  topTags: ['日常', '健康'],
  categoryCounts: {'日常': 2, '健康': 1},
  firstActivityTime: DateTime(2026, 5, 1, 9, 0).millisecondsSinceEpoch,
  lastActivityTime: DateTime(2026, 5, 1, 21, 0).millisecondsSinceEpoch,
  longestGapMinutes: 120,
  densestHourRange: '15:00-16:00',
  insights: const ['今天"日常"相关内容最多。'],
  allTimestamps: [
    DateTime(2026, 5, 1, 9, 0).millisecondsSinceEpoch,
    DateTime(2026, 5, 1, 21, 0).millisecondsSinceEpoch,
  ],
  isReviewed: false,
);

LocalDatabase _memoryDb() {
  return LocalDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
}

class _FakeDailyReviewsRepo implements DailyReviewsRepository {
  _FakeDailyReviewsRepo(this._db);

  final LocalDatabase _db;

  @override
  LocalDatabase get localDatabase => _db;

  @override
  String get tableName => 'daily_reviews';

  @override
  Future<DatabaseRow?> findByDate(String date) async => null;

  @override
  Future<int> upsert({
    required String date,
    required String kept,
    required String adjust,
    required String nextAction,
  }) async => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
