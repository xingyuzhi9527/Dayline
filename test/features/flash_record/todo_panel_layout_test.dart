import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liflow_app/features/flash_record/flash_record_page.dart';

void main() {
  testWidgets('expanded panel reserves extra room for the timeline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayTodoPanelEventsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(home: Scaffold(body: FlashRecordPage())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    final pill = find.byKey(const ValueKey('collapsed-intent-pill'));
    expect(pill, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(pill));
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(0, -18));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final sheet = tester.getRect(
      find.byKey(const ValueKey('todo-panel-bottom-sheet')),
    );
    final timeline = tester.getRect(
      find.byKey(const ValueKey('todo-panel-daily-column')),
    );
    final todos = tester.getRect(
      find.byKey(const ValueKey('todo-panel-todo-column')),
    );

    expect(sheet.bottom, closeTo(tester.view.physicalSize.height / 3, 2));
    expect(timeline.height, greaterThan(0));
    expect(todos.height, greaterThan(0));
    expect(todos.bottom, lessThanOrEqualTo(sheet.bottom));
  });
}
