import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/theme/app_theme.dart';
import 'package:liflow_app/features/timeline/timeline_page.dart';
import 'package:liflow_app/features/timeline/timeline_providers.dart';

void main() {
  testWidgets(
    'Given a target record, then timeline scroll target has two-cue highlight',
    (tester) async {
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semanticsHandle = tester.ensureSemantics();
      final events = List.generate(43, (index) {
        final isTarget = index == 42;
        return TimelineEvent(
          source: TimelineEventSource.record,
          sourceId: index,
          type: 'memo',
          title: isTarget ? '需要精确定位的记录' : '前置记录 $index',
          description: '10:20',
          timestamp:
              DateTime(2026, 7, 19, 10, 20).millisecondsSinceEpoch + index,
          date: '2026-07-19',
          icon: Icons.notes_rounded,
          tags: const [],
          data: {
            'id': index,
            'content': isTarget ? '需要精确定位的记录' : '前置记录 $index',
            'tags': '[]',
            'metadata': '{}',
          },
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timelineEventsProvider.overrideWith((ref) async => events),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: TimelinePage(
              initialDate: DateTime(2026, 7, 19),
              targetRecordId: 42,
              standalone: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('搜索命中'), findsOneWidget);
      expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('搜索命中的记录')), findsOneWidget);
      final targetRect = tester.getRect(find.text('需要精确定位的记录'));
      expect(targetRect.top, greaterThanOrEqualTo(0));
      expect(targetRect.bottom, lessThanOrEqualTo(800));
      expect(tester.takeException(), isNull);
      semanticsHandle.dispose();
    },
  );
}
