import 'dart:async';
import 'dart:io';

import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/core/stt/stt_engine.dart';
import 'package:liflow_app/core/stt/stt_providers.dart';
import 'package:liflow_app/features/flash_record/flash_record_notifier.dart';
import 'package:liflow_app/features/flash_record/flash_record_state.dart';
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
    'given a voice transcript with a draft, when saving, then stores audio attachment and clears the draft file',
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

      final records = await container
          .read(recordsRepositoryProvider)
          .findByDate(DateTime.now());
      final attachments = await container
          .read(mediaAttachmentsRepositoryProvider)
          .findByRecordId(records.single['id'] as int);

      expect(records, hasLength(1));
      expect(attachments, hasLength(1));
      expect(attachments.single['media_type'], 'audio');
      expect(await draftFile.exists(), isFalse);
      expect(
        await File(attachments.single['local_path'] as String).exists(),
        isTrue,
      );
      expect(container.read(flashRecordProvider).recordingDraft, isNull);
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
