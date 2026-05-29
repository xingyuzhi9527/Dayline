import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/documents/document_library_service.dart';
import 'package:liflow_app/core/markdown/markdown_directory_service.dart';
import 'package:liflow_app/core/markdown/markdown_storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late AppSettingsRepository settingsRepository;
  late Directory rootDir;
  late DocumentLibraryService service;

  setUp(() async {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    settingsRepository = AppSettingsRepository(database);
    rootDir = await Directory.systemTemp.createTemp('liflow-docs-root-');
    await settingsRepository.create(
      key: 'markdown_root_path',
      value: rootDir.path,
    );

    final dirService = MarkdownDirectoryService(settingsRepository);
    service = DocumentLibraryService(
      settingsRepository: settingsRepository,
      directoryService: dirService,
      storageService: MarkdownStorageService(dirService),
    );
  });

  tearDown(() async {
    await database.close();
    if (await rootDir.exists()) {
      await rootDir.delete(recursive: true);
    }
  });

  test('load creates Liflow core folders and lists notes and documents', () async {
    final dailyDir = Directory(
      '${rootDir.path}${Platform.pathSeparator}daily${Platform.pathSeparator}2026-05',
    );
    final notesDir = Directory(
      '${rootDir.path}${Platform.pathSeparator}notes${Platform.pathSeparator}2026-05',
    );
    final documentsDir = Directory(
      '${rootDir.path}${Platform.pathSeparator}documents',
    );
    await dailyDir.create(recursive: true);
    await notesDir.create(recursive: true);
    await documentsDir.create(recursive: true);
    await File(
      '${dailyDir.path}${Platform.pathSeparator}2026-05-17.md',
    ).writeAsString('# Daily');
    await File(
      '${notesDir.path}${Platform.pathSeparator}note.md',
    ).writeAsString('# Note');
    await File(
      '${documentsDir.path}${Platform.pathSeparator}paper.pdf',
    ).writeAsBytes(const [1, 2, 3]);

    final snapshot = await service.load();

    expect(
      Directory('${rootDir.path}${Platform.pathSeparator}daily').existsSync(),
      isTrue,
    );
    expect(
      Directory('${rootDir.path}${Platform.pathSeparator}notes').existsSync(),
      isTrue,
    );
    expect(
      Directory(
        '${rootDir.path}${Platform.pathSeparator}documents',
      ).existsSync(),
      isTrue,
    );
    expect(
      snapshot.notes.map((item) => item.name),
      containsAll(['2026-05-17.md', 'note.md']),
    );
    expect(snapshot.documents.map((item) => item.name), contains('paper.pdf'));
    expect(snapshot.favoriteFolders, isEmpty);
  });

  test('deleteDocument removes imported copy from documents folder', () async {
    final documentsDir = Directory(
      '${rootDir.path}${Platform.pathSeparator}documents',
    );
    await documentsDir.create(recursive: true);
    final file = File('${documentsDir.path}${Platform.pathSeparator}paper.pdf');
    await file.writeAsBytes(const [1, 2, 3]);

    final snapshot = await service.load();
    final item = snapshot.documents.singleWhere(
      (item) => item.name == 'paper.pdf',
    );

    await service.deleteDocument(item);

    expect(await file.exists(), isFalse);
    final afterDelete = await service.load();
    expect(
      afterDelete.documents.map((item) => item.name),
      isNot(contains('paper.pdf')),
    );
  });

  test('load returns stored favorite folders', () async {
    await settingsRepository.create(
      key: 'document_favorite_folders',
      value:
          '[{"id":"folder-1","treeUri":"content://folder","name":"报销资料","createdAt":1}]',
    );

    final snapshot = await service.load();

    expect(snapshot.favoriteFolders, hasLength(1));
    expect(snapshot.favoriteFolders.single.name, '报销资料');
    expect(snapshot.favoriteFolders.single.treeUri, 'content://folder');
  });
}
