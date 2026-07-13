import 'dart:convert';

import 'local_database.dart';
import 'repositories.dart';

class DerivedSyncJob {
  const DerivedSyncJob({
    required this.key,
    required this.type,
    required this.payload,
    required this.attempts,
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
  });

  final String key;
  final String type;
  final Map<String, Object?> payload;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class DerivedSyncJobsRepository {
  DerivedSyncJobsRepository(this.localDatabase);

  final LocalDatabase localDatabase;

  Future<void> enqueue({
    required String key,
    required String type,
    required Map<String, Object?> payload,
    DateTime? enqueuedAt,
  }) async {
    final now = enqueuedAt ?? DateTime.now();
    final db = await localDatabase.executor;
    final existing = await findByKey(key);
    final row = {
      'job_key': key,
      'job_type': type,
      'payload_json': jsonEncode(payload),
      'updated_at': timestamp(now),
    };
    if (existing == null) {
      await db.insert('derived_sync_jobs', {
        ...row,
        'attempts': 0,
        'last_error': null,
        'created_at': timestamp(now),
      });
      return;
    }

    await db.update(
      'derived_sync_jobs',
      {...row, 'last_error': null},
      where: 'job_key = ?',
      whereArgs: [key],
    );
  }

  Future<DerivedSyncJob?> findByKey(String key) async {
    final db = await localDatabase.executor;
    final rows = await db.query(
      'derived_sync_jobs',
      where: 'job_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<List<DerivedSyncJob>> findPending({int limit = 20}) async {
    final db = await localDatabase.executor;
    final rows = await db.query(
      'derived_sync_jobs',
      orderBy: 'updated_at ASC, job_key ASC',
      limit: limit,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> markFailed(
    String key,
    Object error, {
    DateTime? failedAt,
  }) async {
    final now = failedAt ?? DateTime.now();
    final db = await localDatabase.executor;
    await db.rawUpdate(
      '''
UPDATE derived_sync_jobs
SET attempts = attempts + 1,
    last_error = ?,
    updated_at = ?
WHERE job_key = ?
''',
      [error.toString(), timestamp(now), key],
    );
  }

  Future<void> delete(String key) async {
    final db = await localDatabase.executor;
    await db.delete(
      'derived_sync_jobs',
      where: 'job_key = ?',
      whereArgs: [key],
    );
  }

  DerivedSyncJob _fromRow(DatabaseRow row) {
    return DerivedSyncJob(
      key: row['job_key'] as String,
      type: row['job_type'] as String,
      payload: _decodePayload(row['payload_json']),
      attempts: row['attempts'] as int,
      lastError: row['last_error'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  Map<String, Object?> _decodePayload(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
    } catch (_) {}
    return const {};
  }
}
