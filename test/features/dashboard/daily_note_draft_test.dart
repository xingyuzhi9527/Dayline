import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/core/markdown/markdown_directory_service.dart';
import 'package:liflow_app/core/markdown/markdown_note_service.dart';
import 'package:liflow_app/features/dashboard/daily_note_draft.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late ProviderContainer container;
  late Directory rootDir;

  setUp(() async {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    container = ProviderContainer(
      overrides: [localDatabaseProvider.overrideWithValue(database)],
    );
    rootDir = await Directory.systemTemp.createTemp('liflow-daily-draft-');
    await MarkdownDirectoryService(
      container.read(appSettingsRepositoryProvider),
    ).setRootPath(rootDir.path);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    if (await rootDir.exists()) {
      await rootDir.delete(recursive: true);
    }
  });

  test('updates existing draft front matter without replacing body', () async {
    final day = DateTime(2026, 6, 4);
    await container
        .read(recordsRepositoryProvider)
        .create(date: day, type: 'memo', content: '第一条');
    await ensureDailyDraftAfterActivity(container, day);

    await container
        .read(expensesRepositoryProvider)
        .create(date: day, amount: 35, category: '午饭');
    await ensureDailyDraftAfterActivity(container, day);

    final noteService = MarkdownNoteService(
      MarkdownDirectoryService(container.read(appSettingsRepositoryProvider)),
    );
    final raw = await noteService.readDailyNote(day);

    expect(raw, contains('status: draft'));
    expect(raw, contains('record_count: 2'));
    expect(raw, contains('## 今日概览'));
  });

  test('does not rewrite final daily note', () async {
    final day = DateTime(2026, 6, 4);
    final noteService = MarkdownNoteService(
      MarkdownDirectoryService(container.read(appSettingsRepositoryProvider)),
    );
    await noteService.saveDailyNote(day, '''
---
date: 2026-06-04
status: final
record_count: 1
---

# final note
''');

    await container
        .read(recordsRepositoryProvider)
        .create(date: day, type: 'memo', content: '新增记录');
    await ensureDailyDraftAfterActivity(container, day);

    final raw = await noteService.readDailyNote(day);
    expect(raw, contains('status: final'));
    expect(raw, contains('record_count: 1'));
    expect(raw, contains('# final note'));
  });
}
