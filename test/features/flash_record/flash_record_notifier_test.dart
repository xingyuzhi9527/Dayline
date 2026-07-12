import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/core/parser/expense_line_item.dart';
import 'package:liflow_app/core/parser/lui_lite_parser.dart';
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
    'given notifier is created, when voice is first requested, then STT initializes lazily',
    () async {
      final sttEngine = _FakeSttEngine(
        availability: const SttAvailability.ready(),
        session: _FakeSttSession(
          transcript: const SttTranscript(text: '', isFinal: false),
        ),
      );
      final container = ProviderContainer(
        overrides: [sttEngineProvider.overrideWithValue(sttEngine)],
      );
      addTearDown(container.dispose);

      final state = container.read(flashRecordProvider);
      expect(state.sttStatus, SttAvailabilityStatus.idle);
      expect(sttEngine.initializeCount, 0);

      await Future<void>.delayed(Duration.zero);
      expect(sttEngine.initializeCount, 0);

      await container.read(flashRecordProvider.notifier).startListening();

      expect(sttEngine.initializeCount, 1);
      expect(
        container.read(flashRecordProvider).sttStatus,
        SttAvailabilityStatus.ready,
      );
      expect(container.read(flashRecordProvider).phase, FlashPhase.listening);
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
    'given a salary reimbursement note with amounts, when saving text, then stores memo only',
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

      await container
          .read(flashRecordProvider.notifier)
          .saveAsText('10000元以上工资可申报1000的房贷报销');

      final records = await container
          .read(recordsRepositoryProvider)
          .findByDate(DateTime.now());
      final expenses = await container
          .read(expensesRepositoryProvider)
          .findByDate(DateTime.now());

      expect(records, hasLength(1));
      expect(records.single['type'], 'memo');
      expect(records.single['content'], '10000元以上工资可申报1000的房贷报销');
      expect(expenses, isEmpty);
    },
  );

  test(
    'given multiple expense amounts, when saving text, then asks for confirmation before persistence',
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
      await notifier.saveAsText('午饭35元 咖啡18元');

      var state = container.read(flashRecordProvider);
      expect(state.phase, FlashPhase.confirming);
      expect(state.parsedInput?.type, ParsedInputType.expense);
      expect(
        await container
            .read(expensesRepositoryProvider)
            .findByDate(DateTime.now()),
        isEmpty,
      );

      await notifier.save();

      state = container.read(flashRecordProvider);
      final expenses = await container
          .read(expensesRepositoryProvider)
          .findByDate(DateTime.now());
      expect(state.phase, FlashPhase.saved);
      expect(expenses, hasLength(2));
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
    'given project JSON was updated before timeline insert fails, when retried, then the first attempt rolls back',
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
            'id': 'project-rollback',
            'name': '事务项目',
            'status': '进行中',
            'goal': '验证回滚',
            'lastUpdate': '刚刚',
            'todos': [],
            'updates': [],
          },
        ]),
      );
      final recordsRepository = _FailOnceRecordsRepository(database);
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          recordsRepositoryProvider.overrideWithValue(recordsRepository),
          sttEngineProvider.overrideWithValue(_FakeSttEngine()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);

      final notifier = container.read(flashRecordProvider.notifier);
      notifier.updateParsedText('待办 修复事务问题');
      notifier.selectProject('project-rollback');
      await notifier.save();

      var projectRow = await settings.findByKey(projectsSettingsKey);
      var projects = jsonDecode(projectRow!['value'] as String) as List;
      var project = projects.single as Map<String, Object?>;
      expect(project['todos'], isEmpty);
      expect(project['updates'], isEmpty);
      expect(
        await container
            .read(recordsRepositoryProvider)
            .findByDate(DateTime.now()),
        isEmpty,
      );
      final pendingOperationId = container
          .read(flashRecordProvider)
          .saveOperationId;
      expect(pendingOperationId, isNotNull);

      await notifier.save();

      projectRow = await settings.findByKey(projectsSettingsKey);
      projects = jsonDecode(projectRow!['value'] as String) as List;
      project = projects.single as Map<String, Object?>;
      expect(project['todos'] as List, hasLength(1));
      expect(project['updates'] as List, hasLength(1));
      expect(
        await container
            .read(recordsRepositoryProvider)
            .findByDate(DateTime.now()),
        hasLength(1),
      );
      expect(
        container.read(flashRecordProvider).saveOperationId,
        pendingOperationId,
      );
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
    'given the second expense insert fails, when retried, then no partial or duplicate expense remains',
    () async {
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final expensesRepository = _FailSecondExpenseOnceRepository(database);
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          expensesRepositoryProvider.overrideWithValue(expensesRepository),
          sttEngineProvider.overrideWithValue(_FakeSttEngine()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);

      final notifier = container.read(flashRecordProvider.notifier);
      notifier.updateParsedText('午饭35元 咖啡18元');
      await notifier.save();

      expect(expensesRepository.createCount, 2);
      expect(await expensesRepository.findByDate(DateTime.now()), isEmpty);
      final pendingOperationId = container
          .read(flashRecordProvider)
          .saveOperationId;
      expect(pendingOperationId, isNotNull);

      await notifier.save();

      final expenses = await expensesRepository.findByDate(DateTime.now());
      expect(expenses, hasLength(2));
      expect(expenses.map((row) => row['amount']), [35.0, 18.0]);
      expect(
        container.read(flashRecordProvider).saveOperationId,
        pendingOperationId,
      );
    },
  );

  test(
    'given a pending expense request survives notifier recreation, when retried with the same input, then it reuses the operation',
    () async {
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final expensesRepository = _FailSecondExpenseOnceRepository(database);
      final firstContainer = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          expensesRepositoryProvider.overrideWithValue(expensesRepository),
          sttEngineProvider.overrideWithValue(_FakeSttEngine()),
        ],
      );
      addTearDown(firstContainer.dispose);
      addTearDown(database.close);

      const input = '午饭35元 咖啡18元';
      final firstNotifier = firstContainer.read(flashRecordProvider.notifier);
      firstNotifier.updateParsedText(input);
      await firstNotifier.save();
      final pendingId = firstContainer
          .read(flashRecordProvider)
          .saveOperationId;
      expect(pendingId, isNotNull);
      expect(await expensesRepository.findByDate(DateTime.now()), isEmpty);

      firstContainer.dispose();
      final secondContainer = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          expensesRepositoryProvider.overrideWithValue(expensesRepository),
          sttEngineProvider.overrideWithValue(_FakeSttEngine()),
        ],
      );
      addTearDown(secondContainer.dispose);
      final secondNotifier = secondContainer.read(flashRecordProvider.notifier);
      secondNotifier.updateParsedText(input);
      await secondNotifier.save();

      expect(await expensesRepository.findByDate(DateTime.now()), hasLength(2));
      expect(
        secondContainer.read(flashRecordProvider).saveOperationId,
        pendingId,
      );
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

  test(
    'given a save exceeds the UI timeout, when retried, then reuses the in-flight write',
    () async {
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final releaseWrite = Completer<void>();
      final recordsRepository = _DelayedRecordsRepository(
        database,
        releaseWrite.future,
      );
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          recordsRepositoryProvider.overrideWithValue(recordsRepository),
          flashSaveTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 5),
          ),
          sttEngineProvider.overrideWithValue(_FakeSttEngine()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);

      final saved = Completer<void>();
      final subscription = container.listen(flashRecordProvider, (_, next) {
        if (next.savedSequence == 1 && !saved.isCompleted) {
          saved.complete();
        }
      });
      addTearDown(subscription.close);

      final notifier = container.read(flashRecordProvider.notifier);
      await notifier.saveAsText('08:05 出门');

      await recordsRepository.createStarted.future.timeout(
        const Duration(seconds: 1),
      );
      expect(recordsRepository.createCount, 1);
      expect(container.read(flashRecordProvider).textSaving, isTrue);
      expect(
        container.read(flashRecordProvider).errorMessage,
        contains('保存仍在处理'),
      );

      await notifier.saveAsText('08:05 出门');
      expect(recordsRepository.createCount, 1);

      releaseWrite.complete();
      await saved.future.timeout(const Duration(seconds: 1));

      final records = await recordsRepository.findByDate(DateTime.now());
      expect(records, hasLength(1));
      expect(container.read(flashRecordProvider).textSaving, isFalse);
      expect(container.read(flashRecordProvider).savedSequence, 1);
    },
  );

  test(
    'given a completed request was not acknowledged, when notifier is recreated and retried, then it does not insert again',
    () async {
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final firstContainer = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          sttEngineProvider.overrideWithValue(_FakeSttEngine()),
        ],
      );
      addTearDown(firstContainer.dispose);
      addTearDown(database.close);

      const input = '今天天气很好';
      var notifier = firstContainer.read(flashRecordProvider.notifier);
      notifier.updateParsedText(input);
      await notifier.save();

      var records = await firstContainer
          .read(recordsRepositoryProvider)
          .findByDate(DateTime.now());
      final firstOperationId = firstContainer
          .read(flashRecordProvider)
          .saveOperationId;
      expect(records, hasLength(1));
      expect(firstOperationId, isNotNull);

      firstContainer.dispose();
      final secondContainer = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          sttEngineProvider.overrideWithValue(_FakeSttEngine()),
        ],
      );
      addTearDown(secondContainer.dispose);
      notifier = secondContainer.read(flashRecordProvider.notifier);
      notifier.updateParsedText(input);
      await notifier.save();

      records = await secondContainer
          .read(recordsRepositoryProvider)
          .findByDate(DateTime.now());
      expect(records, hasLength(1));
      expect(
        secondContainer.read(flashRecordProvider).saveOperationId,
        firstOperationId,
      );

      notifier.resetAfterSaved();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      notifier.updateParsedText(input);
      await notifier.save();

      records = await secondContainer
          .read(recordsRepositoryProvider)
          .findByDate(DateTime.now());
      expect(records, hasLength(2));
    },
  );
}

