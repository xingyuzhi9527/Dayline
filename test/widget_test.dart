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
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Record'), findsWidgets);
    expect(find.text('Timeline'), findsWidgets);
    expect(find.text('Review'), findsWidgets);

    await tester.tap(find.text('Record').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('record-page')), findsOneWidget);

    await tester.tap(find.text('Timeline').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline-page')), findsOneWidget);

    await tester.tap(find.text('Review').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-page')), findsOneWidget);

    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('today-page')), findsOneWidget);
  });
}
