import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'search_index_schema.dart';

final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final database = LocalDatabase();

  ref.onDispose(() {
    unawaited(database.close());
  });

  return database;
});

class LocalDatabase {
  static const _databaseName = 'liflow.db';
  static const _databaseVersion = 8;
  static final _transactionExecutorKey = Object();

  LocalDatabase({
    sqflite.DatabaseFactory? databaseFactory,
    String? databasePath,
    SearchIndexSchema? searchIndexSchema,
  }) : _databaseFactory = databaseFactory ?? sqflite.databaseFactory,
       _databasePath = databasePath,
       searchIndexSchema = searchIndexSchema ?? SearchIndexSchema();

  final sqflite.DatabaseFactory _databaseFactory;
  final String? _databasePath;
  final SearchIndexSchema searchIndexSchema;

  sqflite.Database? _database;

  sqflite.DatabaseExecutor? get _transactionExecutor =>
      Zone.current[_transactionExecutorKey] as sqflite.DatabaseExecutor?;

  Future<sqflite.Database> get database async {
    final openedDatabase = _database;
    if (openedDatabase != null && openedDatabase.isOpen) {
      return openedDatabase;
    }

    final nextDatabase = await _open();
    _database = nextDatabase;
    return nextDatabase;
  }

  /// Returns the active transaction executor when called from [transaction].
  ///
  /// Repositories use this instead of opening their own executor so an entire
  /// cross-repository write can be committed or rolled back as one unit.
  Future<sqflite.DatabaseExecutor> get executor async =>
      _transactionExecutor ?? await database;

  Future<T> transaction<T>(Future<T> Function() action) async {
    if (_transactionExecutor != null) {
      return action();
    }

    final db = await database;
    return db.transaction(
      (txn) => runZoned(action, zoneValues: {_transactionExecutorKey: txn}),
    );
  }

  Future<void> close() async {
    final openedDatabase = _database;
    if (openedDatabase == null) {
      return;
    }

    await openedDatabase.close();
    _database = null;
  }

