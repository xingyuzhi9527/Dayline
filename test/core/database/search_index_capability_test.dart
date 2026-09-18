import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'Given FFI SQLite, when probing FTS5 trigram, then MATCH works',
    () async {
      final version = await database.rawQuery('SELECT sqlite_version() AS v');
      final compileOptions = await database.rawQuery('PRAGMA compile_options');

      expect(version.single['v'], isA<String>());
      expect(compileOptions, isNotEmpty);

      await database.transaction((txn) async {
        await txn.execute('''
CREATE VIRTUAL TABLE temp.records_fts_probe USING fts5(
  content,
  tokenize='trigram'
)
''');
        await txn.insert('records_fts_probe', {'content': '记录一次中文搜索'});

        final rows = await txn.rawQuery(
          'SELECT rowid FROM records_fts_probe WHERE records_fts_probe MATCH ?',
          ['"中文搜"'],
        );
        expect(rows, hasLength(1));

        await txn.execute('DROP TABLE temp.records_fts_probe');
      });
    },
  );

  test(
    'Given unsupported tokenizer, when probe DDL fails, then transaction commits fallback schema',
    () async {
      await database.transaction((txn) async {
        await txn.execute(
          'CREATE TABLE migration_marker (value TEXT NOT NULL)',
        );

        Object? probeError;
        try {
          await txn.execute('''
CREATE VIRTUAL TABLE temp.records_fts_probe USING fts5(
  content,
  tokenize='liflow_missing_tokenizer'
)
''');
        } catch (error) {
          probeError = error;
        } finally {
          await txn.execute('DROP TABLE IF EXISTS temp.records_fts_probe');
        }

        expect(probeError, isNotNull);
        await txn.insert('migration_marker', {'value': 'like_fallback'});
      });

      final marker = await database.query('migration_marker');
      expect(marker.single['value'], 'like_fallback');
    },
  );
}
