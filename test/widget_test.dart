import 'package:dayline_app/app.dart';
import 'package:dayline_app/core/database/local_database.dart';
import 'package:dayline_app/core/database/repository_providers.dart';
import 'package:dayline_app/core/database/repositories.dart';
import 'package:dayline_app/features/flash_record/flash_record_page.dart';
import 'package:dayline_app/features/flash_record/widgets/voice_button.dart';
import 'package:dayline_app/features/timeline/timeline_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('starts on 记 and switches between all three tabs', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: DaylineApp()));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1100));
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
    expect(find.text('时刻准备记录你的灵感'), findsOneWidget);
  });

  testWidgets('中心话筒按钮存在且按住有状态反馈', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DaylineApp()));
    await tester.pumpAndSettle();

    // Default page is 记 with voice button
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(find.text('时刻准备记录你的灵感'), findsOneWidget);
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

  testWidgets('待办的事情使用当天真实记录并以双栏折叠层展示', (tester) async {
    final now = DateTime.now();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayTodoPanelEventsProvider.overrideWith(
            (ref) async => [
              TimelineEvent(
                source: TimelineEventSource.record,
                sourceId: 1,
                type: 'memo',
                title: '今天跑步30分钟',
                description: '运动',
                timestamp: now.millisecondsSinceEpoch,
                date: 'today',
                icon: Icons.directions_run_rounded,
                tags: const ['运动'],
                data: const {'id': 1, 'content': '今天跑步30分钟', 'tags': '["运动"]'},
              ),
              TimelineEvent(
                source: TimelineEventSource.todo,
                sourceId: 1,
                type: 'todo',
                title: '明天交报告',
                description: '待完成',
                timestamp: now
                    .add(const Duration(minutes: 1))
                    .millisecondsSinceEpoch,
                date: 'today',
                icon: Icons.radio_button_unchecked,
                tags: const [],
                data: const {'id': 1, 'title': '明天交报告', 'is_completed': 0},
              ),
            ],
          ),
        ],
        child: const DaylineApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final todoEntry = find.byKey(const ValueKey('today-todo-entry'));
    expect(todoEntry, findsOneWidget);
    expect(find.text('待办的事情'), findsOneWidget);

    await tester.tap(todoEntry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byKey(const ValueKey('todo-panel-layer')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('todo-panel-bottom-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('todo-panel-daily-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-panel-todo-list')), findsOneWidget);
    expect(find.text('日常记录'), findsOneWidget);
    expect(find.text('待办事项'), findsOneWidget);
    expect(find.text('今天跑步30分钟'), findsOneWidget);
    expect(find.text('明天交报告'), findsOneWidget);
    expect(find.text('晨间散步'), findsNothing);
    expect(
      find.byKey(const ValueKey('todo-panel-daily-card-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('todo-panel-todo-card-0')),
      findsOneWidget,
    );

    final sheetRect = tester.getRect(
      find.byKey(const ValueKey('todo-panel-bottom-sheet')),
    );
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(sheetRect.top, greaterThan(screenHeight * 0.45));
    expect(sheetRect.height, lessThan(screenHeight * 0.45));

    await tester.tapAt(Offset(sheetRect.center.dx, sheetRect.top - 24));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const ValueKey('todo-panel-layer')), findsNothing);
  });

  testWidgets('待办面板可以点击待办完成和恢复', (tester) async {
    final fakeTodosRepository = _FakeTodosRepository();
    final now = DateTime.now();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todosRepositoryProvider.overrideWithValue(fakeTodosRepository),
          todayTodoPanelEventsProvider.overrideWith(
            (ref) async => [
              TimelineEvent(
                source: TimelineEventSource.todo,
                sourceId: 1,
                type: 'todo',
                title: '买牛奶',
                description: fakeTodosRepository.completed ? '已完成' : '待完成',
                timestamp: now.millisecondsSinceEpoch,
                date: 'today',
                icon: fakeTodosRepository.completed
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                tags: const [],
                data: {
                  'id': 1,
                  'title': '买牛奶',
                  'is_completed': fakeTodosRepository.completed ? 1 : 0,
                },
              ),
            ],
          ),
        ],
        child: const DaylineApp(),
      ),
    );

    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('today-todo-entry')),
    );

    await tester.tap(find.byKey(const ValueKey('today-todo-entry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await _pumpUntilFound(tester, find.text('买牛奶'));

    await tester.tap(find.text('买牛奶'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fakeTodosRepository.completed, isTrue);

    await tester.tap(find.text('买牛奶'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fakeTodosRepository.completed, isFalse);
  });

  testWidgets('线页面可以修改记录内容', (tester) async {
    final fakeRecordsRepository = _FakeRecordsRepository();
    final now = DateTime.now();
    const recordId = 7;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordsRepositoryProvider.overrideWithValue(fakeRecordsRepository),
          todayTodoPanelEventsProvider.overrideWith((ref) async => const []),
          timelineEventsProvider.overrideWith(
            (ref) async => [
              TimelineEvent(
                source: TimelineEventSource.record,
                sourceId: recordId,
                type: 'memo',
                title: fakeRecordsRepository.content,
                description: '',
                timestamp: now.millisecondsSinceEpoch,
                date: 'today',
                icon: Icons.notes_rounded,
                tags: const [],
                data: {
                  'id': recordId,
                  'content': fakeRecordsRepository.content,
                  'tags': '[]',
                  'metadata': '{}',
                },
              ),
            ],
          ),
        ],
        child: const DaylineApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('线').first);
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntilFound(tester, find.text('原来的记录'));

    await tester.tap(find.byKey(ValueKey('edit-records:$recordId')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '更新后的记录');
    await tester.tap(find.byKey(const ValueKey('timeline-edit-save')));
    await tester.pumpAndSettle();

    await _pumpUntilFound(tester, find.text('更新后的记录'));
    expect(find.text('原来的记录'), findsNothing);
    expect(fakeRecordsRepository.content, '更新后的记录');
  });
}

LocalDatabase _memoryDatabase() {
  return LocalDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  expect(finder, findsOneWidget);
}

class _FakeTodosRepository extends TodosRepository {
  _FakeTodosRepository() : super(_memoryDatabase());

  bool completed = false;

  @override
  Future<int> complete(int id, {DateTime? completedAt}) async {
    completed = true;
    return 1;
  }

  @override
  Future<int> reopen(int id, {DateTime? updatedAt}) async {
    completed = false;
    return 1;
  }
}

class _FakeRecordsRepository extends RecordsRepository {
  _FakeRecordsRepository() : super(_memoryDatabase());

  String content = '原来的记录';

  @override
  Future<int> updateDetails(
    int id, {
    required String content,
    String? time,
    List<String> tags = const [],
    Map<String, Object?> metadata = const {},
    DateTime? updatedAt,
  }) async {
    this.content = content;
    return 1;
  }
}
