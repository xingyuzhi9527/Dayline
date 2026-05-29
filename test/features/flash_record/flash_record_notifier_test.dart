import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/core/parser/expense_line_item.dart';
import 'package:liflow_app/core/stt/stt_engine.dart';
import 'package:liflow_app/core/stt/stt_providers.dart';
import 'package:liflow_app/features/flash_record/flash_record_notifier.dart';
import 'package:liflow_app/features/flash_record/flash_record_state.dart';
import 'package:liflow_app/features/projects/project_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'given notifier is created, when build completes, then STT initializes asynchronously',
    () async {
      final sttEngine = _FakeSttEngine();
      final container = ProviderContainer(
        overrides: [sttEngineProvider.overrideWithValue(sttEngine)],
      );
      addTearDown(container.dispose);

      final state = container.read(flashRecordProvider);
      expect(state.sttStatus, SttAvailabilityStatus.loading);
      expect(sttEngine.initializeCount, 0);

      await Future<void>.delayed(Duration.zero);

      expect(sttEngine.initializeCount, 1);
      expect(
        container.read(flashRecordProvider).sttStatus,
        SttAvailabilityStatus.unavailable,
      );
    },
  );

  test(
    'given a parsed time, when saving text, then created_at follows that time',
    () async {
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          sttEngineProvider.overrideWithValue(_FakeSttEngine()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);

      final today = DateTime.now();

      await container.read(flashRecordProvider.notifier).saveAsText('08:05 出门');

      final records = await container
          .read(recordsRepositoryProvider)
          .findByDate(today);

      expect(records, hasLength(1));
      expect(records.single['time'], '08:05');

      final createdAt = DateTime.fromMillisecondsSinceEpoch(
        records.single['created_at'] as int,
      );
      expect(createdAt.hour, 8);
      expect(createdAt.minute, 5);
    },
  );

  test(
    'given a transcribed voice draft, when saving, then stores text only and clears the draft file',
    () async {
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final appSettingsRepository = AppSettingsRepository(database);
      final rootDir = await Directory.systemTemp.createTemp(
        'liflow-flash-audio-root-',
      );
      final draftDir = await Directory.systemTemp.createTemp(
        'liflow-flash-audio-draft-',
      );
      final draftFile = File(
        '${draftDir.path}${Platform.pathSeparator}draft.wav',
      );
      await draftFile.writeAsBytes(const [1, 2, 3]);
      await appSettingsRepository.create(
        key: 'markdown_root_path',
        value: rootDir.path,
      );

      final sttEngine = _FakeSttEngine(
        availability: const SttAvailability.ready(),
        session: _FakeSttSession(
          transcript: SttTranscript(
            text: '08:05 出门',
            isFinal: true,
            recordingDraft: SttRecordingDraft(
              path: draftFile.path,
              duration: const Duration(seconds: 5),
            ),
          ),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          sttEngineProvider.overrideWithValue(sttEngine),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);
      addTearDown(() async {
        if (await rootDir.exists()) {
          await rootDir.delete(recursive: true);
        }
        if (await draftDir.exists()) {
          await draftDir.delete(recursive: true);
        }
      });

      final notifier = container.read(flashRecordProvider.notifier);
      notifier.setRecordingMode(FlashRecordingMode.transcribe);
      await notifier.startListening();
      await notifier.stopListening();
      await notifier.save();
      await Future<void>.delayed(Duration.zero);

      final records = await container
          .read(recordsRepositoryProvider)
          .findByDate(DateTime.now());
      final attachments = await container
          .read(mediaAttachmentsRepositoryProvider)
          .findByRecordId(records.single['id'] as int);

      expect(records, hasLength(1));
      expect(records.single['content'], '出门');
      expect(attachments, isEmpty);
      expect(await draftFile.exists(), isFalse);
      expect(container.read(flashRecordProvider).recordingDraft, isNull);
    },
  );

  test(
    'given a selected project, when saving a todo, then stores it in project data and only displays it on timeline',
    () async {
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final settings = AppSettingsRepository(database);
      await settings.create(
        key: projectsSettingsKey,
        value: jsonEncode([
          {
            'id': 'project-1',
            'name': '英语学习 App',
            'status': '进行中',
            'goal': '把学习节奏串起来',
            'lastUpdate': '刚刚',
            'todos': [],
            'updates': [],
          },
        ]),
      );
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          sttEngineProvider.overrideWithValue(_FakeSttEngine()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);

      final notifier = container.read(flashRecordProvider.notifier);
      notifier.updateParsedText('待办 修复 bug');
      notifier.selectProject('project-1');
      await notifier.save();

      final records = await container
          .read(recordsRepositoryProvider)
          .findByDate(DateTime.now());
      final todos = await container
          .read(todosRepositoryProvider)
          .findByDate(DateTime.now());
      final projectRow = await settings.findByKey(projectsSettingsKey);
      final projects = jsonDecode(projectRow!['value'] as String) as List;
      final project = projects.single as Map<String, Object?>;
      final projectTodos = project['todos'] as List;
      final projectUpdates = project['updates'] as List;
      final recordMetadata =
          jsonDecode(records.single['metadata'] as String)
              as Map<String, Object?>;

      expect(todos, isEmpty);
      expect(records, hasLength(1));
      expect(records.single['content'], '添加待办：修复 bug');
      expect(recordMetadata['projectId'], 'project-1');
      expect(recordMetadata['projectEntryType'], 'todo');
      expect(projectTodos.single['title'], '修复 bug');
      expect(projectUpdates.single['text'], '添加待办：修复 bug');
    },
  );

  test(
    'given multiple expense items, when saving, then stores each item separately',
    () async {
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          sttEngineProvider.overrideWithValue(_FakeSttEngine()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);

      final notifier = container.read(flashRecordProvider.notifier);
      notifier.updateParsedText('午饭35元 咖啡18元');
      await notifier.save();

      final expenses = await container
          .read(expensesRepositoryProvider)
          .findByDate(DateTime.now());

      expect(expenses, hasLength(2));
      expect(expenses.map((row) => row['category']), ['午饭', '咖啡']);
      expect(expenses.map((row) => row['amount']), [35.0, 18.0]);
    },
  );

  test(
    'given a corrected expense item, when saving, then uses the edited amount',
    () async {
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          sttEngineProvider.overrideWithValue(_FakeSttEngine()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);

      final notifier = container.read(flashRecordProvider.notifier);
      notifier.updateParsedText('午饭35元');
      notifier.updateExpenseItems(const [
        ExpenseLineItem(name: '午饭', amount: 45),
      ]);
      await notifier.save();

      final expenses = await container
          .read(expensesRepositoryProvider)
          .findByDate(DateTime.now());

      expect(expenses.single['category'], '午饭');
      expect(expenses.single['amount'], 45.0);
    },
  );
}

class _FakeSttEngine implements SttEngine {
  _FakeSttEngine({
    this.availability = const SttAvailability.unavailable('offline'),
    this.session,
  });

  final SttAvailability availability;
  final SttListenSession? session;
  var initializeCount = 0;

  @override
  Future<SttAvailability> initialize() async {
    initializeCount += 1;
    return availability;
  }

  @override
  Future<SttListenSession> startListening({bool transcribe = true}) {
    final nextSession = session;
    if (nextSession == null) {
      throw UnimplementedError();
    }
    return Future.value(nextSession);
  }

  @override
  Future<void> dispose() async {}
}

class _FakeSttSession implements SttListenSession {
  _FakeSttSession({required this.transcript});

  final SttTranscript transcript;
  final _controller = StreamController<SttTranscript>.broadcast();

  @override
  Stream<SttTranscript> get transcripts => _controller.stream;

  @override
  Future<SttTranscript> stop({bool transcribe = true}) async {
    await _controller.close();
    return transcript;
  }

  @override
  Future<void> cancel() async {
    await _controller.close();
  }
}
