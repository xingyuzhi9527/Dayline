import 'package:sqflite/sqflite.dart' as sqflite;

typedef SearchCapabilityProbe =
    Future<bool> Function(sqflite.DatabaseExecutor database);

class SearchIndexSchema {
  SearchIndexSchema({SearchCapabilityProbe? capabilityProbe})
    : _capabilityProbe = capabilityProbe;

  static const indexName = 'records';
  static const schemaVersion = 1;
  static const stateTable = 'search_index_state';
  static const ftsTable = 'records_fts';

  final SearchCapabilityProbe? _capabilityProbe;

  Future<void> install(sqflite.DatabaseExecutor database) async {
    await _createStateTable(database);

    var supported = false;
    String? error;
    try {
      supported = await (_capabilityProbe ?? probeFts5Trigram)(database);
    } catch (exception) {
      error = _shortError(exception);
    }

    if (!supported) {
      await cleanupFtsObjects(database);
      await writeState(
        database,
        backend: 'like_fallback',
        status: 'ready',
        lastError: error ?? 'FTS5 trigram is unavailable',
      );
      return;
    }

    try {
      await cleanupFtsObjects(database);
      await _createFtsTable(database);
      await _createTriggers(database);
      await writeState(database, backend: 'fts5_trigram', status: 'pending');
    } catch (exception) {
      await cleanupFtsObjects(database);
      await writeState(
        database,
        backend: 'like_fallback',
        status: 'ready',
        lastError: _shortError(exception),
      );
    }
  }

  Future<bool> probeFts5Trigram(sqflite.DatabaseExecutor database) async {
    try {
      await database.rawQuery('SELECT sqlite_version()');
      await database.rawQuery('PRAGMA compile_options');
      await database.execute('''
CREATE VIRTUAL TABLE temp.records_fts_probe USING fts5(
  content,
  tokenize='trigram'
)
''');
      await database.insert('records_fts_probe', {'content': '中文搜索探针'});
      final match = await database.rawQuery(
        'SELECT rowid FROM records_fts_probe WHERE records_fts_probe MATCH ?',
        ['"中文搜"'],
      );
      return match.length == 1;
    } catch (_) {
      return false;
    } finally {
      await database.execute('DROP TABLE IF EXISTS temp.records_fts_probe');
    }
  }

  Future<void> cleanupFtsObjects(sqflite.DatabaseExecutor database) async {
    await database.execute('DROP TRIGGER IF EXISTS records_fts_ai');
    await database.execute('DROP TRIGGER IF EXISTS records_fts_ad');
    await database.execute('DROP TRIGGER IF EXISTS records_fts_au');
    await database.execute('DROP TABLE IF EXISTS $ftsTable');
  }

  Future<void> writeState(
    sqflite.DatabaseExecutor database, {
    required String backend,
    required String status,
    int? lastRebuiltAt,
    String? lastError,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.rawInsert(
      '''
INSERT INTO $stateTable (
  index_name,
  backend,
  status,
  schema_version,
  last_rebuilt_at,
  last_error,
  updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(index_name) DO UPDATE SET
  backend = excluded.backend,
  status = excluded.status,
  schema_version = excluded.schema_version,
  last_rebuilt_at = excluded.last_rebuilt_at,
  last_error = excluded.last_error,
  updated_at = excluded.updated_at
''',
      [
        indexName,
        backend,
        status,
        schemaVersion,
        lastRebuiltAt,
        lastError,
        now,
      ],
    );
  }

  Future<void> _createStateTable(sqflite.DatabaseExecutor database) {
    return database.execute('''
CREATE TABLE IF NOT EXISTS $stateTable (
  index_name TEXT PRIMARY KEY NOT NULL,
  backend TEXT NOT NULL,
  status TEXT NOT NULL,
  schema_version INTEGER NOT NULL,
  last_rebuilt_at INTEGER,
  last_error TEXT,
  updated_at INTEGER NOT NULL
)
''');
  }

  Future<void> _createFtsTable(sqflite.DatabaseExecutor database) {
    return database.execute('''
CREATE VIRTUAL TABLE $ftsTable USING fts5(
  content,
  tags,
  metadata,
  content='records',
  content_rowid='id',
  tokenize='trigram'
)
''');
  }

  Future<void> _createTriggers(sqflite.DatabaseExecutor database) async {
    await database.execute('''
CREATE TRIGGER records_fts_ai AFTER INSERT ON records BEGIN
  INSERT INTO $ftsTable(rowid, content, tags, metadata)
  VALUES (new.id, new.content, new.tags, new.metadata);
END
''');
    await database.execute('''
CREATE TRIGGER records_fts_ad AFTER DELETE ON records BEGIN
  INSERT INTO $ftsTable($ftsTable, rowid, content, tags, metadata)
  VALUES ('delete', old.id, old.content, old.tags, old.metadata);
END
''');
    await database.execute('''
CREATE TRIGGER records_fts_au AFTER UPDATE ON records BEGIN
  INSERT INTO $ftsTable($ftsTable, rowid, content, tags, metadata)
  VALUES ('delete', old.id, old.content, old.tags, old.metadata);
  INSERT INTO $ftsTable(rowid, content, tags, metadata)
  VALUES (new.id, new.content, new.tags, new.metadata);
END
''');
  }
}

String _shortError(Object error) {
  final message = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (message.length <= 300) return message;
  return message.substring(0, 300);
}
