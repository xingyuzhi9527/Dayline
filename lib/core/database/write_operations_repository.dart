import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart' as sqflite;

import 'local_database.dart';
import 'repositories.dart';

enum WriteOperationStatus { pending, committed, completed }

class WriteOperation {
  const WriteOperation({
    required this.id,
    required this.type,
    required this.fingerprint,
    required this.status,
    required this.result,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String type;
  final String fingerprint;
  final WriteOperationStatus status;
  final Map<String, Object?> result;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCommitted => status != WriteOperationStatus.pending;
  bool get isCompleted => status == WriteOperationStatus.completed;
}

/// Persists an unacknowledged write request across Notifier/process restarts.
///
/// Rows are deleted only after the UI observes success (or abandons a failed
/// request). Until then the payload fingerprint can recover the random request
/// ID without treating future, intentionally repeated content as a duplicate.
class WriteOperationsRepository {
  WriteOperationsRepository(this.localDatabase);

  static final Random _random = Random.secure();

  final LocalDatabase localDatabase;

  Future<WriteOperation?> findById(String operationId) async {
    final db = await localDatabase.executor;
    final rows = await db.query(
      'write_operations',
      where: 'operation_id = ?',
      whereArgs: [operationId],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<WriteOperation?> findActive({
    required String type,
    required String fingerprint,
  }) async {
    final db = await localDatabase.executor;
    final rows = await db.query(
      'write_operations',
      where: 'operation_type = ? AND fingerprint = ?',
      whereArgs: [type, fingerprint],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<WriteOperation> prepare({
    required String type,
    required String fingerprint,
    String? preferredOperationId,
    DateTime? preparedAt,
  }) async {
    await purgeStale(now: preparedAt);

    final preferredId = preferredOperationId?.trim();
    if (preferredId != null && preferredId.isNotEmpty) {
      final preferred = await findById(preferredId);
      if (preferred != null) {
        if (preferred.type != type || preferred.fingerprint != fingerprint) {
          throw StateError('Write operation payload does not match its ID.');
        }
        return preferred;
      }
    }

    final existing = await findActive(type: type, fingerprint: fingerprint);
    if (existing != null) return existing;

    final now = preparedAt ?? DateTime.now();
    final operationId = _newOperationId(now);
    final db = await localDatabase.executor;
    await db.insert('write_operations', {
      'operation_id': operationId,
      'operation_type': type,
      'fingerprint': fingerprint,
      'status': WriteOperationStatus.pending.name,
      'result_json': '{}',
      'created_at': timestamp(now),
      'updated_at': timestamp(now),
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);

    final prepared = await findActive(type: type, fingerprint: fingerprint);
    if (prepared == null) {
      throw StateError('Unable to prepare write operation.');
    }
    return prepared;
  }

  Future<int> purgeStale({DateTime? now}) async {
    final anchor = now ?? DateTime.now();
    final pendingCutoff = timestamp(anchor.subtract(const Duration(days: 1)));
    final committedCutoff = timestamp(
      anchor.subtract(const Duration(days: 30)),
    );
    final completedCutoff = timestamp(anchor.subtract(const Duration(days: 1)));
    final db = await localDatabase.executor;
    return db.delete(
      'write_operations',
      where: '''
(status = ? AND updated_at < ?)
OR (status = ? AND updated_at < ?)
OR (status = ? AND updated_at < ?)
''',
      whereArgs: [
        WriteOperationStatus.pending.name,
        pendingCutoff,
        WriteOperationStatus.committed.name,
        committedCutoff,
        WriteOperationStatus.completed.name,
        completedCutoff,
      ],
    );
  }

  Future<WriteOperation> markCommitted(
    String operationId, {
    Map<String, Object?> result = const {},
    DateTime? updatedAt,
  }) async {
    final db = await localDatabase.executor;
    final writtenAt = updatedAt ?? DateTime.now();
    final changed = await db.update(
      'write_operations',
      {
        'status': WriteOperationStatus.committed.name,
        'result_json': jsonEncode(result),
        'updated_at': timestamp(writtenAt),
      },
      where: 'operation_id = ? AND status = ?',
      whereArgs: [operationId, WriteOperationStatus.pending.name],
    );
    if (changed == 0) {
      final existing = await findById(operationId);
      if (existing == null || !existing.isCommitted) {
        throw StateError('Write operation was not committed.');
      }
      return existing;
    }
    return (await findById(operationId))!;
  }

  Future<WriteOperation> markCompleted(
    String operationId, {
    DateTime? updatedAt,
  }) async {
    final db = await localDatabase.executor;
    final writtenAt = updatedAt ?? DateTime.now();
    final changed = await db.update(
      'write_operations',
      {
        'status': WriteOperationStatus.completed.name,
        'updated_at': timestamp(writtenAt),
      },
      where: 'operation_id = ? AND status = ?',
      whereArgs: [operationId, WriteOperationStatus.committed.name],
    );
    if (changed == 0) {
      final existing = await findById(operationId);
      if (existing == null || !existing.isCompleted) {
        throw StateError('Write operation was not completed.');
      }
      return existing;
    }
    return (await findById(operationId))!;
  }

  Future<void> acknowledge(String? operationId) async {
    final id = operationId?.trim();
    if (id == null || id.isEmpty) return;

    final db = await localDatabase.executor;
    await db.delete(
      'write_operations',
      where: 'operation_id = ? AND status = ?',
      whereArgs: [id, WriteOperationStatus.completed.name],
    );
  }

  Future<void> abandon(String? operationId) async {
    final id = operationId?.trim();
    if (id == null || id.isEmpty) return;

    final db = await localDatabase.executor;
    await db.delete(
      'write_operations',
      where: 'operation_id = ? AND status = ?',
      whereArgs: [id, WriteOperationStatus.pending.name],
    );
  }

  WriteOperation _fromRow(DatabaseRow row) {
    final rawStatus = row['status'] as String?;
    WriteOperationStatus? status;
    for (final candidate in WriteOperationStatus.values) {
      if (candidate.name == rawStatus) {
        status = candidate;
        break;
      }
    }
    if (status == null) {
      throw StateError('Unknown write operation status: $rawStatus');
    }
    return WriteOperation(
      id: row['operation_id'] as String,
      type: row['operation_type'] as String,
      fingerprint: row['fingerprint'] as String,
      status: status,
      result: _decodeResult(row['result_json']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  Map<String, Object?> _decodeResult(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
    } catch (_) {}
    return const {};
  }

  static String _newOperationId(DateTime now) {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    final randomPart = base64UrlEncode(bytes).replaceAll('=', '');
    return '${now.microsecondsSinceEpoch}-$randomPart';
  }
}
