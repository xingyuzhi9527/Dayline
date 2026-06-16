import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/features/monthly_expenses/monthly_expense_providers.dart';
import 'package:liflow_app/features/monthly_expenses/monthly_expense_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows monthly totals and navigates to previous month', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyExpenseSummaryProvider.overrideWith((ref, month) async {
            if (month.year == 2026 && month.month == 5) {
              return MonthlyExpenseSummary(
                month: month,
                monthKey: '2026-05',
                total: 120,
                count: 1,
                dailyAverage: 120 / 31,
                categoryTotals: const [
                  MonthlyExpenseBucket(label: '购物', amount: 120),
                ],
                dailyTotals: const [
                  MonthlyExpenseDayTotal(date: '2026-05-01', amount: 120),
                ],
                highestDay: const MonthlyExpenseDayTotal(
                  date: '2026-05-01',
                  amount: 120,
                ),
                expenses: [
                  {
                    'date': '2026-05-01',
                    'category': '购物',
                    'amount': 120.0,
                    'note': null,
                  },
                ],
              );
            }

            return MonthlyExpenseSummary(
              month: month,
              monthKey: '2026-06',
              total: 80,
              count: 2,
              dailyAverage: 80 / 30,
              categoryTotals: const [
                MonthlyExpenseBucket(label: '餐饮', amount: 35),
                MonthlyExpenseBucket(label: '交通', amount: 45),
              ],
              dailyTotals: const [
                MonthlyExpenseDayTotal(date: '2026-06-01', amount: 35),
                MonthlyExpenseDayTotal(date: '2026-06-02', amount: 45),
              ],
              highestDay: const MonthlyExpenseDayTotal(
                date: '2026-06-02',
                amount: 45,
              ),
              expenses: [
                {
                  'date': '2026-06-01',
                  'category': '餐饮',
                  'amount': 35.0,
                  'note': '午饭',
                },
                {
                  'date': '2026-06-02',
                  'category': '交通',
                  'amount': 45.0,
                  'note': null,
                },
              ],
            );
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MonthlyExpenseSection(initialMonth: DateTime(2026, 6)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('月账单'), findsOneWidget);
    expect(find.text('2026-06'), findsOneWidget);
    expect(find.text('¥80.0'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('最高消费日 06-02，¥45.0'), findsOneWidget);
    expect(find.text('查看月账单 MD'), findsOneWidget);
    expect(find.text('餐饮 ¥35.0'), findsNothing);
    expect(find.text('交通 ¥45.0'), findsNothing);
    expect(find.text('餐饮，午饭'), findsNothing);
    expect(find.text('交通'), findsNothing);

    await tester.tap(find.byTooltip('上个月'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('2026-05'), findsOneWidget);
    expect(find.text('¥120.0'), findsWidgets);
    expect(find.text('最高消费日 05-01，¥120.0'), findsOneWidget);
    expect(find.text('查看月账单 MD'), findsOneWidget);
    expect(find.text('购物 ¥120.0'), findsNothing);
  });
}
