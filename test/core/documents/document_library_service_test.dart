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
  late RecordsRepository recordsRepository;
  late LibraryItemsRepository libraryItemsRepository;
  late Directory rootDir;
  late DocumentLibraryService service;

  setUp(() async {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    settingsRepository = AppSettingsRepository(database);
    recordsRepository = RecordsRepository(database);
    libraryItemsRepository = LibraryItemsRepository(database);
    rootDir = await Directory.systemTemp.createTemp('liflow-docs-root-');
    await settingsRepository.create(
      key: 'markdown_root_path',
      value: rootDir.path,
    );

    final dirService = MarkdownDirectoryService(settingsRepository);
    service = DocumentLibraryService(
      settingsRepository: settingsRepository,
      recordsRepository: recordsRepository,
      libraryItemsRepository: libraryItemsRepository,
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

  test('load reuses persisted snapshot before rescanning filesystem', () async {
    final notesDir = Directory(
      '${rootDir.path}${Platform.pathSeparator}notes${Platform.pathSeparator}2026-05',
    );
    await notesDir.create(recursive: true);
    await File(
      '${notesDir.path}${Platform.pathSeparator}cached.md',
    ).writeAsString('# Cached');

    final firstSnapshot = await service.load();
    expect(firstSnapshot.notes.map((item) => item.name), contains('cached.md'));

    await notesDir.delete(recursive: true);
    final secondService = DocumentLibraryService(
      settingsRepository: settingsRepository,
      recordsRepository: recordsRepository,
      directoryService: MarkdownDirectoryService(settingsRepository),
      storageService: MarkdownStorageService(
        MarkdownDirectoryService(settingsRepository),
      ),
    );

    final persistedSnapshot = await secondService.load();

    expect(
      persistedSnapshot.notes.map((item) => item.name),
      contains('cached.md'),
    );
  });

  test('load reuses SQLite index before rescanning filesystem', () async {
    final notesDir = Directory(
      '${rootDir.path}${Platform.pathSeparator}notes${Platform.pathSeparator}2026-05',
    );
    await notesDir.create(recursive: true);
    await File(
      '${notesDir.path}${Platform.pathSeparator}indexed.md',
    ).writeAsString('# Indexed');

    final firstSnapshot = await service.load(forceRefresh: true);
    expect(
      firstSnapshot.notes.map((item) => item.name),
      contains('indexed.md'),
    );

    await settingsRepository.delete('document_library_snapshot_v1');
    await notesDir.delete(recursive: true);
    final secondService = DocumentLibraryService(
      settingsRepository: settingsRepository,
      recordsRepository: recordsRepository,
      libraryItemsRepository: libraryItemsRepository,
      directoryService: MarkdownDirectoryService(settingsRepository),
      storageService: MarkdownStorageService(
        MarkdownDirectoryService(settingsRepository),
      ),
    );

    final indexedSnapshot = await secondService.load();

    expect(
      indexedSnapshot.notes.map((item) => item.name),
      contains('indexed.md'),
    );
  });

  test('load handles 2000 indexed library items', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await libraryItemsRepository.replaceAll([
      for (var i = 0; i < 2000; i++)
        {
          'item_key': 'markdown:location:indexed-$i',
          'kind': 'markdown',
          'name': 'indexed-$i.md',
          'relative_path': 'notes/indexed-$i.md',
          'location':
              '${rootDir.path}${Platform.pathSeparator}notes${Platform.pathSeparator}indexed-$i.md',
          'mime_type': 'text/markdown',
          'size_bytes': i,
          'updated_at': now - i,
          'source_type': 'local',
          'is_favorite': 0,
          'indexed_at': now,
        },
    ]);

    final snapshot = await service.load();

    expect(snapshot.notes, hasLength(2000));
    expect(snapshot.documents, isEmpty);
    expect(snapshot.notes.first.name, 'indexed-0.md');
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

  test('load includes normal long note records in notes', () async {
    final noteDir = Directory(
      '${rootDir.path}${Platform.pathSeparator}notes${Platform.pathSeparator}2026-06',
    );
    await noteDir.create(recursive: true);
    final file = File('${noteDir.path}${Platform.pathSeparator}ordinary.md');
    await file.writeAsString('# 普通长笔记\n\n正文');

    await recordsRepository.create(
      date: DateTime(2026, 6, 30),
      type: 'long_note',
      content: '普通长笔记',
      metadata: {
        'path': file.path,
        'title': '普通长笔记',
        'fileName': 'ordinary.md',
        'relativePath': 'notes/2026-06/ordinary.md',
      },
      createdAt: DateTime(2026, 6, 30, 10),
    );

    final snapshot = await service.load();

    expect(snapshot.notes.map((item) => item.name), contains('ordinary.md'));
  });

  test('load returns daily favorites and excludes project favorites', () async {
    await recordsRepository.create(
      date: DateTime(2026, 6, 30),
      type: 'memo',
      content: '值得收藏的日常记录',
      tags: const ['收藏'],
      createdAt: DateTime(2026, 6, 30, 10),
    );
    await recordsRepository.create(
      date: DateTime(2026, 6, 30),
      type: 'memo',
      content: '项目收藏记录',
      tags: const ['收藏'],
      metadata: const {'projectId': 'project-1'},
      createdAt: DateTime(2026, 6, 30, 11),
    );

    final snapshot = await service.load();

    expect(snapshot.favoriteRecords, hasLength(1));
    expect(snapshot.favoriteRecords.single.title, '值得收藏的日常记录');
  });

  test('setFavoriteNote adds markdown note to favorites', () async {
    final notesDir = Directory(
      '${rootDir.path}${Platform.pathSeparator}notes${Platform.pathSeparator}2026-06',
    );
    await notesDir.create(recursive: true);
    final file = File('${notesDir.path}${Platform.pathSeparator}idea.md');
    await file.writeAsString('# Idea');

    final snapshot = await service.load();
    final note = snapshot.notes.singleWhere((item) => item.name == 'idea.md');

    await service.setFavoriteNote(item: note, favorite: true);

    final afterFavorite = await service.load();
    final favoriteNote = afterFavorite.notes.singleWhere(
      (item) => item.name == 'idea.md',
    );
    expect(favoriteNote.isFavorite, isTrue);
    expect(afterFavorite.favoriteRecords.map((item) => item.fileName), [
      'idea.md',
    ]);

    await service.setFavoriteNote(item: favoriteNote, favorite: false);

    final afterRemove = await service.load();
    expect(
      afterRemove.notes
          .singleWhere((item) => item.name == 'idea.md')
          .isFavorite,
      isFalse,
    );
    expect(afterRemove.favoriteRecords, isEmpty);
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
