import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/daily_reviews_repository.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/markdown/markdown_directory_service.dart';
import 'package:liflow_app/core/markdown/markdown_storage_service.dart';
import 'package:liflow_app/features/projects/project_store.dart';
import 'package:liflow_app/features/restore/markdown_restore_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late RecordsRepository recordsRepository;
  late TodosRepository todosRepository;
  late AppSettingsRepository settingsRepository;
  late _FakeRestoreSource source;
  late MarkdownRestoreService service;

  setUp(() {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    recordsRepository = RecordsRepository(database);
    todosRepository = TodosRepository(database);
    settingsRepository = AppSettingsRepository(database);
    source = _FakeRestoreSource({
      'daily/2026-05/2026-05-20.md': '''
---
type: daily
source: liflow
created_at: 2026-05-20T21:10:00
title: 2026-05-20
---
# 2026-05-20

Today I clarified the restore flow.
''',
      'notes/2026-05/20260520_restore-plan.md': '''
---
type: note
source: liflow
created_at: 2026-05-20T22:15:00
title: Restore plan
tags: []
---
# Restore plan

After reinstall, choose the original folder and restore long notes.
''',
      'projects/Dayline-abc123/project.md': '''
---
type: project
source: liflow
project_id: "project-abc123"
title: "Dayline"
status: "active"
updated_at: 2026-05-20T22:20:00
tags: [project]
---
# Dayline

## Goal
Make the life log stable.

## Todos
- [ ] Restore guide
- [x] Write project archive

## 最近更新
- 2026-05-20 · 文件：需求文档 ([文件](materials/spec.pdf))
''',
    });
    service = MarkdownRestoreService(
      source: source,
      database: database,
      recordsRepository: recordsRepository,
      settingsRepository: settingsRepository,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('scans markdown folder and previews recoverable content', () async {
    final preview = await service.preview();

    expect(preview.fromSnapshot, isFalse);
    expect(preview.dailyNotes, 1);
    expect(preview.longNotes, 1);
    expect(preview.projects, 1);
    expect(preview.total, 3);
  });

  test(
    'restores records and projects without duplicating on a second run',
    () async {
      final first = await service.restore();
      final second = await service.restore();

      expect(first.recordsRestored, 2);
      expect(first.projectsRestored, 1);
      expect(second.recordsRestored, 0);
      expect(second.projectsRestored, 0);

      final records = await recordsRepository.findAll();
      expect(
        records.map((row) => row['type']),
        containsAll(['memo', 'long_note']),
      );

      final longNote = records.firstWhere((row) => row['type'] == 'long_note');
      final metadata = jsonDecode(longNote['metadata'] as String) as Map;
      expect(
        metadata['path'],
        source.locationFor('notes/2026-05/20260520_restore-plan.md'),
      );
      expect(metadata['restoredFromMarkdown'], isTrue);

      final row = await settingsRepository.findByKey(projectsSettingsKey);
      final projects = jsonDecode(row!['value'] as String) as List;
      expect(projects, hasLength(1));
      expect(projects.single['id'], 'project-abc123');
      expect(projects.single['todos'], hasLength(2));
      final updates = projects.single['updates'] as List;
      expect(
        updates.where(
          (update) =>
              update is Map &&
              update['fileRelativePath'] ==
                  'projects/Dayline-abc123/materials/spec.pdf',
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'restores todos and expenses from daily markdown when snapshot is missing',
    () async {
      source.files['daily/2026-05/2026-05-22.md'] = '''
---
type: daily
source: liflow
created_at: 2026-05-22T21:10:00
title: 2026-05-22
---
# 2026-05-22

## 待办流转

### 已完成

- [x] 交周报，时间 09:30，优先级 2

### 未完成

- [ ] 买牛奶

## 原始记录

### 消费

- 12:10 午饭：¥35.00，园区食堂
- 15:30 咖啡：¥18.00
''';

      final preview = await service.preview();
      expect(preview.todos, 2);
      expect(preview.expenses, 2);

      final first = await service.restore();
      final second = await service.restore();

      expect(first.todosRestored, 2);
      expect(first.expensesRestored, 2);
      expect(second.todosRestored, 0);
      expect(second.expensesRestored, 0);

      final db = await database.database;
      final todos = await db.query(
        'todos',
        where: 'date = ?',
        whereArgs: ['2026-05-22'],
        orderBy: 'id ASC',
      );
      expect(todos.map((row) => row['title']), ['交周报', '买牛奶']);
      expect(todos.first['is_completed'], 1);
      expect(todos.first['due_time'], '09:30');
      expect(todos.first['priority'], 2);

      final expenses = await db.query(
        'expenses',
        where: 'date = ?',
        whereArgs: ['2026-05-22'],
        orderBy: 'created_at ASC',
      );
      expect(expenses.map((row) => row['category']), ['午饭', '咖啡']);
      expect(expenses.map((row) => row['amount']), [35.0, 18.0]);
      expect(expenses.first['note'], '园区食堂');
    },
  );

  test(
    'restores expenses from monthly expense report markdown when snapshot is missing',
    () async {
      source.files.clear();
      source.files['projects/月消费账本-system-monthly-expenses/months/2026-06.md'] =
          '''
---
type: monthly_expense_report
source: liflow
month: 2026-06
generated_at: 2026-06-30T22:00:00
total: 80.00
count: 2
currency: CNY
---

# 2026-06 月消费账单

## 概览

- 总消费：¥80.00
- 消费次数：2

## 每日明细

### 06-02

- 08:10 早餐：¥12.00，包子豆浆
- 19:30 打车：¥68.00
''';

      final preview = await service.preview();
      expect(preview.expenses, 2);

      final first = await service.restore();
      final second = await service.restore();

      expect(first.expensesRestored, 2);
      expect(second.expensesRestored, 0);

      final db = await database.database;
      final expenses = await db.query(
        'expenses',
        where: 'date = ?',
        whereArgs: ['2026-06-02'],
        orderBy: 'created_at ASC',
      );
      expect(expenses.map((row) => row['category']), ['早餐', '打车']);
      expect(expenses.map((row) => row['amount']), [12.0, 68.0]);
      expect(expenses.first['note'], '包子豆浆');
    },
  );

  test(
    'supplements empty snapshot todos and expenses from markdown fallback',
    () async {
      source.files.clear();
      source.files['daily/2026-06/2026-06-02.md'] = '''
---
type: daily
source: liflow
created_at: 2026-06-02T21:10:00
title: 2026-06-02
---
# 2026-06-02

## 待办

- [ ] 补记账单
''';
      source.files['projects/月消费账本-system-monthly-expenses/months/2026-06.md'] =
          '''
---
type: monthly_expense_report
source: liflow
month: 2026-06
generated_at: 2026-06-30T22:00:00
total: 45.00
count: 1
currency: CNY
---

# 2026-06 月消费账单

## 每日明细

### 06-02

- 12:20 午饭：¥45.00
''';
      source.snapshot = jsonEncode({
        'schemaVersion': BackupSnapshotService.schemaVersion,
        'writtenAt': '2026-06-30T23:00:00.000',
        'records': const <Object?>[],
        'todos': const <Object?>[],
        'trackers': const <Object?>[],
        'tracker_logs': const <Object?>[],
        'focus_sessions': const <Object?>[],
        'expenses': const <Object?>[],
        'body_logs': const <Object?>[],
        'daily_reviews': const <Object?>[],
        'media_attachments': const <Object?>[],
        'project_files': const <Object?>[],
        'projects': const <Object?>[],
        'settings': const <Object?>[],
      });

      final preview = await service.preview();
      expect(preview.fromSnapshot, isTrue);
      expect(preview.todos, 1);
      expect(preview.expenses, 1);

      final result = await service.restore();
      expect(result.fromSnapshot, isTrue);
      expect(result.todosRestored, 1);
      expect(result.expensesRestored, 1);

      final db = await database.database;
      final todos = await db.query('todos');
      final expenses = await db.query('expenses');
      expect(todos.single['title'], '补记账单');
      expect(expenses.single['category'], '午饭');
      expect(expenses.single['amount'], 45.0);
    },
  );

  test('prefers backup snapshot and restores todos and settings', () async {
    source.snapshot = jsonEncode({
      // Keep this fixture on the legacy format to protect backward
      // compatibility while new snapshots use schema version 2.
      'schemaVersion': 1,
      'writtenAt': '2026-05-21T09:00:00.000',
      'records': [
        {
          'id': 10,
          'date': '2026-05-21',
          'type': 'memo',
          'content': 'Snapshot memo',
          'time': null,
          'tags': '[]',
          'metadata': '{}',
          'is_deleted': 0,
          'created_at': 1789870000000,
          'updated_at': 1789870000000,
        },
      ],
      'todos': [
        {
          'id': 20,
          'date': '2026-05-21',
          'title': 'Snapshot todo',
          'note': null,
          'due_time': null,
          'priority': 0,
          'is_completed': 1,
          'completed_at': 1789870100000,
          'created_at': 1789870000000,
          'updated_at': 1789870100000,
        },
      ],
      'projects': [
        {
          'id': 'project-snapshot',
          'name': 'Snapshot Project',
          'status': 'active',
          'goal': 'Restore from snapshot',
          'lastUpdate': '2026-05-21',
          'archiveLocation': 'snapshot://project-snapshot',
          'todos': [],
          'updates': [],
        },
      ],
      'settings': [
        {
          'key': 'dashboard_layout',
          'value': '{"cards":[]}',
          'updated_at': 1789870000000,
        },
        {
          'key': 'markdown_root_tree_uri',
          'value': 'content://old-folder',
          'updated_at': 1789870000000,
        },
      ],
    });

    final preview = await service.preview();
    expect(preview.fromSnapshot, isTrue);
    expect(preview.dailyNotes, 1);
    expect(preview.todos, 1);
    expect(preview.projects, 1);
    expect(preview.settings, 1);

    final first = await service.restore();
    final second = await service.restore();

    expect(first.fromSnapshot, isTrue);
    expect(first.recordsRestored, 1);
    expect(first.todosRestored, 1);
    expect(first.projectsRestored, 1);
    expect(first.settingsRestored, 1);
    expect(second.recordsRestored, 0);
    expect(second.todosRestored, 0);
    expect(second.projectsRestored, 0);

    final records = await recordsRepository.findAll();
    expect(records.single['content'], 'Snapshot memo');
    final metadata = jsonDecode(records.single['metadata'] as String) as Map;
    expect(metadata['restoredFromSnapshot'], isTrue);

    final todos = await todosRepository.findAll();
    expect(todos.single['title'], 'Snapshot todo');
    expect(todos.single['is_completed'], 1);

    expect(
      await settingsRepository.findByKey('markdown_root_tree_uri'),
      isNull,
    );
    final restoredSetting = await settingsRepository.findByKey(
      'dashboard_layout',
    );
    expect(restoredSetting?['value'], '{"cards":[]}');
  });

  test(
    'restores schema v2 structured tables with remapped foreign keys idempotently',
    () async {
      source.snapshot = jsonEncode({
        // Schema v2 contains attachment metadata only. It remains readable,
        // while v3 adds portable attachment entities.
        'schemaVersion': 2,
        'writtenAt': '2026-05-21T09:00:00.000',
        'records': [
          {
            'id': 10,
            'date': '2026-05-21',
            'type': 'moment_photo',
            'content': '公园照片',
            'time': '09:00',
            'tags': '[]',
            'metadata': '{}',
            'is_deleted': 0,
            'created_at': 1789870000000,
            'updated_at': 1789870000000,
          },
        ],
        'todos': [],
        'trackers': [
          {
            'id': 30,
            'name': '喝水',
            'unit': '杯',
            'target_value': 8.0,
            'color': '#2F6F73',
            'icon': 'water_drop',
            'is_archived': 0,
            'created_at': 1789870000001,
            'updated_at': 1789870000001,
          },
        ],
        'tracker_logs': [
          {
            'id': 40,
            'tracker_id': 30,
            'date': '2026-05-21',
            'value': 2.0,
            'note': '上午',
            'created_at': 1789870000002,
            'updated_at': 1789870000002,
          },
        ],
        'focus_sessions': [
          {
            'id': 50,
            'date': '2026-05-21',
            'started_at': 1789870000003,
            'ended_at': 1789871800003,
            'duration_minutes': 30,
            'note': '写作',
            'created_at': 1789870000003,
            'updated_at': 1789870000003,
          },
        ],
        'expenses': [
          {
            'id': 60,
            'date': '2026-05-21',
            'amount': 18.5,
            'category': '咖啡',
            'note': '拿铁',
            'currency': 'CNY',
            'created_at': 1789870000004,
            'updated_at': 1789870000004,
          },
        ],
        'body_logs': [
          {
            'id': 70,
            'date': '2026-05-21',
            'metric': 'weight',
            'value': 65.2,
            'unit': 'kg',
            'note': '晨起',
            'created_at': 1789870000005,
            'updated_at': 1789870000005,
          },
        ],
        'daily_reviews': [
          {
            'id': 80,
            'date': '2026-05-21',
            'kept': '早起',
            'adjust': '少刷手机',
            'next_action': '读书',
            'created_at': 1789870000006,
            'updated_at': 1789870000006,
          },
        ],
        'media_attachments': [
          {
            'id': 90,
            'record_id': 10,
            'media_type': 'image',
            'source_type': 'camera',
            'local_path': '/private/photo.jpg',
            'thumbnail_path': null,
            'width': 100,
            'height': 80,
            'duration_ms': null,
            'sort_order': 0,
            'created_at': 1789870000007,
            'updated_at': 1789870000007,
          },
        ],
        'projects': [],
        'settings': [],
      });

      final preview = await service.preview();
      expect(preview.fromSnapshot, isTrue);
      expect(preview.structuredData, 7);
      expect(preview.isEmpty, isFalse);

      final first = await service.restore();
      expect(first.recordsRestored, 1);
      expect(first.trackersRestored, 1);
      expect(first.trackerLogsRestored, 1);
      expect(first.focusSessionsRestored, 1);
      expect(first.expensesRestored, 1);
      expect(first.bodyLogsRestored, 1);
      expect(first.dailyReviewsRestored, 1);
      expect(first.mediaAttachmentsRestored, 1);

      final db = await database.database;
      final record = (await db.query('records')).single;
      final tracker = (await db.query('trackers')).single;
      final trackerLog = (await db.query('tracker_logs')).single;
      final attachment = (await db.query('media_attachments')).single;
      expect(trackerLog['tracker_id'], tracker['id']);
      expect(attachment['record_id'], record['id']);

      final second = await service.restore();
      expect(second.total, 0);
      expect(await db.query('records'), hasLength(1));
      expect(await db.query('trackers'), hasLength(1));
      expect(await db.query('tracker_logs'), hasLength(1));
      expect(await db.query('media_attachments'), hasLength(1));
    },
  );

  test(
    'writes schema v3 snapshots with portable media file descriptors',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'liflow-snapshot-media-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final sourcePhoto = File(p.join(tempDir.path, 'source.jpg'));
      final sourceBytes = <int>[1, 3, 3, 7, 9];
      await sourcePhoto.writeAsBytes(sourceBytes, flush: true);
      final now = DateTime(2026, 5, 21, 9);
      final recordId = await recordsRepository.create(
        date: now,
        type: 'moment_photo',
        content: '快照照片',
        createdAt: now,
      );
      final trackerId = await TrackersRepository(database).create(name: '喝水');
      await TrackerLogsRepository(
        database,
      ).create(trackerId: trackerId, date: now, value: 1, createdAt: now);
      await FocusSessionsRepository(
        database,
      ).create(date: now, startedAt: now, durationMinutes: 25, createdAt: now);
      await ExpensesRepository(
        database,
      ).create(date: now, amount: 12, category: '咖啡', createdAt: now);
      await BodyLogsRepository(
        database,
      ).create(date: now, metric: 'weight', value: 65, createdAt: now);
      await DailyReviewsRepository(
        database,
      ).create(date: '2026-05-21', kept: '早起', createdAt: now);
      await MediaAttachmentsRepository(database).create(
        recordId: recordId,
        mediaType: 'image',
        sourceType: 'camera',
        localPath: sourcePhoto.path,
        createdAt: now,
      );

      final storage = _CapturingStorageService(
        MarkdownDirectoryService(settingsRepository),
      );
      await BackupSnapshotService(
        directoryService: MarkdownDirectoryService(settingsRepository),
        database: database,
        storageService: storage,
      ).writeSnapshot();

      final snapshot = jsonDecode(storage.content!) as Map<String, dynamic>;
      expect(snapshot['schemaVersion'], BackupSnapshotService.schemaVersion);
      expect(snapshot['mediaBackup'], {
        'formatVersion': 1,
        'storageKind': 'localPath',
        'restoreSupport': 'full',
      });
      for (final key in const [
        'records',
        'todos',
        'trackers',
        'tracker_logs',
        'focus_sessions',
        'expenses',
        'body_logs',
        'daily_reviews',
        'media_attachments',
        'project_files',
        'projects',
        'settings',
      ]) {
        expect(
          snapshot[key],
          isA<List>(),
          reason: 'missing snapshot key: $key',
        );
      }
      expect(snapshot['records'], hasLength(1));
      expect(snapshot['trackers'], hasLength(1));
      expect(snapshot['tracker_logs'], hasLength(1));
      expect(snapshot['focus_sessions'], hasLength(1));
      expect(snapshot['expenses'], hasLength(1));
      expect(snapshot['body_logs'], hasLength(1));
      expect(snapshot['daily_reviews'], hasLength(1));
      expect(snapshot['media_attachments'], hasLength(1));
      final attachment = (snapshot['media_attachments'] as List).single as Map;
      final backupFiles = attachment['backup_files'] as Map;
      final mediaFile = backupFiles['local_path'] as Map;
      expect(mediaFile['status'], 'exported');
      expect(mediaFile['size'], sourceBytes.length);
      expect(mediaFile['sha256'], sha256.convert(sourceBytes).toString());
      expect(
        mediaFile['relativePath'],
        startsWith('${BackupSnapshotService.mediaBackupRoot}/'),
      );
      expect(storage.binaryWrites, hasLength(1));
      expect(storage.binaryWrites.single.sourcePath, sourcePhoto.path);
    },
  );

  test(
    'writes and restores project material files from the backup snapshot',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'liflow-project-file-restore-',
      );
      addTearDown(() => root.delete(recursive: true));
      final directoryService = MarkdownDirectoryService(settingsRepository);
      await directoryService.setRootPath(root.path);

      const bytes = <int>[7, 7, 1, 2, 9];
      final materialRelativePath = 'projects/Dayline-abc123/materials/spec.pdf';
      final materialFile = File(
        p.joinAll([root.path, ...materialRelativePath.split('/')]),
      );
      await materialFile.parent.create(recursive: true);
      await materialFile.writeAsBytes(bytes, flush: true);
      final project = {
        'id': 'project-abc123',
        'name': 'Dayline',
        'status': 'active',
        'goal': 'Keep files portable',
        'lastUpdate': '2026-05-21',
        'archiveLocation': 'fake://project',
        'todos': const <Object?>[],
        'updates': [
          {
            'id': 'file-update',
            'time': '2026-05-21',
            'createdAt': DateTime(2026, 5, 21).millisecondsSinceEpoch,
            'source': '文件',
            'text': 'spec.pdf',
            'entryType': 'file',
            'fileRelativePath': materialRelativePath,
            'mimeType': 'application/pdf',
          },
        ],
      };
      await settingsRepository.create(
        key: projectsSettingsKey,
        value: jsonEncode([project]),
      );

      await BackupSnapshotService(
        directoryService: directoryService,
        database: database,
      ).writeSnapshot();

      final snapshotFile = File(
        p.joinAll([
          root.path,
          ...BackupSnapshotService.snapshotRelativePath.split('/'),
        ]),
      );
      final snapshot = jsonDecode(await snapshotFile.readAsString()) as Map;
      final projectFiles = snapshot['project_files'] as List;
      expect(projectFiles, hasLength(1));
      expect(projectFiles.single['status'], 'exported');
      expect(projectFiles.single['targetRelativePath'], materialRelativePath);

      await materialFile.delete();
      expect(await materialFile.exists(), isFalse);

      final restoreService = MarkdownRestoreService(
        source: StorageMarkdownRestoreSource(
          directoryService: directoryService,
        ),
        database: database,
        recordsRepository: recordsRepository,
        settingsRepository: settingsRepository,
      );
      final first = await restoreService.restore();

      expect(first.projectFilesRestored, 1);
      expect(first.projectFilesUnavailable, 0);
      expect(await materialFile.readAsBytes(), bytes);

      final second = await restoreService.restore();
      expect(second.projectFilesRestored, 0);
      expect(second.projectFilesUnavailable, 0);
    },
  );

  test(
    'restores schema v3 media bytes to a device-local path idempotently',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'liflow-restore-media-',
      );
      addTearDown(() => root.delete(recursive: true));
      final directoryService = MarkdownDirectoryService(settingsRepository);
      await directoryService.setRootPath(root.path);

      final bytes = <int>[9, 8, 7, 6, 5, 4];
      final digest = sha256.convert(bytes).toString();
      final backupRelativePath = p.posix.join(
        BackupSnapshotService.mediaBackupRoot,
        '90',
        'media_${digest.substring(0, 16)}.jpg',
      );
      final backupFile = File(
        p.joinAll([root.path, ...backupRelativePath.split('/')]),
      );
      await backupFile.parent.create(recursive: true);
      await backupFile.writeAsBytes(bytes, flush: true);

      final snapshot = _portableMediaSnapshot(
        backupRelativePath: backupRelativePath,
        size: bytes.length,
        sha256Hex: digest,
      );
      final snapshotFile = File(
        p.joinAll([
          root.path,
          ...BackupSnapshotService.snapshotRelativePath.split('/'),
        ]),
      );
      await snapshotFile.parent.create(recursive: true);
      await snapshotFile.writeAsString(jsonEncode(snapshot), flush: true);

      final restoreService = MarkdownRestoreService(
        source: StorageMarkdownRestoreSource(
          directoryService: directoryService,
        ),
        database: database,
        recordsRepository: recordsRepository,
        settingsRepository: settingsRepository,
      );

      final first = await restoreService.restore();
      expect(first.recordsRestored, 1);
      expect(first.mediaAttachmentsRestored, 1);
      expect(first.mediaAttachmentsUnavailable, 0);

      final db = await database.database;
      final attachment = (await db.query('media_attachments')).single;
      final restoredPath = attachment['local_path'] as String;
      expect(p.isWithin(root.path, restoredPath), isTrue);
      expect(
        p.relative(restoredPath, from: root.path).replaceAll('\\', '/'),
        startsWith('documents/photos/2026-05/'),
      );
      expect(await File(restoredPath).readAsBytes(), bytes);

      final second = await restoreService.restore();
      expect(second.total, 0);
      expect(second.mediaAttachmentsUnavailable, 0);
      expect(await db.query('media_attachments'), hasLength(1));
      expect(await File(restoredPath).readAsBytes(), bytes);
    },
  );

  test(
    'skips a corrupted media entity and reports it as unavailable',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'liflow-restore-corrupt-media-',
      );
      addTearDown(() => root.delete(recursive: true));
      final directoryService = MarkdownDirectoryService(settingsRepository);
      await directoryService.setRootPath(root.path);

      const bytes = <int>[1, 2, 3];
      final expectedDigest = sha256.convert(const <int>[4, 5, 6]).toString();
      final backupRelativePath = p.posix.join(
        BackupSnapshotService.mediaBackupRoot,
        '90',
        'media_${expectedDigest.substring(0, 16)}.jpg',
      );
      final backupFile = File(
        p.joinAll([root.path, ...backupRelativePath.split('/')]),
      );
      await backupFile.parent.create(recursive: true);
      await backupFile.writeAsBytes(bytes, flush: true);

      final snapshotFile = File(
        p.joinAll([
          root.path,
          ...BackupSnapshotService.snapshotRelativePath.split('/'),
        ]),
      );
      await snapshotFile.parent.create(recursive: true);
      await snapshotFile.writeAsString(
        jsonEncode(
          _portableMediaSnapshot(
            backupRelativePath: backupRelativePath,
            size: bytes.length,
            sha256Hex: expectedDigest,
          ),
        ),
        flush: true,
      );

      final result = await MarkdownRestoreService(
        source: StorageMarkdownRestoreSource(
          directoryService: directoryService,
        ),
        database: database,
        recordsRepository: recordsRepository,
        settingsRepository: settingsRepository,
      ).restore();

      expect(result.recordsRestored, 1);
      expect(result.mediaAttachmentsRestored, 0);
      expect(result.mediaAttachmentsUnavailable, 1);
      final db = await database.database;
      expect(await db.query('media_attachments'), isEmpty);
    },
  );
}