  Future<sqflite.Database> _open() async {
    final configuredPath = _databasePath;
    final databasePath = configuredPath ?? await _defaultDatabasePath();

    return _databaseFactory.openDatabase(
      databasePath,
      options: sqflite.OpenDatabaseOptions(
        version: _databaseVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
  }

  Future<String> _defaultDatabasePath() async {
    final databaseRoot = await _databaseFactory.getDatabasesPath();
    return p.join(databaseRoot, _databaseName);
  }

  Future<void> _createSchema(sqflite.Database db, int version) async {
    await db.execute('''
CREATE TABLE records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  type TEXT NOT NULL,
  content TEXT NOT NULL,
  time TEXT,
  tags TEXT NOT NULL DEFAULT '[]',
  metadata TEXT NOT NULL DEFAULT '{}',
  is_deleted INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE todos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  title TEXT NOT NULL,
  note TEXT,
  due_time TEXT,
  priority INTEGER NOT NULL DEFAULT 0,
  is_completed INTEGER NOT NULL DEFAULT 0,
  completed_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE trackers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  unit TEXT,
  target_value REAL,
  color TEXT,
  icon TEXT,
  is_archived INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE tracker_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tracker_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  value REAL NOT NULL DEFAULT 1,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (tracker_id) REFERENCES trackers (id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE focus_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  duration_minutes INTEGER NOT NULL,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE expenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  amount REAL NOT NULL,
  category TEXT NOT NULL,
  note TEXT,
  currency TEXT NOT NULL DEFAULT 'CNY',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE body_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  metric TEXT NOT NULL,
  value REAL NOT NULL,
  unit TEXT,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE app_settings (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await db.execute('CREATE INDEX idx_records_date ON records (date)');
    await db.execute('CREATE INDEX idx_todos_date ON todos (date)');
    await db.execute(
      'CREATE INDEX idx_tracker_logs_date ON tracker_logs (date)',
    );
    await db.execute(
      'CREATE INDEX idx_focus_sessions_date ON focus_sessions (date)',
    );
    await db.execute('CREATE INDEX idx_expenses_date ON expenses (date)');
    await db.execute('CREATE INDEX idx_body_logs_date ON body_logs (date)');

    await db.execute('''
CREATE TABLE daily_reviews (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL UNIQUE,
  kept TEXT NOT NULL DEFAULT '',
  adjust TEXT NOT NULL DEFAULT '',
  next_action TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await db.execute(
      'CREATE INDEX idx_daily_reviews_date ON daily_reviews (date)',
    );

    await db.execute('''
CREATE TABLE media_attachments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  record_id INTEGER NOT NULL,
  media_type TEXT NOT NULL,
  source_type TEXT NOT NULL DEFAULT 'unknown',
  local_path TEXT NOT NULL,
  thumbnail_path TEXT,
  width INTEGER,
  height INTEGER,
  duration_ms INTEGER,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (record_id) REFERENCES records (id) ON DELETE CASCADE
)
''');

    await db.execute(
      'CREATE INDEX idx_media_attachments_record_id ON media_attachments (record_id)',
    );

    await _createWriteOperationsSchema(db);
    await _createDerivedSyncJobsSchema(db);
    await _createLibraryItemsSchema(db);
    await searchIndexSchema.install(db);
  }

  Future<void> _upgradeSchema(
    sqflite.Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('''
CREATE TABLE daily_reviews (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL UNIQUE,
  kept TEXT NOT NULL DEFAULT '',
  adjust TEXT NOT NULL DEFAULT '',
  next_action TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
      await db.execute(
        'CREATE INDEX idx_daily_reviews_date ON daily_reviews (date)',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE records ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 4) {
      await db.execute('''
CREATE TABLE media_attachments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  record_id INTEGER NOT NULL,
  media_type TEXT NOT NULL,
  source_type TEXT NOT NULL DEFAULT 'unknown',
  local_path TEXT NOT NULL,
  thumbnail_path TEXT,
  width INTEGER,
  height INTEGER,
  duration_ms INTEGER,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (record_id) REFERENCES records (id) ON DELETE CASCADE
)
''');
      await db.execute(
        'CREATE INDEX idx_media_attachments_record_id ON media_attachments (record_id)',
      );
    }
    if (oldVersion < 5) {
      await _createWriteOperationsSchema(db);
    }
    if (oldVersion < 6) {
      await _createDerivedSyncJobsSchema(db);
    }
    if (oldVersion < 7) {
      await _createLibraryItemsSchema(db);
    }
    if (oldVersion < 8) {
      await searchIndexSchema.install(db);
    }
  }

  Future<void> _createWriteOperationsSchema(sqflite.DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS write_operations (
  operation_id TEXT PRIMARY KEY NOT NULL,
  operation_type TEXT NOT NULL,
  fingerprint TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'committed', 'completed')),
  result_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE (operation_type, fingerprint)
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_write_operations_status ON write_operations (status, updated_at)',
    );
  }

  Future<void> _createDerivedSyncJobsSchema(sqflite.DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS derived_sync_jobs (
  job_key TEXT PRIMARY KEY NOT NULL,
  job_type TEXT NOT NULL,
  payload_json TEXT NOT NULL DEFAULT '{}',
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_derived_sync_jobs_updated ON derived_sync_jobs (updated_at)',
    );
  }

  Future<void> _createLibraryItemsSchema(sqflite.DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS library_items (
  item_key TEXT PRIMARY KEY NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('markdown', 'document')),
  name TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  location TEXT NOT NULL,
  mime_type TEXT,
  size_bytes INTEGER,
  updated_at INTEGER,
  source_type TEXT NOT NULL DEFAULT 'scan',
  is_favorite INTEGER NOT NULL DEFAULT 0,
  indexed_at INTEGER NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_items_kind_updated ON library_items (kind, updated_at)',
    );
  }
}
