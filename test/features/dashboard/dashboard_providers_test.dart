import 'package:liflow_app/core/database/daily_reviews_repository.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/features/dashboard/dashboard_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

LocalDatabase _memoryDatabase() {
  return LocalDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('DashboardSummary', () {
    test('hasData returns false when empty', () {
      const summary = DashboardSummary(
        date: '2026-05-13',
        recordCount: 0,
        totalTodos: 0,
        completedTodos: 0,
        trackerCount: 0,
        focusMinutes: 0,
        expenseTotal: 0,
        monthExpenseTotal: 0,
        expenseCount: 0,
        bodyLogCount: 0,
        topTags: [],
        categoryCounts: {},
        firstActivityTime: null,
        lastActivityTime: null,
        longestGapMinutes: 0,
        densestHourRange: '-',
        insights: [],
        allTimestamps: [],
        isReviewed: false,
      );

      expect(summary.hasData, isFalse);
      expect(summary.hasUnfinishedTodos, isFalse);
    });

    test('hasData returns true with records', () {
      const summary = DashboardSummary(
        date: '2026-05-13',
        recordCount: 5,
        totalTodos: 3,
        completedTodos: 1,
        trackerCount: 0,
        focusMinutes: 0,
        expenseTotal: 0,
        monthExpenseTotal: 0,
        expenseCount: 0,
        bodyLogCount: 0,
        topTags: ['运动'],
        categoryCounts: {'运动': 3},
        firstActivityTime: 1700000000000,
        lastActivityTime: 1700000100000,
        longestGapMinutes: 30,
        densestHourRange: '15:00-16:00',
        insights: ['今天"运动"相关内容最多。'],
        allTimestamps: [1700000000000, 1700000100000],
        isReviewed: false,
      );

      expect(summary.hasData, isTrue);
      expect(summary.hasUnfinishedTodos, isTrue);
    });

    test('hasUnfinishedTodos returns false when all completed', () {
      const summary = DashboardSummary(
        date: '2026-05-13',
        recordCount: 0,
        totalTodos: 5,
        completedTodos: 5,
        trackerCount: 0,
        focusMinutes: 0,
        expenseTotal: 0,
        monthExpenseTotal: 0,
        expenseCount: 0,
        bodyLogCount: 0,
        topTags: [],
        categoryCounts: {},
        firstActivityTime: null,
        lastActivityTime: null,
        longestGapMinutes: 0,
        densestHourRange: '-',
        insights: [],
        allTimestamps: [],
        isReviewed: false,
      );

      expect(summary.hasUnfinishedTodos, isFalse);
    });
  });

  group('Dashboard providers', () {
    test(
      'dashboardSummaryProvider returns empty summary when no data',
      () async {
        final db = _memoryDatabase();
        final container = ProviderContainer(
          overrides: [localDatabaseProvider.overrideWithValue(db)],
        );

        final summary = await container.read(dashboardSummaryProvider.future);

        expect(summary.hasData, isFalse);
        expect(summary.recordCount, 0);
        expect(summary.topTags, isEmpty);
        expect(summary.insights, isEmpty);
        expect(summary.isReviewed, isFalse);

        container.dispose();
      },
    );

    test('dashboardSummaryProvider aggregates real data', () async {
      final db = _memoryDatabase();
      final container = ProviderContainer(
        overrides: [localDatabaseProvider.overrideWithValue(db)],
      );

      final now = DateTime.now();
      final recordsRepo = container.read(recordsRepositoryProvider);
      await recordsRepo.create(
        date: now,
        type: 'memo',
        content: '跑步30分钟',
        tags: ['运动', '健康'],
      );
      await recordsRepo.create(
        date: now,
        type: 'memo',
        content: '写代码',
        tags: ['工作'],
      );

      final todosRepo = container.read(todosRepositoryProvider);
      await todosRepo.create(date: now, title: '交报告');

      final summary = await container.read(dashboardSummaryProvider.future);

      expect(summary.hasData, isTrue);
      expect(summary.recordCount, 2);
      expect(summary.totalTodos, 1);
      expect(summary.completedTodos, 0);
      expect(summary.topTags, contains('运动'));
      expect(summary.isReviewed, isFalse);

      container.dispose();
    });

    test(
      'dashboardSummaryForDateProvider labels yesterday insights correctly',
      () async {
        final db = _memoryDatabase();
        final container = ProviderContainer(
          overrides: [localDatabaseProvider.overrideWithValue(db)],
        );

        final today = DateTime.now();
        final yesterday = DateTime(
          today.year,
          today.month,
          today.day,
        ).subtract(const Duration(days: 1));
        final recordsRepo = container.read(recordsRepositoryProvider);
        for (var i = 0; i < 3; i++) {
          await recordsRepo.create(
            date: yesterday,
            type: 'memo',
            content: '复盘 $i',
            tags: ['复盘'],
            createdAt: yesterday.add(Duration(hours: 8 + i)),
          );
        }

        final summary = await container.read(
          dashboardSummaryForDateProvider(yesterday).future,
        );

        expect(summary.date, dateKey(yesterday));
        expect(summary.insights, isNotEmpty);
        expect(summary.insights.join('\n'), contains('昨天'));
        expect(summary.insights.join('\n'), isNot(contains('今天')));

        container.dispose();
      },
    );

    test(
      'dashboardReviewProvider returns null when no review exists',
      () async {
        final db = _memoryDatabase();
        final container = ProviderContainer(
          overrides: [localDatabaseProvider.overrideWithValue(db)],
        );

        final review = await container.read(dashboardReviewProvider.future);
        expect(review, isNull);

        container.dispose();
      },
    );

    test('DailyReviewsRepository upsert creates and updates', () async {
      final db = _memoryDatabase();
      // Ensure schema is created
      await db.database;
      final repo = DailyReviewsRepository(db);

      // First upsert: creates
      await repo.upsert(
        date: '2026-05-13',
        kept: '跑步',
        adjust: '睡太晚',
        nextAction: '早睡',
      );

      var found = await repo.findByDate('2026-05-13');
      expect(found, isNotNull);
      expect(found!['kept'], '跑步');

      // Second upsert: updates
      await repo.upsert(
        date: '2026-05-13',
        kept: '学习',
        adjust: '效率低',
        nextAction: '早睡',
      );

      found = await repo.findByDate('2026-05-13');
      expect(found!['kept'], '学习');
    });
  });
}
