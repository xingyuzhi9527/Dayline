import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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

  Database? _database;

  Future<Database> get database async {
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

  Future<Database> _open() async {
    final databaseRoot = await getDatabasesPath();
    final databasePath = p.join(databaseRoot, _databaseName);

    return openDatabase(
      databasePath,
      version: _databaseVersion,
      onCreate: _createSchema,
    );
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
CREATE TABLE app_meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
  }
}
