import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/markdown/markdown_directory_service.dart';
import 'package:liflow_app/core/markdown/markdown_note_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late AppSettingsRepository settings;
  late Directory rootDir;
  late MarkdownNoteService service;

  setUp(() async {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    settings = AppSettingsRepository(database);
    rootDir = await Directory.systemTemp.createTemp('liflow-project-note-');
    await settings.create(key: 'markdown_root_path', value: rootDir.path);
    service = MarkdownNoteService(MarkdownDirectoryService(settings));
  });

  tearDown(() async {
    await database.close();
    if (await rootDir.exists()) {
      await rootDir.delete(recursive: true);
    }
  });

  test('saves project long notes inside the project notes folder', () async {
    final location = await service.saveLongNote(
      title: '文献综述思路',
      body: '先按主题分组。',
      dateTime: DateTime(2026, 5, 19, 8, 30),
      projectId: 'project-12345678',
      projectName: '毕业论文',
    );

    expect(
      location.replaceAll('\\', '/'),
      contains('projects/毕业论文-12345678/notes/2026-05-19_08-30_文献综述思路.md'),
    );

    final content = await File(location).readAsString();
    expect(content, contains('project_id: "project-12345678"'));
    expect(content, contains('project_name: "毕业论文"'));
    expect(content, contains('# 文献综述思路'));
  });
}