class _DelayedRecordsRepository extends RecordsRepository {
  _DelayedRecordsRepository(super.localDatabase, this._releaseWrite);

  final Future<void> _releaseWrite;
  final createStarted = Completer<void>();
  var createCount = 0;

  @override
  Future<int> create({
    required DateTime date,
    required String type,
    required String content,
    String? time,
    List<String> tags = const [],
    Map<String, Object?> metadata = const {},
    DateTime? createdAt,
  }) async {
    createCount += 1;
    if (!createStarted.isCompleted) {
      createStarted.complete();
    }
    await _releaseWrite;
    return super.create(
      date: date,
      type: type,
      content: content,
      time: time,
      tags: tags,
      metadata: metadata,
      createdAt: createdAt,
    );
  }
}

class _FailOnceRecordsRepository extends RecordsRepository {
  _FailOnceRecordsRepository(super.localDatabase);

  var _shouldFail = true;

  @override
  Future<int> create({
    required DateTime date,
    required String type,
    required String content,
    String? time,
    List<String> tags = const [],
    Map<String, Object?> metadata = const {},
    DateTime? createdAt,
  }) async {
    final id = await super.create(
      date: date,
      type: type,
      content: content,
      time: time,
      tags: tags,
      metadata: metadata,
      createdAt: createdAt,
    );
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('injected timeline failure');
    }
    return id;
  }
}

class _FailSecondExpenseOnceRepository extends ExpensesRepository {
  _FailSecondExpenseOnceRepository(super.localDatabase);

  var createCount = 0;
  var _shouldFail = true;

  @override
  Future<int> create({
    required DateTime date,
    required double amount,
    required String category,
    String? note,
    String currency = 'CNY',
    DateTime? createdAt,
  }) async {
    createCount += 1;
    final id = await super.create(
      date: date,
      amount: amount,
      category: category,
      note: note,
      currency: currency,
      createdAt: createdAt,
    );
    if (_shouldFail && createCount == 2) {
      _shouldFail = false;
      throw StateError('injected second expense failure');
    }
    return id;
  }
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
