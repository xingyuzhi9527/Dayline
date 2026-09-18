import 'dart:convert';

import 'local_database.dart';

typedef DatabaseRow = Map<String, Object?>;

String dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

int timestamp(DateTime dateTime) => dateTime.millisecondsSinceEpoch;

abstract class Repository {
  Repository(this.localDatabase, this.tableName);

  final LocalDatabase localDatabase;
  final String tableName;

  Future<int> insert(DatabaseRow values) async {
    final db = await localDatabase.executor;
    return db.insert(tableName, values);
  }

  Future<DatabaseRow?> findById(int id) async {
    final db = await localDatabase.executor;
    final rows = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<DatabaseRow>> findAll() async {
    final db = await localDatabase.executor;
    return db.query(tableName, orderBy: 'id ASC');
  }

  Future<int> update(int id, DatabaseRow values) async {
    final db = await localDatabase.executor;
    return db.update(tableName, values, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(int id) async {
    final db = await localDatabase.executor;
    return db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  DatabaseRow withTimestamps(DatabaseRow values, {DateTime? createdAt}) {
    final writtenAt = timestamp(createdAt ?? DateTime.now());
    return {
      ...values,
      'created_at': values['created_at'] ?? writtenAt,
      'updated_at': values['updated_at'] ?? writtenAt,
    };
  }
}

class RecordsRepository extends Repository {
  RecordsRepository(LocalDatabase localDatabase)
    : super(localDatabase, 'records');

  Future<int> create({
    required DateTime date,
    required String type,
    required String content,
    String? time,
    List<String> tags = const [],
    Map<String, Object?> metadata = const {},
    DateTime? createdAt,
  }) {
    return insert(
      withTimestamps({
        'date': dateKey(date),
        'type': type,
        'content': content,
        'time': time,
        'tags': jsonEncode(tags),
        'metadata': jsonEncode(metadata),
      }, createdAt: createdAt),
    );
  }

  Future<List<DatabaseRow>> findByDate(DateTime date) async {
    final db = await localDatabase.executor;
    return db.query(
      tableName,
      where: 'date = ? AND is_deleted = 0',
      whereArgs: [dateKey(date)],
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<int> countByDate(DateTime date) async {
    final db = await localDatabase.executor;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM records WHERE date = ? AND is_deleted = 0',
      [dateKey(date)],
    );
    return (rows.single['cnt'] as int);
  }

  Future<int> softDelete(int id, {DateTime? updatedAt}) {
    return update(id, {
      'is_deleted': 1,
      'updated_at': timestamp(updatedAt ?? DateTime.now()),
    });
  }

  Future<int> restore(int id, {DateTime? updatedAt}) {
    return update(id, {
      'is_deleted': 0,
      'updated_at': timestamp(updatedAt ?? DateTime.now()),
    });
  }

  Future<List<DatabaseRow>> findDeleted({int limit = 50}) async {
    final db = await localDatabase.executor;
    return db.query(
      tableName,
      where: 'is_deleted = 1',
      orderBy: 'updated_at DESC, id DESC',
      limit: limit,
    );
  }

  Future<int> permanentDelete(int id) async {
    final db = await localDatabase.executor;
    return db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateDetails(
    int id, {
    required String content,
    String? time,
    List<String> tags = const [],
    Map<String, Object?> metadata = const {},
    DateTime? updatedAt,
  }) {
    return update(id, {
      'content': content,
      'time': time,
      'tags': jsonEncode(tags),
      'metadata': jsonEncode(metadata),
      'updated_at': timestamp(updatedAt ?? DateTime.now()),
    });
  }

  Future<List<DatabaseRow>> findRecent({int limit = 3}) async {
    final db = await localDatabase.executor;
    return db.query(
      tableName,
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
  }

  Future<List<String>> findDistinctTypes() async {
    final db = await localDatabase.executor;
    final rows = await db.rawQuery('''
SELECT DISTINCT type
FROM records
WHERE is_deleted = 0 AND TRIM(type) <> ''
ORDER BY type COLLATE NOCASE ASC
''');
    return rows
        .map((row) => row['type'])
        .whereType<String>()
        .toList(growable: false);
  }

  Future<List<DatabaseRow>> findDocumentLibraryCandidates() async {
    final db = await localDatabase.executor;
    return db.query(
      tableName,
      columns: const [
        'id',
        'type',
        'content',
        'tags',
        'metadata',
        'is_deleted',
        'created_at',
        'updated_at',
      ],
      where:
          'is_deleted = 0 AND (type = ? OR tags LIKE ? OR tags LIKE ? OR metadata LIKE ? OR metadata LIKE ? OR metadata LIKE ?)',
      whereArgs: const [
        'long_note',
        '%收藏%',
        '%favorite%',
        '%"favorite"%',
        '%"isFavorite"%',
        '%"is_favorite"%',
      ],
      orderBy: 'created_at DESC, id DESC',
    );
  }
}

class MediaAttachmentsRepository extends Repository {
  MediaAttachmentsRepository(LocalDatabase localDatabase)
    : super(localDatabase, 'media_attachments');

  Future<int> create({
    required int recordId,
    required String mediaType,
    required String sourceType,
    required String localPath,
    String? thumbnailPath,
    int? width,
    int? height,
    int? durationMs,
    int sortOrder = 0,
    DateTime? createdAt,
  }) {
    return insert(
      withTimestamps({
        'record_id': recordId,
        'media_type': mediaType,
        'source_type': sourceType,
        'local_path': localPath,
        'thumbnail_path': thumbnailPath,
        'width': width,
        'height': height,
        'duration_ms': durationMs,
        'sort_order': sortOrder,
      }, createdAt: createdAt),
    );
  }

  Future<List<DatabaseRow>> findByRecordId(int recordId) async {
    final db = await localDatabase.executor;
    return db.query(
      tableName,
      where: 'record_id = ?',
      whereArgs: [recordId],
      orderBy: 'sort_order ASC, created_at ASC, id ASC',
    );
  }

  Future<Map<int, List<DatabaseRow>>> findByRecordIds(
    List<int> recordIds,
  ) async {
    if (recordIds.isEmpty) return const {};

    final db = await localDatabase.executor;
    final placeholders = List.filled(recordIds.length, '?').join(', ');
    final rows = await db.query(
      tableName,
      where: 'record_id IN ($placeholders)',
      whereArgs: recordIds,
      orderBy: 'record_id ASC, sort_order ASC, created_at ASC, id ASC',
    );

    final grouped = <int, List<DatabaseRow>>{};
    for (final row in rows) {
      final recordId = row['record_id'] as int;
      grouped.putIfAbsent(recordId, () => <DatabaseRow>[]).add(row);
    }
    return grouped;
  }
}

class TodosRepository extends Repository {
  TodosRepository(LocalDatabase localDatabase) : super(localDatabase, 'todos');

  Future<int> create({
    required DateTime date,
    required String title,
    String? note,
    String? dueTime,
    int priority = 0,
    DateTime? createdAt,
  }) {
    return insert(
      withTimestamps({
        'date': dateKey(date),
        'title': title,
        'note': note,
        'due_time': dueTime,
        'priority': priority,
        'is_completed': 0,
        'completed_at': null,
      }, createdAt: createdAt),
    );
  }

  Future<List<DatabaseRow>> findByDate(DateTime date) async {
    final db = await localDatabase.executor;
    return db.query(
      tableName,
      where: 'date = ?',
      whereArgs: [dateKey(date)],
      orderBy: 'is_completed ASC, priority DESC, created_at ASC, id ASC',
    );
  }

  Future<List<DatabaseRow>> findAgenda({
    required DateTime anchorDate,
    int futureDays = 7,
  }) async {
    final db = await localDatabase.executor;
    final today = dateKey(anchorDate);
    final future = dateKey(anchorDate.add(Duration(days: futureDays)));
    return db.query(
      tableName,
      where: '''
(is_completed = 0 AND date < ?)
OR date = ?
OR (is_completed = 0 AND date > ? AND date <= ?)
''',
      whereArgs: [today, today, today, future],
      orderBy:
          'date ASC, is_completed ASC, priority DESC, created_at ASC, id ASC',
    );
  }

  Future<int> countByDate(DateTime date) async {
    final db = await localDatabase.executor;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM todos WHERE date = ?',
      [dateKey(date)],
    );
    return (rows.single['cnt'] as int);
  }

  Future<int> countCompletedByDate(DateTime date) async {
    final db = await localDatabase.executor;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM todos WHERE date = ? AND is_completed = 1',
      [dateKey(date)],
    );
    return (rows.single['cnt'] as int);
  }

  Future<int> complete(int id, {DateTime? completedAt}) {
    final finishedAt = completedAt ?? DateTime.now();
    return update(id, {
      'is_completed': 1,
      'completed_at': timestamp(finishedAt),
      'updated_at': timestamp(finishedAt),
    });
  }

  Future<int> reopen(int id, {DateTime? updatedAt}) {
    final writtenAt = timestamp(updatedAt ?? DateTime.now());
    return update(id, {
      'is_completed': 0,
      'completed_at': null,
      'updated_at': writtenAt,
    });
  }

  Future<int> updateDetails(
    int id, {
    required String title,
    String? note,
    String? dueTime,
    int priority = 0,
    required bool isCompleted,
    int? completedAt,
    DateTime? updatedAt,
  }) {
    final writtenAt = timestamp(updatedAt ?? DateTime.now());
    return update(id, {
      'title': title,
      'note': note,
      'due_time': dueTime,
      'priority': priority,
      'is_completed': isCompleted ? 1 : 0,
      'completed_at': isCompleted ? (completedAt ?? writtenAt) : null,
      'updated_at': writtenAt,
    });
  }
}

class TrackersRepository extends Repository {
  TrackersRepository(LocalDatabase localDatabase)
    : super(localDatabase, 'trackers');

  Future<int> create({
    required String name,
    String? unit,
    double? targetValue,
    String? color,
    String? icon,
  }) {
    return insert(
      withTimestamps({
        'name': name,
        'unit': unit,
        'target_value': targetValue,
        'color': color,
        'icon': icon,
        'is_archived': 0,
      }),
    );
  }

  Future<int> archive(int id, {DateTime? updatedAt}) {
    return update(id, {
      'is_archived': 1,
      'updated_at': timestamp(updatedAt ?? DateTime.now()),
    });
  }

  Future<List<DatabaseRow>> findActive() async {
    final db = await localDatabase.executor;
    return db.query(
      tableName,
      where: 'is_archived = 0',
      orderBy: 'created_at ASC, id ASC',
    );
  }
}

class TrackerLogsRepository extends Repository {
  TrackerLogsRepository(LocalDatabase localDatabase)
    : super(localDatabase, 'tracker_logs');

  Future<int> create({
    required int trackerId,
    required DateTime date,
    double value = 1,
    String? note,
    DateTime? createdAt,
  }) {
    return insert(
      withTimestamps({
        'tracker_id': trackerId,
        'date': dateKey(date),
        'value': value,
        'note': note,
      }, createdAt: createdAt),
    );
  }

  Future<List<DatabaseRow>> findByDate(DateTime date) async {
    final db = await localDatabase.executor;
    return db.query(
      tableName,
      where: 'date = ?',
      whereArgs: [dateKey(date)],
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<int> countByDate(DateTime date) async {
    final db = await localDatabase.executor;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM tracker_logs WHERE date = ?',
      [dateKey(date)],
    );
    return (rows.single['cnt'] as int);
  }

  Future<int> updateDetails(
    int id, {
    required double value,
    String? note,
    DateTime? updatedAt,
  }) {
    return update(id, {
      'value': value,
      'note': note,
      'updated_at': timestamp(updatedAt ?? DateTime.now()),
    });
  }
}

class FocusSessionsRepository extends Repository {
  FocusSessionsRepository(LocalDatabase localDatabase)
    : super(localDatabase, 'focus_sessions');

  Future<int> create({
    required DateTime date,
    required DateTime startedAt,
    required int durationMinutes,
    DateTime? endedAt,
    String? note,
    DateTime? createdAt,
  }) {
    return insert(
      withTimestamps({
        'date': dateKey(date),
        'started_at': timestamp(startedAt),
        'ended_at': endedAt == null ? null : timestamp(endedAt),
        'duration_minutes': durationMinutes,
        'note': note,
      }, createdAt: createdAt),
    );
  }

  Future<int> sumMinutesByDate(DateTime date) async {
    final db = await localDatabase.executor;
    final rows = await db.rawQuery(
      '''
SELECT COALESCE(SUM(duration_minutes), 0) AS total
FROM focus_sessions
WHERE date = ?
''',
      [dateKey(date)],
    );
    return (rows.single['total'] as num).toInt();
  }

  Future<List<DatabaseRow>> findByDate(DateTime date) async {
    final db = await localDatabase.executor;
    return db.query(
      tableName,
      where: 'date = ?',
      whereArgs: [dateKey(date)],
      orderBy: 'started_at ASC, id ASC',
    );
  }

  Future<int> countByDate(DateTime date) async {
    final db = await localDatabase.executor;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM focus_sessions WHERE date = ?',
      [dateKey(date)],
    );
    return (rows.single['cnt'] as int);
  }

  Future<int> updateDetails(
    int id, {
    required int durationMinutes,
    String? note,
    DateTime? updatedAt,
  }) {
    return update(id, {
      'duration_minutes': durationMinutes,
      'note': note,
      'updated_at': timestamp(updatedAt ?? DateTime.now()),
    });
  }
}

class ExpensesRepository extends Repository {
  ExpensesRepository(LocalDatabase localDatabase)
    : super(localDatabase, 'expenses');

  Future<int> create({
    required DateTime date,
    required double amount,
    required String category,
    String? note,
    String currency = 'CNY',
    DateTime? createdAt,
  }) {
    return insert(
      withTimestamps({
        'date': dateKey(date),
        'amount': amount,
        'category': category,
        'note': note,
        'currency': currency,
      }, createdAt: createdAt),
    );
  }

  Future<double> sumAmountByDate(DateTime date) async {
    final db = await localDatabase.executor;
    final rows = await db.rawQuery(
      '''
SELECT COALESCE(SUM(amount), 0) AS total
FROM expenses
WHERE date = ?
''',
      [dateKey(date)],
    );
    return (rows.single['total'] as num).toDouble();
  }

  Future<double> sumAmountByMonth(DateTime date) async {
    final db = await localDatabase.executor;
    final start = DateTime(date.year, date.month);
    final next = DateTime(date.year, date.month + 1);
    final rows = await db.rawQuery(
      '''
SELECT COALESCE(SUM(amount), 0) AS total
FROM expenses
WHERE date >= ? AND date < ?
''',
      [dateKey(start), dateKey(next)],
    );
    return (rows.single['total'] as num).toDouble();
  }

  Future<List<DatabaseRow>> findByMonth(DateTime date) async {
    final db = await localDatabase.executor;
    final start = DateTime(date.year, date.month);
    final next = DateTime(date.year, date.month + 1);
    return db.query(
      tableName,
      where: 'date >= ? AND date < ?',
      whereArgs: [dateKey(start), dateKey(next)],
      orderBy: 'date ASC, created_at ASC, id ASC',
    );
  }

  Future<Map<String, double>> sumAmountByCategoryForMonth(DateTime date) async {
    final db = await localDatabase.executor;
    final start = DateTime(date.year, date.month);
    final next = DateTime(date.year, date.month + 1);
    final rows = await db.rawQuery(
      '''
SELECT category, COALESCE(SUM(amount), 0) AS total
FROM expenses
WHERE date >= ? AND date < ?
GROUP BY category
ORDER BY total DESC, category ASC
''',
      [dateKey(start), dateKey(next)],
    );
    return {
      for (final row in rows)
        row['category'] as String: (row['total'] as num).toDouble(),
    };
  }

  Future<Map<String, double>> sumAmountByDayForMonth(DateTime date) async {
    final db = await localDatabase.executor;
    final start = DateTime(date.year, date.month);
    final next = DateTime(date.year, date.month + 1);
    final rows = await db.rawQuery(
      '''
SELECT date, COALESCE(SUM(amount), 0) AS total
FROM expenses
WHERE date >= ? AND date < ?
GROUP BY date
ORDER BY date ASC
''',
      [dateKey(start), dateKey(next)],
    );
    return {
      for (final row in rows)
        row['date'] as String: (row['total'] as num).toDouble(),
    };
  }

  Future<List<DatabaseRow>> findByDate(DateTime date) async {
    final db = await localDatabase.executor;
    return db.query(
      tableName,
      where: 'date = ?',
      whereArgs: [dateKey(date)],
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<int> countByDate(DateTime date) async {
    final db = await localDatabase.executor;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM expenses WHERE date = ?',
      [dateKey(date)],
    );
    return (rows.single['cnt'] as int);
  }

  Future<int> updateDetails(
    int id, {
    required double amount,
    required String category,
    String? note,
    String currency = 'CNY',
    DateTime? updatedAt,
  }) {
    return update(id, {
      'amount': amount,
      'category': category,
      'note': note,
      'currency': currency,
      'updated_at': timestamp(updatedAt ?? DateTime.now()),
    });
  }
}

class BodyLogsRepository extends Repository {
  BodyLogsRepository(LocalDatabase localDatabase)
    : super(localDatabase, 'body_logs');

  Future<int> create({
    required DateTime date,
    required String metric,
    required double value,
    String? unit,
    String? note,
    DateTime? createdAt,
  }) {
    return insert(
      withTimestamps({
        'date': dateKey(date),
        'metric': metric,
        'value': value,
        'unit': unit,
        'note': note,
      }, createdAt: createdAt),
    );
  }

  Future<List<DatabaseRow>> findByDate(DateTime date) async {
    final db = await localDatabase.executor;
    return db.query(
      tableName,
      where: 'date = ?',
      whereArgs: [dateKey(date)],
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<int> countByDate(DateTime date) async {
    final db = await localDatabase.executor;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM body_logs WHERE date = ?',
      [dateKey(date)],
    );
    return (rows.single['cnt'] as int);
  }

  Future<int> updateDetails(
    int id, {
    required String metric,
    required double value,
    String? unit,
    String? note,
    DateTime? updatedAt,
  }) {
    return update(id, {
      'metric': metric,
      'value': value,
      'unit': unit,
      'note': note,
      'updated_at': timestamp(updatedAt ?? DateTime.now()),
    });
  }
}

class LibraryItemsRepository {
  LibraryItemsRepository(this.localDatabase);

  final LocalDatabase localDatabase;

  Future<List<DatabaseRow>> findAll() async {
    final db = await localDatabase.executor;
    return db.query(
      'library_items',
      orderBy: 'kind ASC, updated_at DESC, name ASC, item_key ASC',
    );
  }

  Future<void> replaceAll(List<DatabaseRow> rows) async {
    await localDatabase.transaction(() async {
      final db = await localDatabase.executor;
      await db.delete('library_items');
      for (final row in rows) {
        await db.insert('library_items', row);
      }
    });
  }

  Future<void> upsert(DatabaseRow row) async {
    final db = await localDatabase.executor;
    final itemKey = row['item_key'] as String;
    await db.delete(
      'library_items',
      where: 'item_key = ?',
      whereArgs: [itemKey],
    );
    await db.insert('library_items', row);
  }

  Future<int> deleteByKey(String itemKey) async {
    final db = await localDatabase.executor;
    return db.delete(
      'library_items',
      where: 'item_key = ?',
      whereArgs: [itemKey],
    );
  }
}

class DashboardDayBundle {
  const DashboardDayBundle({
    required this.activityRows,
    required this.monthExpenseTotal,
    required this.review,
  });

  final List<DatabaseRow> activityRows;
  final double monthExpenseTotal;
  final DatabaseRow? review;
}

class DashboardRepository {
  DashboardRepository(this.localDatabase);

  final LocalDatabase localDatabase;

  Future<DashboardDayBundle> loadDayBundle(DateTime date) async {
    final activityRowsFuture = _loadDailyActivityRows(date);
    final monthExpenseTotalFuture = _sumAmountByMonth(date);
    final reviewFuture = _findReviewByDate(dateKey(date));

    final results = await Future.wait([
      activityRowsFuture,
      monthExpenseTotalFuture,
      reviewFuture,
    ]);

    return DashboardDayBundle(
      activityRows: results[0] as List<DatabaseRow>,
      monthExpenseTotal: results[1] as double,
      review: results[2] as DatabaseRow?,
    );
  }

  Future<List<DatabaseRow>> _loadDailyActivityRows(DateTime date) async {
    final db = await localDatabase.executor;
    final day = dateKey(date);
    return db.rawQuery(
      '''
SELECT * FROM (
  SELECT 'record' AS kind, id AS source_id, created_at, NULL AS started_at, NULL AS completed_at, NULL AS duration_minutes, NULL AS amount, NULL AS category, tags, NULL AS is_completed, content, type, NULL AS title, NULL AS note, NULL AS due_time, NULL AS priority, NULL AS tracker_id, NULL AS value, NULL AS currency, NULL AS metric, NULL AS unit
  FROM records
  WHERE date = ? AND is_deleted = 0
  UNION ALL
  SELECT 'todo' AS kind, id AS source_id, created_at, NULL AS started_at, completed_at, NULL AS duration_minutes, NULL AS amount, NULL AS category, NULL AS tags, is_completed, NULL AS content, NULL AS type, title, note, due_time, priority, NULL AS tracker_id, NULL AS value, NULL AS currency, NULL AS metric, NULL AS unit
  FROM todos
  WHERE date = ?
  UNION ALL
  SELECT 'tracker' AS kind, id AS source_id, created_at, NULL AS started_at, NULL AS completed_at, NULL AS duration_minutes, NULL AS amount, NULL AS category, NULL AS tags, NULL AS is_completed, NULL AS content, NULL AS type, NULL AS title, note, NULL AS due_time, NULL AS priority, tracker_id, value, NULL AS currency, NULL AS metric, NULL AS unit
  FROM tracker_logs
  WHERE date = ?
  UNION ALL
  SELECT 'focus' AS kind, id AS source_id, created_at, started_at, NULL AS completed_at, duration_minutes, NULL AS amount, NULL AS category, NULL AS tags, NULL AS is_completed, NULL AS content, NULL AS type, NULL AS title, note, NULL AS due_time, NULL AS priority, NULL AS tracker_id, NULL AS value, NULL AS currency, NULL AS metric, NULL AS unit
  FROM focus_sessions
  WHERE date = ?
  UNION ALL
  SELECT 'expense' AS kind, id AS source_id, created_at, NULL AS started_at, NULL AS completed_at, NULL AS duration_minutes, amount, category, NULL AS tags, NULL AS is_completed, NULL AS content, NULL AS type, NULL AS title, note, NULL AS due_time, NULL AS priority, NULL AS tracker_id, NULL AS value, currency, NULL AS metric, NULL AS unit
  FROM expenses
  WHERE date = ?
  UNION ALL
  SELECT 'body' AS kind, id AS source_id, created_at, NULL AS started_at, NULL AS completed_at, NULL AS duration_minutes, NULL AS amount, NULL AS category, NULL AS tags, NULL AS is_completed, NULL AS content, NULL AS type, NULL AS title, note, NULL AS due_time, NULL AS priority, NULL AS tracker_id, NULL AS value, NULL AS currency, metric, unit
  FROM body_logs
  WHERE date = ?
)
ORDER BY created_at ASC, kind ASC, source_id ASC
''',
      [day, day, day, day, day, day],
    );
  }

  Future<double> _sumAmountByMonth(DateTime date) async {
    final db = await localDatabase.executor;
    final start = DateTime(date.year, date.month);
    final next = DateTime(date.year, date.month + 1);
    final rows = await db.rawQuery(
      '''
SELECT COALESCE(SUM(amount), 0) AS total
FROM expenses
WHERE date >= ? AND date < ?
''',
      [dateKey(start), dateKey(next)],
    );
    return (rows.single['total'] as num).toDouble();
  }

  Future<DatabaseRow?> _findReviewByDate(String date) async {
    final db = await localDatabase.executor;
    final rows = await db.query(
      'daily_reviews',
      where: 'date = ?',
      whereArgs: [date],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }
}

class AppSettingsRepository {
  AppSettingsRepository(this.localDatabase);

  final LocalDatabase localDatabase;

  Future<void> create({
    required String key,
    required String value,
    DateTime? updatedAt,
  }) async {
    final db = await localDatabase.executor;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
      'updated_at': timestamp(updatedAt ?? DateTime.now()),
    });
  }

  Future<DatabaseRow?> findByKey(String key) async {
    final db = await localDatabase.executor;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<DatabaseRow>> findAll() async {
    final db = await localDatabase.executor;
    return db.query('app_settings', orderBy: 'key ASC');
  }

  Future<int> update(String key, String value, {DateTime? updatedAt}) async {
    final db = await localDatabase.executor;
    return db.update(
      'app_settings',
      {'value': value, 'updated_at': timestamp(updatedAt ?? DateTime.now())},
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  Future<int> delete(String key) async {
    final db = await localDatabase.executor;
    return db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
  }
}
