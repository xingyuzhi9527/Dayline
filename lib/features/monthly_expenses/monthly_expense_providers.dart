import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repositories.dart';
import '../../core/database/repository_providers.dart';

class MonthlyExpenseBucket {
  const MonthlyExpenseBucket({required this.label, required this.amount});

  final String label;
  final double amount;
}

class MonthlyExpenseDayTotal {
  const MonthlyExpenseDayTotal({required this.date, required this.amount});

  final String date;
  final double amount;
}

class MonthlyExpenseSummary {
  const MonthlyExpenseSummary({
    required this.month,
    required this.monthKey,
    required this.total,
    required this.count,
    required this.dailyAverage,
    required this.categoryTotals,
    required this.dailyTotals,
    required this.highestDay,
    required this.expenses,
  });

  final DateTime month;
  final String monthKey;
  final double total;
  final int count;
  final double dailyAverage;
  final List<MonthlyExpenseBucket> categoryTotals;
  final List<MonthlyExpenseDayTotal> dailyTotals;
  final MonthlyExpenseDayTotal? highestDay;
  final List<DatabaseRow> expenses;

  bool get hasData => count > 0;
}

final monthlyExpenseSummaryProvider =
    FutureProvider.family<MonthlyExpenseSummary, DateTime>((ref, date) async {
      ref.watch(dataVersionProvider);
      final month = DateTime(date.year, date.month);
      final repo = ref.read(expensesRepositoryProvider);
      final expenses = await repo.findByMonth(month);
      final categoryTotals = await repo.sumAmountByCategoryForMonth(month);
      final dailyTotals = await repo.sumAmountByDayForMonth(month);
      final total = await repo.sumAmountByMonth(month);
      final dayCount = DateTime(month.year, month.month + 1, 0).day;
      final sortedDailyTotals = dailyTotals.entries
          .map(
            (entry) =>
                MonthlyExpenseDayTotal(date: entry.key, amount: entry.value),
          )
          .toList();
      final highestDay = sortedDailyTotals.isEmpty
          ? null
          : sortedDailyTotals.reduce((a, b) {
              if (a.amount == b.amount) {
                return a.date.compareTo(b.date) <= 0 ? a : b;
              }
              return a.amount > b.amount ? a : b;
            });

      return MonthlyExpenseSummary(
        month: month,
        monthKey: _monthKey(month),
        total: total,
        count: expenses.length,
        dailyAverage: dayCount == 0 ? 0 : total / dayCount,
        categoryTotals: categoryTotals.entries
            .map(
              (entry) =>
                  MonthlyExpenseBucket(label: entry.key, amount: entry.value),
            )
            .toList(),
        dailyTotals: sortedDailyTotals,
        highestDay: highestDay,
        expenses: expenses,
      );
    });

String monthlyExpenseMonthKey(DateTime date) =>
    _monthKey(DateTime(date.year, date.month));

String _monthKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  return '${date.year}-$month';
}
