import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/markdown/markdown_directory_service.dart';
import 'package:liflow_app/core/media/photo_moment_service.dart';
import 'package:path/path.dart' as p;
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

  test('creates a multi-photo moment in a named folder', () async {
    final first = File('${captureDir.path}${Platform.pathSeparator}first.jpg');
    final second = File(
      '${captureDir.path}${Platform.pathSeparator}second.png',
    );
    await first.writeAsBytes(const [1, 1, 1]);
    await second.writeAsBytes(const [2, 2, 2]);
    final createdAt = DateTime(2026, 5, 17, 21, 36, 9, 123);

    final recordId = await service.createFromImageSelection(
      sourceImagePaths: [first.path, second.path],
      note: '多图',
      tags: const ['相册'],
      createdAt: createdAt,
    );

    final attachments = await mediaAttachmentsRepository.findByRecordId(
      recordId,
    );
    expect(attachments, hasLength(2));

    final firstStoredPath = attachments.first['local_path'] as String;
    final secondStoredPath = attachments.last['local_path'] as String;
    expect(firstStoredPath, contains('photo_20260517_213609123'));
    expect(firstStoredPath, endsWith('first.jpg'));
    expect(secondStoredPath, endsWith('second.png'));
    expect(await File(firstStoredPath).exists(), isTrue);
    expect(await File(secondStoredPath).exists(), isTrue);
    expect(await first.exists(), isTrue);
    expect(await second.exists(), isTrue);
  });

  test('creates an expense receipt with a named photo file', () async {
    final source = File(
      '${captureDir.path}${Platform.pathSeparator}receipt.jpg',
    );
    await source.writeAsBytes(const [3, 2, 1]);
    final createdAt = DateTime(2026, 5, 17, 18, 9, 8);

    final recordId = await service.createExpenseReceipt(
      sourceImagePath: source.path,
      expenseName: '午饭/咖啡',
      expenseAmount: 53,
      expenseIds: const [7, 8],
      createdAt: createdAt,
    );

    final records = await recordsRepository.findByDate(createdAt);
    final attachments = await mediaAttachmentsRepository.findByRecordId(
      recordId,
    );
    final storedPath = attachments.single['local_path'] as String;

    expect(records.single['content'], '消费凭证：午饭/咖啡');
    expect(records.single['tags'], '["消费","报销"]');
    expect(storedPath, contains('午饭咖啡_53_20260517_180908.jpg'));
    expect(storedPath, contains('receipts'));
    expect(await File(storedPath).exists(), isTrue);
    expect(
      await File(
        '${File(storedPath).parent.path}${Platform.pathSeparator}.nomedia',
      ).exists(),
      isTrue,
    );
    expect(await source.exists(), isTrue);
  });

  test(
    'expense receipt operation ids prevent same-second file collisions',
    () async {
      final firstSource = File(
        '${captureDir.path}${Platform.pathSeparator}receipt-a.jpg',
      );
      final secondSource = File(
        '${captureDir.path}${Platform.pathSeparator}receipt-b.jpg',
      );
      await firstSource.writeAsBytes(const [1, 1, 1]);
      await secondSource.writeAsBytes(const [2, 2, 2]);
      final createdAt = DateTime(2026, 5, 17, 18, 9, 8);

      final firstId = await service.createExpenseReceipt(
        sourceImagePath: firstSource.path,
        expenseName: '午饭',
        expenseAmount: 35,
        createdAt: createdAt,
        operationId: 'operation-a',
      );
      final secondId = await service.createExpenseReceipt(
        sourceImagePath: secondSource.path,
        expenseName: '午饭',
        expenseAmount: 35,
        createdAt: createdAt,
        operationId: 'operation-b',
      );

      final firstPath =
          (await mediaAttachmentsRepository.findByRecordId(
                firstId,
              )).single['local_path']
              as String;
      final secondPath =
          (await mediaAttachmentsRepository.findByRecordId(
                secondId,
              )).single['local_path']
              as String;
      expect(firstPath, isNot(secondPath));
      expect(await File(firstPath).readAsBytes(), const [1, 1, 1]);
      expect(await File(secondPath).readAsBytes(), const [2, 2, 2]);
    },
  );

  test('failed receipt attachment insert removes its copied file', () async {
    final source = File(
      '${captureDir.path}${Platform.pathSeparator}receipt-failure.jpg',
    );
    await source.writeAsBytes(const [4, 5, 6]);
    final failingService = PhotoMomentService(
      recordsRepository: recordsRepository,
      mediaAttachmentsRepository: _FailingMediaAttachmentsRepository(database),
      directoryService: MarkdownDirectoryService(appSettingsRepository),
    );

    await expectLater(
      failingService.createExpenseReceipt(
        sourceImagePath: source.path,
        expenseName: '失败收据',
        expenseAmount: 20,
        createdAt: DateTime(2026, 5, 17, 18, 9, 8),
        operationId: 'operation-failure',
      ),
      throwsStateError,
    );

    expect(await recordsRepository.findByDate(DateTime(2026, 5, 17)), isEmpty);
    final receiptFiles = await rootDir
        .list(recursive: true)
        .where((entry) => entry is File && p.basename(entry.path) != '.nomedia')
        .toList();
    expect(receiptFiles, isEmpty);
  });
}

class _FailingMediaAttachmentsRepository extends MediaAttachmentsRepository {
  _FailingMediaAttachmentsRepository(super.localDatabase);

  @override
  Future<int> create({
    required int recordId,
    required String mediaType,
    required String sourceType,
    required String localPath,
    String? thumbnailPath,
    int? width,
    int? height,
    int? durationMs,
    int sortOrder = 0,
    DateTime? createdAt,
  }) {
    throw StateError('injected attachment failure');
  }
}
