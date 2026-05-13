import 'dart:async';

import 'package:dayline_app/app.dart';
import 'package:dayline_app/core/database/local_database.dart';
import 'package:dayline_app/core/database/repository_providers.dart';
import 'package:dayline_app/core/database/repositories.dart';
import 'package:dayline_app/core/stt/stt_engine.dart';
import 'package:dayline_app/core/stt/stt_providers.dart';
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

    await tester.tap(find.byKey(const ValueKey('collapsed-intent-pill')));
    await tester.pump(const Duration(milliseconds: 260));

    // Find the text input after the unified intent pill expands.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('文字'), findsOneWidget);

    final input = find.byType(TextField).first;
    await tester.enterText(input, '今天跑步30分钟');
    await tester.pump();

    expect(find.text('今天跑步30分钟'), findsOneWidget);
  });

  testWidgets('底部胶囊保留键盘入口但不显示上滑箭头', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DaylineApp()));
    await tester.pumpAndSettle();

    final pill = find.byKey(const ValueKey('collapsed-intent-pill'));

    expect(pill, findsOneWidget);
    expect(
      find.descendant(
        of: pill,
        matching: find.byIcon(Icons.keyboard_alt_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: pill,
        matching: find.byIcon(Icons.keyboard_arrow_up_rounded),
      ),
      findsNothing,
    );
  });

  testWidgets('文字胶囊点空白后收回小窗口', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: DaylineApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('collapsed-intent-pill')));
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.byKey(const ValueKey('expanded-intent-input')), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const ValueKey('intent-dismiss-layer')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('intent-dismiss-layer')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('collapsed-intent-pill')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('collapsed intent long press stops after pointer release', (
    tester,
  ) async {
    final sttEngine = _HoldToTalkSttEngine();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sttEngineProvider.overrideWithValue(sttEngine),
          todayTodoPanelEventsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: Scaffold(body: FlashRecordPage())),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();

    final pill = find.byKey(const ValueKey('collapsed-intent-pill'));
    expect(pill, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(pill));
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();

    expect(sttEngine.startCount, 1);
    expect(pill, findsOneWidget);

    await gesture.up();
    await tester.pump();

    expect(sttEngine.stopCount, 1);
  });

  testWidgets('点击空白可以停止正在听写的大话筒', (tester) async {
    final sttEngine = _HoldToTalkSttEngine();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sttEngineProvider.overrideWithValue(sttEngine),
          todayTodoPanelEventsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: Scaffold(body: FlashRecordPage())),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    await tester.tap(find.byType(VoiceButton));
    await tester.pump();

    expect(sttEngine.startCount, 1);

    await tester.tapAt(const Offset(20, 20));
    await tester.pump();

    expect(sttEngine.stopCount, 1);
  });

  testWidgets('听写时底部胶囊不显示波形和上滑箭头', (tester) async {
    final sttEngine = _HoldToTalkSttEngine();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sttEngineProvider.overrideWithValue(sttEngine),
          todayTodoPanelEventsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: Scaffold(body: FlashRecordPage())),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    await tester.tap(find.byType(VoiceButton));
    await tester.pump();

    final pill = find.byKey(const ValueKey('collapsed-intent-pill'));

    expect(pill, findsOneWidget);
    for (final icon in [
      Icons.graphic_eq_rounded,
      Icons.keyboard_arrow_up_rounded,
    ]) {
      expect(
        find.descendant(of: pill, matching: find.byIcon(icon)),
        findsNothing,
      );
    }
  });

  testWidgets(
    'tapping the transparent edge of voice area does not start voice',
    (tester) async {
      final sttEngine = _HoldToTalkSttEngine();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sttEngineProvider.overrideWithValue(sttEngine),
            todayTodoPanelEventsProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(home: Scaffold(body: FlashRecordPage())),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump();

      final voiceRect = tester.getRect(find.byType(VoiceButton));
      await tester.tapAt(voiceRect.center + const Offset(130, 0));
      await tester.pump();

      expect(sttEngine.startCount, 0);
    },
  );

  testWidgets('text input sits close to the keyboard', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(const ProviderScope(child: DaylineApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('collapsed-intent-pill')));
    await tester.pump(const Duration(milliseconds: 260));

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final keyboardTop = screenHeight - 300;
    final inputRect = tester.getRect(
      find.byKey(const ValueKey('expanded-intent-input')),
    );

    expect(inputRect.bottom, greaterThan(keyboardTop - 28));
  });

  testWidgets('listening pill does not open text input', (tester) async {
    final sttEngine = _HoldToTalkSttEngine();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sttEngineProvider.overrideWithValue(sttEngine),
          todayTodoPanelEventsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: Scaffold(body: FlashRecordPage())),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    await tester.tap(find.byType(VoiceButton));
    await tester.pump();

    expect(sttEngine.startCount, 1);

    await tester.tap(find.byKey(const ValueKey('collapsed-intent-pill')));
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.byKey(const ValueKey('expanded-intent-input')), findsNothing);
  });

  testWidgets('voice long press waits for STT init and starts once ready', (
    tester,
  ) async {
    final sttEngine = _DeferredInitSttEngine();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sttEngineProvider.overrideWithValue(sttEngine),
          todayTodoPanelEventsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: Scaffold(body: FlashRecordPage())),
      ),
    );

    await tester.pump();

    final pill = find.byKey(const ValueKey('collapsed-intent-pill'));
    expect(pill, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(pill));
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();

    expect(find.text('离线大脑还在唤醒，稍等一下'), findsNothing);
    expect(find.textContaining('离线语音暂不可用'), findsNothing);
    expect(sttEngine.initializeCount, greaterThanOrEqualTo(1));

    sttEngine.completeInitialization();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(sttEngine.startCount, 1);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('待办入口使用真实记录并以精简时间轴展示', (tester) async {
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

    final todoEntry = find.byKey(const ValueKey('collapsed-intent-pill'));
    expect(todoEntry, findsOneWidget);

    await tester.drag(todoEntry, const Offset(0, -90));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byKey(const ValueKey('todo-panel-layer')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('todo-panel-bottom-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('todo-panel-daily-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-panel-todo-list')), findsOneWidget);
    expect(find.text('迷你时间轴'), findsNothing);
    expect(find.text('待办事项'), findsNothing);
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
    expect(sheetRect.top, greaterThan(screenHeight * 0.25));
    expect(sheetRect.height, greaterThan(screenHeight * 0.45));

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
      find.byKey(const ValueKey('collapsed-intent-pill')),
    );

    await tester.drag(
      find.byKey(const ValueKey('collapsed-intent-pill')),
      const Offset(0, -90),
    );
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

class _HoldToTalkSttEngine implements SttEngine {
  int startCount = 0;
  _HoldToTalkSession? session;

  int get stopCount => session?.stopCount ?? 0;

  @override
  Future<SttAvailability> initialize() async => const SttAvailability.ready();

  @override
  Future<SttListenSession> startListening() async {
    startCount += 1;
    session = _HoldToTalkSession();
    return session!;
  }

  @override
  Future<void> dispose() async {}
}

class _HoldToTalkSession implements SttListenSession {
  final _controller = StreamController<SttTranscript>.broadcast();
  int stopCount = 0;

  @override
  Stream<SttTranscript> get transcripts => _controller.stream;

  @override
  Future<SttTranscript> stop() async {
    stopCount += 1;
    const transcript = SttTranscript(
      text: 'released voice memo',
      isFinal: true,
    );
    if (!_controller.isClosed) {
      _controller.add(transcript);
      await _controller.close();
    }
    return transcript;
  }

  @override
  Future<void> cancel() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

class _DeferredInitSttEngine implements SttEngine {
  final _initializeCompleter = Completer<SttAvailability>();
  _HoldToTalkSession? session;

  int initializeCount = 0;
  int startCount = 0;

  @override
  Future<SttAvailability> initialize() {
    initializeCount += 1;
    return _initializeCompleter.future;
  }

  void completeInitialization() {
    if (!_initializeCompleter.isCompleted) {
      _initializeCompleter.complete(const SttAvailability.ready());
    }
  }

  @override
  Future<SttListenSession> startListening() async {
    startCount += 1;
    session = _HoldToTalkSession();
    return session!;
  }

  @override
  Future<void> dispose() async {}
}
