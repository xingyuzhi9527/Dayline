import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/features/monthly_expenses/monthly_expense_providers.dart';
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

  test(
    'monthlyExpenseSummaryProvider aggregates one month of expenses',
    () async {
      final db = _memoryDatabase();
      final container = ProviderContainer(
        overrides: [localDatabaseProvider.overrideWithValue(db)],
      );

      final repo = container.read(expensesRepositoryProvider);
      await repo.create(
        date: DateTime(2026, 6, 1),
        amount: 35,
        category: '餐饮',
        note: '午饭',
        createdAt: DateTime(2026, 6, 1, 12),
      );
      await repo.create(
        date: DateTime(2026, 6, 2),
        amount: 45,
        category: '交通',
        createdAt: DateTime(2026, 6, 2, 9),
      );
      await repo.create(
        date: DateTime(2026, 6, 2),
        amount: 18,
        category: '餐饮',
        createdAt: DateTime(2026, 6, 2, 15),
      );
      await repo.create(
        date: DateTime(2026, 7, 1),
        amount: 999,
        category: '忽略',
      );

      final summary = await container.read(
        monthlyExpenseSummaryProvider(DateTime(2026, 6, 16)).future,
      );

      expect(summary.monthKey, '2026-06');
      expect(summary.total, 98);
      expect(summary.count, 3);
      expect(summary.dailyAverage, 98 / 30);
      expect(summary.highestDay?.date, '2026-06-02');
      expect(summary.highestDay?.amount, 63);
      expect(summary.categoryTotals.map((item) => item.label), ['餐饮', '交通']);
      expect(summary.categoryTotals.map((item) => item.amount), [53.0, 45.0]);
      expect(summary.expenses.map((row) => row['category']), [
        '餐饮',
        '交通',
        '餐饮',
      ]);

      container.dispose();
      await db.close();
    },
  );

  test('monthlyExpenseSummaryProvider returns empty summary', () async {
    final db = _memoryDatabase();
    final container = ProviderContainer(
      overrides: [localDatabaseProvider.overrideWithValue(db)],
    );

    final summary = await container.read(
      monthlyExpenseSummaryProvider(DateTime(2026, 2, 1)).future,
    );

    expect(summary.monthKey, '2026-02');
    expect(summary.total, 0);
    expect(summary.count, 0);
    expect(summary.dailyAverage, 0);
    expect(summary.highestDay, isNull);
    expect(summary.categoryTotals, isEmpty);
    expect(summary.dailyTotals, isEmpty);
    expect(summary.expenses, isEmpty);

    container.dispose();
    await db.close();
  });
}
