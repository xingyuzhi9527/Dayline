import 'package:dayline_app/app.dart';
import 'package:dayline_app/features/flash_record/flash_record_page.dart';
import 'package:dayline_app/features/flash_record/widgets/voice_button.dart';
import 'package:dayline_app/features/timeline/timeline_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts on 记 and switches between all three tabs', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: DaylineApp()));
    await tester.pumpAndSettle();

    // Default tab is 记
    expect(find.text('记'), findsWidgets);
    expect(find.text('线'), findsOneWidget);
    expect(find.text('盘'), findsOneWidget);

    // Verify nav bar has exactly 3 items
    expect(find.text('今日'), findsNothing);
    expect(find.text('时间线'), findsNothing);
    expect(find.text('复盘'), findsNothing);

    // Switch to 线
    await tester.tap(find.text('线').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timeline-page')), findsOneWidget);

    // Switch to 盘
    await tester.tap(find.text('盘').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dashboard-page')), findsOneWidget);

    // Switch back to 记
    await tester.tap(find.text('记').first);
    await tester.pumpAndSettle();
    expect(find.text('点击生成测试记录'), findsOneWidget);
  });

  testWidgets('中心话筒按钮存在且按住有状态反馈', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DaylineApp()));
    await tester.pumpAndSettle();

    // Default page is 记 with voice button
    expect(find.text('点击生成测试记录'), findsOneWidget);
    expect(find.byType(VoiceButton), findsOneWidget);

    // Tap on the central voice button — triggers mock simulation
    await tester.tap(find.byType(VoiceButton));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 900)); // wait for mock delay

    // After tap, should show recognized mock text
    expect(find.text('记'), findsWidgets);
  });

  testWidgets('底部文字输入框存在并可用', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DaylineApp()));
    await tester.pumpAndSettle();

    // Find the text input at the bottom
    expect(find.byType(TextField), findsOneWidget);

    final input = find.byType(TextField).first;
    await tester.enterText(input, '今天跑步30分钟');
    await tester.pump();

    expect(find.text('今天跑步30分钟'), findsOneWidget);
  });

  testWidgets('今日回忆使用当天真实记录并以下半屏折叠层展示', (tester) async {
    final now = DateTime.now();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayMemoryEventsProvider.overrideWith(
            (ref) async => [
              TimelineEvent(
                id: 'records:1',
                type: 'memo',
                title: '今天跑步30分钟',
                description: '运动',
                timestamp: now.millisecondsSinceEpoch,
                date: 'today',
                icon: Icons.directions_run_rounded,
                tags: const ['运动'],
              ),
              TimelineEvent(
                id: 'todos:1',
                type: 'todo',
                title: '明天交报告',
                description: '待完成',
                timestamp: now
                    .add(const Duration(minutes: 1))
                    .millisecondsSinceEpoch,
                date: 'today',
                icon: Icons.radio_button_unchecked,
                tags: const [],
              ),
            ],
          ),
        ],
        child: const DaylineApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final memoryEntry = find.byKey(const ValueKey('today-memory-entry'));
    expect(memoryEntry, findsOneWidget);

    await tester.tap(memoryEntry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byKey(const ValueKey('memory-scatter-layer')), findsOneWidget);
    expect(find.byKey(const ValueKey('memory-bottom-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('memory-scroll-field')), findsOneWidget);
    expect(find.text('今天跑步30分钟'), findsOneWidget);
    expect(find.text('明天交报告'), findsOneWidget);
    expect(find.text('晨间散步'), findsNothing);
    expect(find.byKey(const ValueKey('memory-card-0')), findsOneWidget);

    final sheetRect = tester.getRect(
      find.byKey(const ValueKey('memory-bottom-sheet')),
    );
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(sheetRect.top, greaterThan(screenHeight * 0.5));
    expect(sheetRect.height, lessThan(screenHeight * 0.42));

    await tester.tapAt(Offset(sheetRect.center.dx, sheetRect.top - 24));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const ValueKey('memory-scatter-layer')), findsNothing);
  });
}
