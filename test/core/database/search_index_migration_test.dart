import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/search_index_schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'Given a fresh install, when opened, then database v8 is pending FTS',
    () async {
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);

      final db = await database.database;
      final state = await db.query(SearchIndexSchema.stateTable);

      expect(await db.getVersion(), 8);
      expect(state.single['backend'], 'fts5_trigram');
      expect(state.single['status'], 'pending');
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'records_fts'",
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'Given a v7 database, when upgraded, then record fields are unchanged',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'liflow-v8-migration-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final path = p.join(directory.path, 'legacy.db');

      final legacy = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      final legacyDb = await legacy.database;
      const original = <String, Object?>{
        'id': 42,
        'date': '2026-07-19',
        'type': 'memo',
        'content': '保留原文',
        'time': '08:05',
        'tags': '["边界"]',
        'metadata': '{"projectId":"project-1"}',
        'is_deleted': 1,
        'created_at': 100,
        'updated_at': 200,
      };
      await legacyDb.insert('records', original);
      await legacy.searchIndexSchema.cleanupFtsObjects(legacyDb);
      await legacyDb.execute('DROP TABLE search_index_state');
      await legacyDb.execute('PRAGMA user_version = 7');
      await legacy.close();

      final upgraded = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(upgraded.close);
      final db = await upgraded.database;

      expect(await db.getVersion(), 8);
      expect((await db.query('records')).single, original);
      expect(
        (await db.query(SearchIndexSchema.stateTable)).single['status'],
        'pending',
      );
    },
  );

  test(
    'Given FTS is unavailable, when v8 opens, then LIKE fallback can write',
    () async {
      final schema = SearchIndexSchema(capabilityProbe: (_) async => false);
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
        searchIndexSchema: schema,
      );
      addTearDown(database.close);
      final records = RecordsRepository(database);

      final id = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: '降级仍然可写',
      );
      final db = await database.database;
      final state = (await db.query(SearchIndexSchema.stateTable)).single;

      expect(await db.getVersion(), 8);
      expect(state['backend'], 'like_fallback');
      expect(state['status'], 'ready');
      expect(await records.findById(id), containsPair('content', '降级仍然可写'));
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name LIKE 'records_fts%'",
        ),
        isEmpty,
      );
    },
  );
}
