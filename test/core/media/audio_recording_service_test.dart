import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/markdown/markdown_directory_service.dart';
import 'package:liflow_app/core/media/audio_recording_service.dart';
import 'package:liflow_app/core/stt/stt_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late RecordsRepository recordsRepository;
  late MediaAttachmentsRepository mediaAttachmentsRepository;
  late AppSettingsRepository appSettingsRepository;
  late Directory rootDir;
  late Directory draftDir;
  late AudioRecordingService service;

  setUp(() async {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    recordsRepository = RecordsRepository(database);
    mediaAttachmentsRepository = MediaAttachmentsRepository(database);
    appSettingsRepository = AppSettingsRepository(database);
    rootDir = await Directory.systemTemp.createTemp('liflow-audio-root-');
    draftDir = await Directory.systemTemp.createTemp('liflow-audio-draft-');

    await appSettingsRepository.create(
      key: 'markdown_root_path',
      value: rootDir.path,
    );

    service = AudioRecordingService(
      recordsRepository: recordsRepository,
      mediaAttachmentsRepository: mediaAttachmentsRepository,
      directoryService: MarkdownDirectoryService(appSettingsRepository),
    );
  });

  tearDown(() async {
    await database.close();
    if (await rootDir.exists()) {
      await rootDir.delete(recursive: true);
    }
    if (await draftDir.exists()) {
      await draftDir.delete(recursive: true);
    }
  });

  test(
    'Given an audio draft, When creating a voice memo, Then stores the audio and removes the draft',
    () async {
      final draftFile = File(
        '${draftDir.path}${Platform.pathSeparator}draft.wav',
      );
      await draftFile.writeAsBytes(const [1, 2, 3, 4]);
      final draft = SttRecordingDraft(
        path: draftFile.path,
        duration: const Duration(seconds: 7),
      );
      final createdAt = DateTime(2026, 5, 17, 22, 30);

      final recordId = await service.createVoiceMemo(
        draft: draft,
        createdAt: createdAt,
      );

      final records = await recordsRepository.findByDate(createdAt);
      final attachments = await mediaAttachmentsRepository.findByRecordId(
        recordId,
      );

      expect(records, hasLength(1));
      expect(records.single['type'], 'voice_memo');
      expect(await draftFile.exists(), isFalse);
      expect(attachments, hasLength(1));
      expect(attachments.single['media_type'], 'audio');
      expect(attachments.single['duration_ms'], 7000);

      final storedPath = attachments.single['local_path'] as String;
      expect(storedPath, contains('audio'));
      expect(await File(storedPath).exists(), isTrue);
    },
  );

  test(
    'Given stored audio attachments, When deleting record files, Then removes stored audio from disk',
    () async {
      final draftFile = File(
        '${draftDir.path}${Platform.pathSeparator}draft.wav',
      );
      await draftFile.writeAsBytes(const [9, 8, 7]);
      final recordId = await service.createVoiceMemo(
        draft: SttRecordingDraft(
          path: draftFile.path,
          duration: const Duration(seconds: 3),
        ),
        createdAt: DateTime(2026, 5, 17, 22, 40),
      );
      final attachment = (await mediaAttachmentsRepository.findByRecordId(
        recordId,
      )).single;
      final storedPath = attachment['local_path'] as String;

      await service.deleteAttachmentsForRecord(recordId);

      expect(await File(storedPath).exists(), isFalse);
    },
  );
}