Map<String, Object?> _portableMediaSnapshot({
  required String backupRelativePath,
  required int size,
  required String sha256Hex,
}) {
  final createdAt = DateTime(2026, 5, 21, 9).millisecondsSinceEpoch;
  return {
    'schemaVersion': BackupSnapshotService.schemaVersion,
    'writtenAt': '2026-05-21T09:00:00.000',
    'records': [
      {
        'id': 10,
        'date': '2026-05-21',
        'type': 'moment_photo',
        'content': 'portable photo',
        'time': '09:00',
        'tags': '[]',
        'metadata': '{}',
        'is_deleted': 0,
        'created_at': createdAt,
        'updated_at': createdAt,
      },
    ],
    'media_attachments': [
      {
        'id': 90,
        'record_id': 10,
        'media_type': 'image',
        'source_type': 'camera',
        'local_path': '/old-device/photo.jpg',
        'thumbnail_path': null,
        'width': 100,
        'height': 80,
        'duration_ms': null,
        'sort_order': 0,
        'created_at': createdAt,
        'updated_at': createdAt,
        'backup_files': {
          'local_path': {
            'status': 'exported',
            'relativePath': backupRelativePath,
            'size': size,
            'sha256': sha256Hex,
            'mimeType': 'image/jpeg',
          },
        },
      },
    ],
    'todos': const <Object?>[],
    'trackers': const <Object?>[],
    'tracker_logs': const <Object?>[],
    'focus_sessions': const <Object?>[],
    'expenses': const <Object?>[],
    'body_logs': const <Object?>[],
    'daily_reviews': const <Object?>[],
    'project_files': const <Object?>[],
    'projects': const <Object?>[],
    'settings': const <Object?>[],
  };
}

