import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/features/projects/project_store.dart';
import 'package:liflow_app/features/restore/markdown_restore_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
''',
    });
    service = MarkdownRestoreService(
      source: source,
      recordsRepository: recordsRepository,
      todosRepository: todosRepository,
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
    },
  );

  test('prefers backup snapshot and restores todos and settings', () async {
    source.snapshot = jsonEncode({
      'schemaVersion': BackupSnapshotService.schemaVersion,
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
