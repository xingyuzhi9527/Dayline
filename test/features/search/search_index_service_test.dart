import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/features/search/data/search_index_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late LocalDatabase database;
  late RecordsRepository records;
  late SearchIndexService service;

  setUp(() {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    records = RecordsRepository(database);
    service = SearchIndexService(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<List<int>> matches(String query) async {
    final db = await database.database;
    final rows = await db.rawQuery(
      '''
SELECT r.id
FROM records_fts
JOIN records r ON r.id = records_fts.rowid
WHERE records_fts MATCH ? AND r.is_deleted = 0
ORDER BY r.id
''',
      ['"$query"'],
    );
    return rows.map((row) => row['id'] as int).toList();
  }

  test(
    'Given pending historical rows, when ensureReady runs, then index is ready',
    () async {
      final db = await database.database;
      await db.rawInsert(
        '''
INSERT INTO records(date, type, content, tags, metadata, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?)
''',
        ['2026-07-19', 'memo', '历史中文记录', '[]', '{}', 1, 1],
      );

      final state = await service.ensureReady();

      expect(state.isFtsReady, isTrue);
      expect(await matches('中文记'), hasLength(1));
      expect(await service.verifyIntegrity(), isTrue);
    },
  );

  test(
    'Given a ready index, when rebuilt twice, then documents are not duplicated',
    () async {
      final id = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: '重复重建测试',
      );

      await service.rebuild();
      await service.rebuild();

      expect(await matches('重建测'), [id]);
    },
  );

  test(
    'Given trigger-managed records, when changed, then FTS follows source rows',
    () async {
      await service.ensureReady();
      final id = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: '旧的搜索关键词',
        tags: const ['初始标签'],
        metadata: const {'projectName': '旧项目'},
      );
      expect(await matches('旧的搜'), [id]);

      await records.updateDetails(
        id,
        content: '新的搜索关键词',
        tags: const ['新的标签'],
        metadata: const {'projectName': '新项目'},
      );
      expect(await matches('旧的搜'), isEmpty);
      expect(await matches('新的搜'), [id]);
      expect(await matches('新的标'), [id]);
      expect(await matches('新项目'), [id]);

      await records.softDelete(id);
      expect(await matches('新的搜'), isEmpty);
      await records.restore(id);
      expect(await matches('新的搜'), [id]);

      await records.permanentDelete(id);
      expect(await matches('新的搜'), isEmpty);
      expect(await service.verifyIntegrity(), isTrue);
    },
  );

  test(
    'Given missing index entries, when repaired, then source rows are unchanged',
    () async {
      final id = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: '损坏后自动修复',
      );
      await service.ensureReady();
      final before = await records.findById(id);
      final db = await database.database;
      await db.execute(
        "INSERT INTO records_fts(records_fts) VALUES('delete-all')",
      );

      expect(await service.verifyIntegrity(), isFalse);
      final state = await service.repairAfterRestore();

      expect(state.isFtsReady, isTrue);
      expect(await records.findById(id), before);
      expect(await matches('自动修'), [id]);
    },
  );
}
