import 'package:dayline_app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts on Today and switches between all primary tabs', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: DaylineApp()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('today-page')), findsOneWidget);
    expect(find.text('今日'), findsWidgets);
    expect(find.text('记录'), findsWidgets);
    expect(find.text('时间线'), findsWidgets);
    expect(find.text('复盘'), findsWidgets);

    await tester.tap(find.text('记录').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('record-page')), findsOneWidget);

    await tester.tap(find.text('时间线').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline-page')), findsOneWidget);

    await tester.tap(find.text('复盘').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-page')), findsOneWidget);

    await tester.tap(find.text('今日').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('today-page')), findsOneWidget);
  });

  testWidgets('record input keeps typed text before submitting', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: DaylineApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('记录').last);
    await tester.pumpAndSettle();

    final input = find.byType(TextField).first;
    await tester.enterText(input, '9点半 跑步 30分钟 #健康');
    await tester.pump();

    expect(find.text('9点半 跑步 30分钟 #健康'), findsOneWidget);

    await tester.pump();
    expect(find.text('9点半 跑步 30分钟 #健康'), findsOneWidget);
  });
}
