import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/derived_sync_jobs_repository.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late DerivedSyncJobsRepository repository;

  setUp(() {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = DerivedSyncJobsRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('enqueue coalesces the same derived sync key', () async {
    await repository.enqueue(
      key: 'expense:2026-07',
      type: 'monthly_expense_report',
      payload: const {'date': 1},
      enqueuedAt: DateTime(2026, 7, 12, 9),
    );
    await repository.enqueue(
      key: 'expense:2026-07',
      type: 'monthly_expense_report',
      payload: const {'date': 2},
      enqueuedAt: DateTime(2026, 7, 12, 10),
    );

    final jobs = await repository.findPending();

    expect(jobs, hasLength(1));
    expect(jobs.single.key, 'expense:2026-07');
    expect(jobs.single.payload['date'], 2);
    expect(jobs.single.attempts, 0);
  });

  test('failed job remains pending until deleted after success', () async {
    await repository.enqueue(
      key: 'daily:2026-07-12',
      type: 'daily_draft',
      payload: const {'updatedAt': 1},
    );

    await repository.markFailed('daily:2026-07-12', StateError('no grant'));
    var job = await repository.findByKey('daily:2026-07-12');
    expect(job, isNotNull);
    expect(job!.attempts, 1);
    expect(job.lastError, contains('no grant'));

    await repository.delete('daily:2026-07-12');
    job = await repository.findByKey('daily:2026-07-12');
    expect(job, isNull);
  });
}
