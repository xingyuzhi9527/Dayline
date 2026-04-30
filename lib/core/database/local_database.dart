import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final database = LocalDatabase();

  ref.onDispose(() {
    unawaited(database.close());
  });

  return database;
});

class LocalDatabase {
  static const _databaseName = 'dayline.db';
  static const _databaseVersion = 1;

  LocalDatabase({
    sqflite.DatabaseFactory? databaseFactory,
    String? databasePath,
  }) : _databaseFactory = databaseFactory ?? sqflite.databaseFactory,
       _databasePath = databasePath;

  final sqflite.DatabaseFactory _databaseFactory;
  final String? _databasePath;

  sqflite.Database? _database;

  Future<sqflite.Database> get database async {
    final openedDatabase = _database;
    if (openedDatabase != null && openedDatabase.isOpen) {
      return openedDatabase;
    }

    final nextDatabase = await _open();
    _database = nextDatabase;
    return nextDatabase;
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
  }
}
