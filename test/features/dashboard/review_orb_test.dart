import 'package:liflow_app/features/dashboard/widgets/review_orb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ReviewOrb renders with empty state', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewOrb(
            recordCount: 0,
            hasUnfinishedTodos: false,
            isEvening: false,
            isReviewed: false,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.byType(ReviewOrb), findsOneWidget);
    await tester.tap(find.byType(ReviewOrb));
    expect(tapped, isTrue);
  });

  testWidgets('ReviewOrb shows check icon when reviewed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewOrb(
            recordCount: 10,
            hasUnfinishedTodos: false,
            isEvening: false,
            isReviewed: true,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('ReviewOrb shows todo notch when unfinished todos exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewOrb(
            recordCount: 5,
            hasUnfinishedTodos: true,
            isEvening: false,
            isReviewed: false,
            onTap: () {},
          ),
        ),
      ),
    );

    // Should render with auto_awesome icon and a notch
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
  });

  testWidgets('ReviewOrb breathing animation runs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewOrb(
            recordCount: 8,
            hasUnfinishedTodos: false,
            isEvening: true,
            isReviewed: false,
            onTap: () {},
          ),
        ),
      ),
    );

    // Verify animation controller runs by pumping a few frames
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Orb should still be rendered
    expect(find.byType(ReviewOrb), findsOneWidget);
  });
}
