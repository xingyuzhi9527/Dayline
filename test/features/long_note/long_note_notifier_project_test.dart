import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/features/long_note/long_note_notifier.dart';
import 'package:liflow_app/features/projects/project_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late AppSettingsRepository settings;
  late Directory rootDir;
  late ProviderContainer container;

  setUp(() async {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    settings = AppSettingsRepository(database);
    rootDir = await Directory.systemTemp.createTemp('liflow-long-note-');
    await settings.create(key: 'markdown_root_path', value: rootDir.path);
    await settings.create(
      key: projectsSettingsKey,
      value: jsonEncode([
        {
          'id': 'project-12345678',
          'name': '毕业论文',
          'status': '进行中',
          'goal': '完成初稿',
          'lastUpdate': '刚刚',
          'todos': [],
          'updates': [],
        },
      ]),
    );
    container = ProviderContainer(
      overrides: [localDatabaseProvider.overrideWithValue(database)],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    if (await rootDir.exists()) {
      await rootDir.delete(recursive: true);
    }
  });

  test(
    'saving a project long note stores a short project update reference',
    () async {
      final saved = await container
          .read(longNoteProvider.notifier)
          .save(
            '文献综述思路',
            '正文很长，不应该进入项目最近更新。',
            project: const ProjectOption(id: 'project-12345678', name: '毕业论文'),
          );

      expect(saved, isTrue);

      final records = await container
          .read(recordsRepositoryProvider)
          .findByDate(DateTime.now());
      final record = records.single;
      final metadata = jsonDecode(record['metadata'] as String) as Map;
      expect(metadata['projectId'], 'project-12345678');
      expect(metadata['projectName'], '毕业论文');
      expect(metadata['projectEntryType'], 'long_note');
      expect(
        (metadata['path'] as String).replaceAll('\\', '/'),
        contains('/projects/毕业论文-12345678/notes/'),
      );
      expect(metadata['fileName'], contains('文献综述思路.md'));

      final row = await settings.findByKey(projectsSettingsKey);
      final projects = jsonDecode(row!['value'] as String) as List;
      final project = projects.single as Map<String, Object?>;
      final updates = project['updates'] as List;
      final update = updates.single as Map<String, Object?>;

      expect(update['source'], '长笔记');
      expect(update['text'], '文献综述思路');
      expect(update['entryType'], 'long_note');
      expect(update['notePath'], metadata['path']);
      expect(update['noteFileName'], contains('文献综述思路.md'));
      expect(
        (update['noteRelativePath'] as String).replaceAll('\\', '/'),
        contains('projects/毕业论文-12345678/notes/'),
      );
      expect(update['recordId'], record['id']);

      final archive = await File(
        project['archiveLocation'] as String,
      ).readAsString();
      expect(archive, contains('文献综述思路.md'));
      expect(archive, contains('(notes/${update['noteFileName'] as String})'));
    },
  );
}
