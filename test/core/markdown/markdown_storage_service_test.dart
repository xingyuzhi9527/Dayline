import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/markdown/markdown_directory_service.dart';
import 'package:liflow_app/core/markdown/markdown_storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late Directory rootDir;
  late MarkdownStorageService service;

  setUp(() async {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    rootDir = await Directory.systemTemp.createTemp('liflow-markdown-');
    final settings = AppSettingsRepository(database);
    await settings.create(key: 'markdown_root_path', value: rootDir.path);
    service = MarkdownStorageService(MarkdownDirectoryService(settings));
  });

  tearDown(() async {
    await database.close();
    if (await rootDir.exists()) await rootDir.delete(recursive: true);
  });

  test('writes a new local text file and leaves no sidecars', () async {
    final location = await service.writeRelativeTextFile(
      relativePath: 'daily/2026-05/2026-05-21.md',
      content: '# First',
    );

    final target = File(location);
    expect(await target.readAsString(), '# First');
    expect(await _sidecar(target, '.liflow-tmp').exists(), isFalse);
    expect(await _sidecar(target, '.liflow-backup').exists(), isFalse);
  });

  test(
    'replaces an existing local file without truncating on failure',
    () async {
      final location = await service.writeRelativeTextFile(
        relativePath: 'notes/replace.md',
        content: 'before',
      );
      final target = File(location);
      final missingSource = File(
        '${rootDir.path}${Platform.pathSeparator}missing-source.bin',
      );

      await expectLater(
        service.writeRelativeBinaryFile(
          relativePath: 'notes/replace.md',
          sourcePath: missingSource.path,
          mimeType: 'application/octet-stream',
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await target.readAsString(), 'before');
      expect(await _sidecar(target, '.liflow-tmp').exists(), isFalse);
      expect(await _sidecar(target, '.liflow-backup').exists(), isFalse);
    },
  );

  test(
    'replaces an existing local binary file through a temporary copy',
    () async {
      final source = File('${rootDir.path}${Platform.pathSeparator}source.bin');
      await source.writeAsBytes(const [1, 2, 3]);
      await service.writeRelativeBinaryFile(
        relativePath: 'documents/replace.bin',
        sourcePath: source.path,
        mimeType: 'application/octet-stream',
      );
      final target = File(
        '${rootDir.path}${Platform.pathSeparator}documents${Platform.pathSeparator}replace.bin',
      );

      await source.writeAsBytes(const [9, 8, 7, 6]);
      await service.writeRelativeBinaryFile(
        relativePath: 'documents/replace.bin',
        sourcePath: source.path,
        mimeType: 'application/octet-stream',
      );

      expect(await target.readAsBytes(), const [9, 8, 7, 6]);
      expect(await _sidecar(target, '.liflow-tmp').exists(), isFalse);
      expect(await _sidecar(target, '.liflow-backup').exists(), isFalse);
    },
  );

  test(
    'repairs a backup and temporary file left by an interrupted write',
    () async {
      final location = await service.writeRelativeTextFile(
        relativePath: 'notes/interrupted.md',
        content: 'current',
      );
      final target = File(location);
      final backup = _sidecar(target, '.liflow-backup');
      final temporary = _sidecar(target, '.liflow-tmp');

      await target.rename(backup.path);
      await temporary.writeAsString('partial replacement');

      expect(await service.readTextFileLocation(location), 'current');
      expect(await backup.exists(), isFalse);
      expect(await temporary.exists(), isFalse);
    },
  );

  test('restores a missing target from backup before the next write', () async {
    final location = await service.writeRelativeTextFile(
      relativePath: 'notes/recover-before-write.md',
      content: 'old',
    );
    final target = File(location);
    final backup = _sidecar(target, '.liflow-backup');
    final temporary = _sidecar(target, '.liflow-tmp');
    await target.rename(backup.path);
    await temporary.writeAsString('partial replacement');

    await service.writeTextFileLocation(location, 'new');

    expect(await target.readAsString(), 'new');
    expect(await backup.exists(), isFalse);
    expect(await temporary.exists(), isFalse);
  });
}

File _sidecar(File target, String suffix) => File('${target.path}$suffix');
