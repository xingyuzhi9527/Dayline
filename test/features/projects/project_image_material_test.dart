import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/features/projects/project_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late AppSettingsRepository settings;
  late Directory rootDir;
  late Directory sourceDir;
  late ProviderContainer container;

  setUp(() async {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    settings = AppSettingsRepository(database);
    rootDir = await Directory.systemTemp.createTemp('liflow-project-image-');
    sourceDir = await Directory.systemTemp.createTemp(
      'liflow-project-image-source-',
    );
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
    if (await sourceDir.exists()) {
      await sourceDir.delete(recursive: true);
    }
  });

  test(
    'adding a project image stores the file under the project without timeline record',
    () async {
      final source = File(
        '${sourceDir.path}${Platform.pathSeparator}draft.png',
      );
      await source.writeAsBytes(const [137, 80, 78, 71]);
      final createdAt = DateTime(2026, 5, 30, 9, 8, 7, 6);

      final material = await addProjectImageMaterial(
        container,
        projectId: 'project-12345678',
        projectName: '毕业论文',
        sourceImagePath: source.path,
        title: '访谈原图',
        createdAt: createdAt,
      );

      expect(
        material.relativePath,
        'projects/毕业论文-12345678/materials/毕业论文-5.30-访谈原图.png',
      );
      expect(await File(material.localPath).exists(), isTrue);

      final records = await container
          .read(recordsRepositoryProvider)
          .findByDate(createdAt);
      expect(records, isEmpty);

      final row = await settings.findByKey(projectsSettingsKey);
      final projects = jsonDecode(row!['value'] as String) as List;
      final project = projects.single as Map<String, Object?>;
      final updates = project['updates'] as List;
      final update = updates.single as Map<String, Object?>;

      expect(update['source'], '图片资料');
      expect(update['entryType'], 'image');
      expect(update['imageRelativePath'], material.relativePath);
      expect(update['imagePath'], material.localPath);

      final archiveLocation = project['archiveLocation'] as String;
      final archive = await File(archiveLocation).readAsString();
      expect(archive, contains('图片资料'));
      expect(archive, contains('materials/毕业论文-5.30-访谈原图.png'));
    },
  );

  test(
    'renaming a project image updates the display name without changing file path or timeline',
    () async {
      final source = File(
        '${sourceDir.path}${Platform.pathSeparator}draft.jpg',
      );
      await source.writeAsBytes(const [1, 2, 3, 4]);
      final createdAt = DateTime(2026, 5, 30, 9, 8, 7, 6);
      final material = await addProjectImageMaterial(
        container,
        projectId: 'project-12345678',
        projectName: '毕业论文',
        sourceImagePath: source.path,
        title: '原始照片',
        createdAt: createdAt,
      );
      final oldLocalPath = material.localPath;

      await updateProjectImageMaterialName(
        container,
        projectId: 'project-12345678',
        projectName: '毕业论文',
        imageRelativePath: material.relativePath,
        title: '访谈照片',
        updatedAt: createdAt.add(const Duration(minutes: 1)),
      );

      final records = await container
          .read(recordsRepositoryProvider)
          .findByDate(createdAt);
      expect(records, isEmpty);

      final row = await settings.findByKey(projectsSettingsKey);
      final projects = jsonDecode(row!['value'] as String) as List;
      final project = projects.single as Map<String, Object?>;
      final updates = project['updates'] as List;
      final update = updates.single as Map<String, Object?>;

      expect(update['text'], '毕业论文-5.30-访谈照片.jpg');
      expect(
        update['imageRelativePath'],
        'projects/毕业论文-12345678/materials/毕业论文-5.30-访谈照片.jpg',
      );
      expect(await File(oldLocalPath).exists(), isFalse);
      expect(await File(update['imagePath'] as String).exists(), isTrue);

      final archive = await File(
        project['archiveLocation'] as String,
      ).readAsString();
      expect(archive, contains('毕业论文-5.30-访谈照片.jpg'));
      expect(archive, contains('materials/毕业论文-5.30-访谈照片.jpg'));
    },
  );
}
