import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/write_operations_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late WriteOperationsRepository operations;

  setUp(() {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    operations = WriteOperationsRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('reuses one active operation for the same fingerprint', () async {
    final preparedAt = DateTime(2026, 7, 12, 9, 30);
    final first = await operations.prepare(
      type: 'flash_record.parsed.v1',
      fingerprint: 'same-request',
      preparedAt: preparedAt,
    );
    final second = await operations.prepare(
      type: 'flash_record.parsed.v1',
      fingerprint: 'same-request',
      preparedAt: preparedAt.add(const Duration(seconds: 1)),
    );

    expect(second.id, first.id);
    expect(second.status, WriteOperationStatus.pending);

    final rows = await (await database.database).query('write_operations');
    expect(rows, hasLength(1));

    await operations.markCommitted(first.id);
    await operations.markCompleted(first.id);
    final completedReplay = await operations.prepare(
      type: 'flash_record.parsed.v1',
      fingerprint: 'same-request',
    );
    expect(completedReplay.id, first.id);

    await operations.acknowledge(first.id);
    final newRequest = await operations.prepare(
      type: 'flash_record.parsed.v1',
      fingerprint: 'same-request',
    );
    expect(newRequest.id, isNot(first.id));
  });

  test('concurrent prepare calls converge on one operation', () async {
    final prepared = await Future.wait(
      List.generate(
        8,
        (_) => operations.prepare(
          type: 'flash_record.parsed.v1',
          fingerprint: 'concurrent-request',
        ),
      ),
    );

    expect(prepared.map((operation) => operation.id).toSet(), hasLength(1));
    final rows = await (await database.database).query('write_operations');
    expect(rows, hasLength(1));
  });

  test('rejects a preferred operation id for a different payload', () async {
    final operation = await operations.prepare(
      type: 'flash_record.parsed.v1',
      fingerprint: 'original-payload',
    );

    await expectLater(
      operations.prepare(
        type: 'flash_record.parsed.v1',
        fingerprint: 'changed-payload',
        preferredOperationId: operation.id,
      ),
      throwsStateError,
    );
    expect(await operations.findById(operation.id), isNotNull);
  });

  test(
    'moves pending to committed to completed and only completed can be acknowledged',
    () async {
      final operation = await operations.prepare(
        type: 'flash_record.parsed.v1',
        fingerprint: 'lifecycle',
      );

      await operations.acknowledge(operation.id);
      expect(
        await operations.findById(operation.id),
        isNotNull,
        reason: 'A pending request must not be acknowledged or deleted.',
      );

      final committed = await operations.markCommitted(
        operation.id,
        result: const {'recordId': 42},
      );
      expect(committed.status, WriteOperationStatus.committed);
      expect(committed.result['recordId'], 42);

      await operations.acknowledge(operation.id);
      expect(
        await operations.findById(operation.id),
        isNotNull,
        reason: 'A committed request must remain replayable.',
      );

      final completed = await operations.markCompleted(operation.id);
      expect(completed.status, WriteOperationStatus.completed);
      await operations.acknowledge(operation.id);
      expect(await operations.findById(operation.id), isNull);
    },
  );

  test('abandon removes only a pending request', () async {
    final pending = await operations.prepare(
      type: 'flash_record.parsed.v1',
      fingerprint: 'abandon-pending',
    );
    await operations.abandon(pending.id);
    expect(await operations.findById(pending.id), isNull);

    final committed = await operations.prepare(
      type: 'flash_record.parsed.v1',
      fingerprint: 'abandon-committed',
    );
    await operations.markCommitted(committed.id);
    await operations.abandon(committed.id);
    expect(await operations.findById(committed.id), isNotNull);
  });

  test(
    'purges stale operations while retaining a recent pending request',
    () async {
      final now = DateTime(2026, 7, 12, 12);
      final recent = await operations.prepare(
        type: 'flash_record.parsed.v1',
        fingerprint: 'recent-pending',
        preparedAt: now.subtract(const Duration(hours: 12)),
      );
      final stalePending = await operations.prepare(
        type: 'flash_record.parsed.v1',
        fingerprint: 'stale-pending',
        preparedAt: now.subtract(const Duration(days: 2)),
      );
      final staleCommitted = await operations.prepare(
        type: 'flash_record.parsed.v1',
        fingerprint: 'stale-committed',
        preparedAt: now.subtract(const Duration(days: 31)),
      );
      await operations.markCommitted(
        staleCommitted.id,
        updatedAt: now.subtract(const Duration(days: 31)),
      );
      final staleCompleted = await operations.prepare(
        type: 'flash_record.parsed.v1',
        fingerprint: 'stale-completed',
        preparedAt: now.subtract(const Duration(days: 2)),
      );
      await operations.markCommitted(
        staleCompleted.id,
        updatedAt: now.subtract(const Duration(days: 2)),
      );
      await operations.markCompleted(
        staleCompleted.id,
        updatedAt: now.subtract(const Duration(days: 2)),
      );

      final deleted = await operations.purgeStale(now: now);

      expect(deleted, 3);
      expect(await operations.findById(recent.id), isNotNull);
      expect(await operations.findById(stalePending.id), isNull);
      expect(await operations.findById(staleCommitted.id), isNull);
      expect(await operations.findById(staleCompleted.id), isNull);
    },
  );

  test(
    'transaction rollback keeps prepared row and rolls back committed status and business row',
    () async {
      final operation = await operations.prepare(
        type: 'flash_record.parsed.v1',
        fingerprint: 'rollback',
      );
      final records = RecordsRepository(database);

      await expectLater(
        database.transaction(() async {
          await records.create(
            date: DateTime(2026, 7, 12),
            type: 'memo',
            content: 'rolled back',
          );
          await operations.markCommitted(
            operation.id,
            result: const {'recordId': 1},
          );
          throw StateError('inject rollback');
        }),
        throwsStateError,
      );

      expect(await records.findAll(), isEmpty);
      final afterRollback = await operations.findById(operation.id);
      expect(afterRollback, isNotNull);
      expect(afterRollback!.status, WriteOperationStatus.pending);
      expect(afterRollback.result, isEmpty);
    },
  );

  test(
    'v4 database is upgraded with write operations without losing existing rows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'liflow-write-operations-migration-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final path = p.join(directory.path, 'legacy.db');

      final legacyDatabase = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(legacyDatabase.close);
      final legacy = await legacyDatabase.database;
      await legacy.insert('records', {
        'date': '2026-07-12',
        'type': 'memo',
        'content': 'keep',
        'tags': '[]',
        'metadata': '{}',
        'is_deleted': 0,
        'created_at': 1,
        'updated_at': 1,
      });
      await legacy.execute('DROP TABLE write_operations');
      await legacy.execute('PRAGMA user_version = 4');
      await legacyDatabase.close();

      final upgraded = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(upgraded.close);
      final db = await upgraded.database;

      expect(await db.getVersion(), 8);
      expect(await db.query('write_operations'), isEmpty);
      expect(await db.query('derived_sync_jobs'), isEmpty);
      expect(await db.query('library_items'), isEmpty);
      expect(await db.query('records'), hasLength(1));
    },
  );
}
