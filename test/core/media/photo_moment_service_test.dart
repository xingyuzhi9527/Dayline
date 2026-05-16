import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/markdown/markdown_directory_service.dart';
import 'package:liflow_app/core/media/photo_moment_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late RecordsRepository recordsRepository;
  late MediaAttachmentsRepository mediaAttachmentsRepository;
  late AppSettingsRepository appSettingsRepository;
  late Directory rootDir;
  late Directory captureDir;
  late PhotoMomentService service;

  setUp(() async {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    recordsRepository = RecordsRepository(database);
    mediaAttachmentsRepository = MediaAttachmentsRepository(database);
    appSettingsRepository = AppSettingsRepository(database);
    rootDir = await Directory.systemTemp.createTemp('liflow-photo-root-');
    captureDir = await Directory.systemTemp.createTemp('liflow-photo-capture-');

    await appSettingsRepository.create(
      key: 'markdown_root_path',
      value: rootDir.path,
    );

    service = PhotoMomentService(
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
    if (await captureDir.exists()) {
      await captureDir.delete(recursive: true);
    }
  });

  test(
    'creates a photo moment and copies the captured image into attachments',
    () async {
      final source = File(
        '${captureDir.path}${Platform.pathSeparator}capture.jpg',
      );
      await source.writeAsBytes(const [1, 2, 3, 4, 5]);
      final createdAt = DateTime(2026, 5, 17, 21, 36);

      final recordId = await service.createFromCameraCapture(
        sourceImagePath: source.path,
        note: '晚饭还不错',
        tags: const ['饮食', '生活'],
        createdAt: createdAt,
      );

      final records = await recordsRepository.findByDate(createdAt);
      final attachments = await mediaAttachmentsRepository.findByRecordId(
        recordId,
      );

      expect(records, hasLength(1));
      expect(records.single['type'], 'moment_photo');
      expect(records.single['content'], '晚饭还不错');
      expect(records.single['tags'], '["饮食","生活"]');
      expect(await source.exists(), isFalse);
      expect(attachments, hasLength(1));

      final storedPath = attachments.single['local_path'] as String;
      expect(storedPath, contains('documents'));
      expect(storedPath, contains('photos'));
      expect(await File(storedPath).exists(), isTrue);
    },
  );

  test(
    'permanently deleting a photo moment removes both db rows and stored files',
    () async {
      final source = File(
        '${captureDir.path}${Platform.pathSeparator}capture.jpg',
      );
      await source.writeAsBytes(const [9, 8, 7, 6]);

      final recordId = await service.createFromCameraCapture(
        sourceImagePath: source.path,
        note: '',
        tags: const [],
        createdAt: DateTime(2026, 5, 17, 22, 10),
      );
      final attachment = (await mediaAttachmentsRepository.findByRecordId(
        recordId,
      )).single;
      final storedPath = attachment['local_path'] as String;

      await service.permanentlyDeletePhotoMoment(recordId);

      expect(await recordsRepository.findById(recordId), isNull);
      expect(
        await mediaAttachmentsRepository.findByRecordId(recordId),
        isEmpty,
      );
      expect(await File(storedPath).exists(), isFalse);
    },
  );
}