class _CapturingStorageService extends MarkdownStorageService {
  _CapturingStorageService(super.directoryService);

  String? content;
  final binaryWrites =
      <({String relativePath, String sourcePath, String mimeType})>[];

  @override
  Future<void> writeRelativeBinaryFile({
    required String relativePath,
    required String sourcePath,
    required String mimeType,
  }) async {
    binaryWrites.add((
      relativePath: relativePath,
      sourcePath: sourcePath,
      mimeType: mimeType,
    ));
  }

  @override
  Future<String> writeRelativeTextFile({
    required String relativePath,
    required String content,
    String? mimeType,
  }) async {
    this.content = content;
    return 'fake://$relativePath';
  }
}

class _FakeRestoreSource implements MarkdownRestoreSource {
  _FakeRestoreSource(this.files);

  final Map<String, String> files;
  String? snapshot;

  @override
  Future<List<MarkdownRestoreFile>> listMarkdownFiles() async {
    return [
      for (final entry in files.entries)
        MarkdownRestoreFile(
          relativePath: entry.key,
          location: locationFor(entry.key),
          updatedAt: DateTime(2026, 5, 21).millisecondsSinceEpoch,
        ),
    ];
  }

  @override
  Future<String> readFile(String location) async {
    final path = location.replaceFirst('fake://', '');
    return files[path]!;
  }

  @override
  Future<String?> readBackupSnapshot() async => snapshot;

  String locationFor(String relativePath) => 'fake://$relativePath';
}
