import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/local_database.dart';
import '../../../core/database/search_index_schema.dart';

class SearchIndexState {
  const SearchIndexState({
    required this.backend,
    required this.status,
    required this.schemaVersion,
    required this.updatedAt,
    this.lastRebuiltAt,
    this.lastError,
  });

  final String backend;
  final String status;
  final int schemaVersion;
  final int updatedAt;
  final int? lastRebuiltAt;
  final String? lastError;

  bool get isFtsReady => backend == 'fts5_trigram' && status == 'ready';
  bool get isBuilding => status == 'building';

  factory SearchIndexState.fromRow(Map<String, Object?> row) {
    return SearchIndexState(
      backend: row['backend'] as String,
      status: row['status'] as String,
      schemaVersion: row['schema_version'] as int,
      updatedAt: row['updated_at'] as int,
      lastRebuiltAt: row['last_rebuilt_at'] as int?,
      lastError: row['last_error'] as String?,
    );
  }
}

class SearchIndexService {
  SearchIndexService(this._database, {SearchIndexSchema? schema})
    : _schema = schema ?? _database.searchIndexSchema;

  final LocalDatabase _database;
  final SearchIndexSchema _schema;
  Future<SearchIndexState>? _ensureOperation;

  Future<SearchIndexState> readState() async {
    final database = await _database.executor;
    final rows = await database.query(
      SearchIndexSchema.stateTable,
      where: 'index_name = ?',
      whereArgs: [SearchIndexSchema.indexName],
      limit: 1,
    );
    if (rows.isEmpty) {
      await _schema.writeState(
        database,
        backend: 'like_fallback',
        status: 'failed',
        lastError: 'Search index state is missing',
      );
      return readState();
    }
    return SearchIndexState.fromRow(rows.single);
  }

  Future<SearchIndexState> ensureReady() {
    final active = _ensureOperation;
    if (active != null) return active;

    final operation = _ensureReady();
    _ensureOperation = operation;
    operation.whenComplete(() {
      if (identical(_ensureOperation, operation)) {
        _ensureOperation = null;
      }
    });
    return operation;
  }

  Future<SearchIndexState> _ensureReady() async {
    final state = await readState();
    if (state.isFtsReady ||
        (state.backend == 'like_fallback' && state.status == 'ready')) {
      return state;
    }
    return rebuild();
  }

  Future<SearchIndexState> rebuild() async {
    final database = await _database.executor;
    if (!await _hasFtsSchema()) {
      await _schema.writeState(
        database,
        backend: 'like_fallback',
        status: 'ready',
        lastError: 'FTS5 trigram schema is unavailable',
      );
      return readState();
    }

    await _schema.writeState(
      database,
      backend: 'fts5_trigram',
      status: 'building',
    );

    try {
      final rebuiltAt = DateTime.now().millisecondsSinceEpoch;
      await _database.transaction(() async {
        final transaction = await _database.executor;
        await transaction.rawInsert(
          "INSERT INTO records_fts(records_fts) VALUES('rebuild')",
        );
        await _runIntegrityCheck(transaction);
        await _schema.writeState(
          transaction,
          backend: 'fts5_trigram',
          status: 'ready',
          lastRebuiltAt: rebuiltAt,
        );
      });
    } catch (error) {
      await _schema.writeState(
        database,
        backend: 'like_fallback',
        status: 'failed',
        lastError: _shortError(error),
      );
    }
    return readState();
  }

  Future<bool> verifyIntegrity() async {
    if (!await _hasFtsSchema()) return false;
    try {
      final database = await _database.executor;
      await _runIntegrityCheck(database);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<SearchIndexState> repairAfterRestore() async {
    final state = await readState();
    if (state.backend == 'like_fallback' && state.status == 'ready') {
      return state;
    }
    if (await verifyIntegrity()) return state;
    return rebuild();
  }

  Future<void> markQueryFailure(Object error) async {
    final database = await _database.executor;
    await _schema.writeState(
      database,
      backend: 'like_fallback',
      status: 'failed',
      lastError: _shortError(error),
    );
  }

  Future<bool> _hasFtsSchema() async {
    final database = await _database.executor;
    final rows = await database.rawQuery(
      '''
SELECT sql FROM sqlite_master
WHERE type = 'table' AND name = ? AND sql LIKE '%fts5%'
''',
      [SearchIndexSchema.ftsTable],
    );
    return rows.isNotEmpty;
  }

  Future<void> _runIntegrityCheck(sqflite.DatabaseExecutor database) async {
    await database.rawInsert(
      "INSERT INTO records_fts(records_fts, rank) VALUES('integrity-check', 1)",
    );
  }
}

String _shortError(Object error) {
  final value = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  return value.length <= 300 ? value : value.substring(0, 300);
}
