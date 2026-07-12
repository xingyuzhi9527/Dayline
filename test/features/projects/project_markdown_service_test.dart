import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/features/projects/project_markdown_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'replaying one operation does not duplicate project archive entries',
    () async {
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final root = await Directory.systemTemp.createTemp(
        'liflow-project-archive-idempotency-',
      );
      addTearDown(database.close);
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final settings = AppSettingsRepository(database);
      await settings.create(key: 'markdown_root_path', value: root.path);
      final service = ProjectMarkdownService(settings);
      final updatedAt = DateTime(2026, 7, 12, 9, 30);
      final project = <String, Object?>{
        'id': 'project-idempotent',
        'name': '幂等项目',
        'status': '进行中',
        'goal': '只写一次',
        'lastUpdate': '刚刚',
        'todos': const [],
        'updates': const [],
      };
      const operationId = 'request-123';
      final entry = ProjectArchiveEntry(
        text: '完成持久化幂等',
        source: '文本记录',
        createdAt: updatedAt,
        operationId: operationId,
      );

      final location = await service.syncArchive(
        project: project,
        entry: entry,
        entryAsMajor: true,
        updatedAt: updatedAt,
      );
      await service.syncArchive(
        project: {
          ...project,
          ProjectMarkdownService.archiveLocationKey: location,
        },
        entry: entry,
        entryAsMajor: true,
        updatedAt: updatedAt,
      );

      final content = await File(location).readAsString();
      expect(
        RegExp('<!-- dayline:operation:$operationId -->').allMatches(content),
        hasLength(2),
        reason: 'The log and major sections each keep one operation marker.',
      );
      expect(RegExp('文本记录：完成持久化幂等').allMatches(content), hasLength(1));
      expect(RegExp('### 2026-07-12 09:30').allMatches(content), hasLength(1));
    },
  );
}
