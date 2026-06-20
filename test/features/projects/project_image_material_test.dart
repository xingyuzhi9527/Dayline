import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/features/projects/project_store.dart';
import 'package:path/path.dart' as p;
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
    'adding a project file stores it under materials and links it from project archive',
    () async {
      final source = File(
        '${sourceDir.path}${Platform.pathSeparator}brief.pdf',
      );
      await source.writeAsBytes(const [37, 80, 68, 70]);
      final createdAt = DateTime(2026, 5, 31, 10, 11, 12, 13);

      final material = await addProjectFileMaterial(
        container,
        projectId: 'project-12345678',
        projectName: '毕业论文',
        sourceFilePath: source.path,
        createdAt: createdAt,
      );

      expect(
        material.relativePath,
        'projects/毕业论文-12345678/materials/brief.pdf',
      );
      expect(material.fileName, 'brief.pdf');
      expect(material.mimeType, 'application/pdf');
      expect(await File(material.localPath!).exists(), isTrue);

      final records = await container
          .read(recordsRepositoryProvider)
          .findByDate(createdAt);
      expect(records, isEmpty);

      final row = await settings.findByKey(projectsSettingsKey);
      final projects = jsonDecode(row!['value'] as String) as List;
      final project = projects.single as Map<String, Object?>;
      final updates = project['updates'] as List;
      final update = updates.single as Map<String, Object?>;

      expect(update['source'], '文件');
      expect(update['text'], 'brief.pdf');
      expect(update['entryType'], 'file');
      expect(update['fileRelativePath'], material.relativePath);
      expect(update['filePath'], material.localPath);
      expect(update['mimeType'], 'application/pdf');

      final archive = await File(
        project['archiveLocation'] as String,
      ).readAsString();
      expect(archive, contains('文件'));
      expect(archive, contains('[文件](materials/brief.pdf)'));
    },
  );

  test(
    'adding a markdown project file stores it under project notes',
    () async {
      final source = File(
        '${sourceDir.path}${Platform.pathSeparator}meeting.md',
      );
      await source.writeAsString('# 会议记录\n\n下一步整理访谈。');
      final createdAt = DateTime(2026, 5, 31, 10, 12, 13, 14);

      final material = await addProjectFileMaterial(
        container,
        projectId: 'project-12345678',
        projectName: '毕业论文',
        sourceFilePath: source.path,
        createdAt: createdAt,
      );

      expect(material.relativePath, 'projects/毕业论文-12345678/notes/meeting.md');
      expect(material.fileName, 'meeting.md');
      expect(material.mimeType, 'text/markdown');
      expect(await File(material.localPath!).exists(), isTrue);

      final row = await settings.findByKey(projectsSettingsKey);
      final projects = jsonDecode(row!['value'] as String) as List;
      final project = projects.single as Map<String, Object?>;
      final updates = project['updates'] as List;
      final update = updates.single as Map<String, Object?>;

      expect(update['source'], '文件');
      expect(update['entryType'], 'file');
      expect(update['fileRelativePath'], material.relativePath);

      final archive = await File(
        project['archiveLocation'] as String,
      ).readAsString();
      expect(archive, contains('[文件](notes/meeting.md)'));
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

  test(
    'adding multiple project images stores them in one materials folder',
    () async {
      final first = File('${sourceDir.path}${Platform.pathSeparator}draft.png');
      final second = File(
        '${sourceDir.path}${Platform.pathSeparator}draft.jpg',
      );
      await first.writeAsBytes(const [1, 1, 1]);
      await second.writeAsBytes(const [2, 2, 2]);
      final createdAt = DateTime(2026, 5, 30, 9, 8, 7, 6);

      final material = await addProjectImageMaterials(
        container,
        projectId: 'project-12345678',
        projectName: '姣曚笟璁烘枃',
        sourceImagePaths: [first.path, second.path],
        title: '鎵归噺璧勬枡',
        createdAt: createdAt,
      );

      expect(material.allRelativePaths, hasLength(2));
      expect(material.allLocalPaths, hasLength(2));
      expect(material.allRelativePaths.first, endsWith('/draft.png'));
      expect(material.allRelativePaths.last, endsWith('/draft.jpg'));
      expect(
        p.posix.dirname(material.allRelativePaths.first),
        p.posix.dirname(material.allRelativePaths.last),
      );
      expect(
        p.posix.dirname(material.allRelativePaths.first),
        contains('/materials/'),
      );
      expect(await File(material.allLocalPaths.first).exists(), isTrue);
      expect(await File(material.allLocalPaths.last).exists(), isTrue);

      final row = await settings.findByKey(projectsSettingsKey);
      final projects = jsonDecode(row!['value'] as String) as List;
      final project = projects.single as Map<String, Object?>;
      final updates = project['updates'] as List;
      final update = updates.single as Map<String, Object?>;

      expect(update['entryType'], 'image');
      expect(update['imagePath'], material.allLocalPaths.first);
      expect(update['imageRelativePath'], material.allRelativePaths.first);
      expect(update['imagePaths'], material.allLocalPaths);
      expect(update['imageRelativePaths'], material.allRelativePaths);
      expect(update['text'], contains('2张'));

      final records = await container
          .read(recordsRepositoryProvider)
          .findByDate(createdAt);
      expect(records, isEmpty);
    },
  );

  test(
    'deleting project image material removes update and image files',
    () async {
      final first = File('${sourceDir.path}${Platform.pathSeparator}draft.png');
      final second = File(
        '${sourceDir.path}${Platform.pathSeparator}draft.jpg',
      );
      await first.writeAsBytes(const [1, 1, 1]);
      await second.writeAsBytes(const [2, 2, 2]);
      final createdAt = DateTime(2026, 5, 30, 9, 8, 7, 6);

      final material = await addProjectImageMaterials(
        container,
        projectId: 'project-12345678',
        projectName: '毕业论文',
        sourceImagePaths: [first.path, second.path],
        title: '批量资料',
        createdAt: createdAt,
      );
      final folder = Directory(p.dirname(material.allLocalPaths.first));
      expect(await folder.exists(), isTrue);

      await deleteProjectImageMaterial(
        container,
        projectId: 'project-12345678',
        imageRelativePath: material.allRelativePaths.first,
        updatedAt: createdAt.add(const Duration(minutes: 1)),
      );

      final row = await settings.findByKey(projectsSettingsKey);
      final projects = jsonDecode(row!['value'] as String) as List;
      final project = projects.single as Map<String, Object?>;
      expect(project['updates'] as List, isEmpty);
      expect(await File(material.allLocalPaths.first).exists(), isFalse);
      expect(await File(material.allLocalPaths.last).exists(), isFalse);
      expect(await folder.exists(), isFalse);

      final archive = await File(
        project['archiveLocation'] as String,
      ).readAsString();
      expect(archive, contains('## 最近更新\n_暂无最近更新。_'));
    },
  );
}
