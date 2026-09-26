import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/features/flash_record/startup_todo_reminder_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

LocalDatabase _memoryDatabase() => LocalDatabase(
  databaseFactory: databaseFactoryFfi,
  databasePath: inMemoryDatabasePath,
);

void main() {
  test('filters and stably sorts today and previous unfinished todos', () async {
    final now = DateTime(2026, 9, 26, 9);
    final repo = _FakeTodosRepository([
      _todo(1, '无时间高优先级', '2026-09-26', null, 9, 1),
      _todo(2, '今天十点', '2026-09-26', '10:00', 0, 2),
      _todo(3, '昨天的事', '2026-09-25', null, 1, 3),
      _todo(4, '今天八点', '2026-09-26', '08:00', 0, 4),
      _todo(5, '未来不提醒', '2026-09-27', null, 99, 5),
      _todo(6, '已完成', '2026-09-26', '07:00', 99, 6, completed: 1),
      _todo(7, '非法日期', '2026-09-31', null, 99, 7),
    ]);

    final snapshot = await loadStartupTodoReminderSnapshot(repo, now: now);

    expect(snapshot!.totalCount, 4);
    expect(snapshot.todayCount, 3);
    expect(snapshot.previousCount, 1);
    expect(snapshot.items.map((item) => item.id), [4, 2]);
  });

  test('dismissal values reset by local date and persist as capped JSON', () async {
    final settings = _FakeSettingsRepository();
    final firstDay = DateTime(2026, 9, 26, 12);
    await saveStartupTodoDismissal(settings, now: firstDay, closeCount: 9);

    final sameDay = await readStartupTodoDismissal(settings, now: firstDay);
    final nextDay = await readStartupTodoDismissal(
      settings,
      now: firstDay.add(const Duration(days: 1)),
    );

    expect(sameDay!.closeCount, 3);
    expect(nextDay!.closeCount, 0);
    expect(jsonDecode(settings.value!)['date'], '2026-09-26');
  });
}

Map<String, Object?> _todo(
  int id,
  String title,
  String date,
  String? dueTime,
  int priority,
  int createdAt, {
  int completed = 0,
}) => {
  'id': id,
  'title': title,
  'date': date,
  'due_time': dueTime,
  'priority': priority,
  'created_at': DateTime(2026, 9, 20).millisecondsSinceEpoch + createdAt,
  'is_completed': completed,
};

class _FakeTodosRepository extends TodosRepository {
  _FakeTodosRepository(this.rows) : super(_memoryDatabase());

  final List<Map<String, Object?>> rows;

  @override
  Future<List<DatabaseRow>> findAgenda({
    required DateTime anchorDate,
    int futureDays = 7,
  }) async => rows;
}

class _FakeSettingsRepository extends AppSettingsRepository {
  _FakeSettingsRepository() : super(_memoryDatabase());

  String? value;

  @override
  Future<DatabaseRow?> findByKey(String key) async =>
      value == null ? null : {'key': key, 'value': value};

  @override
  Future<void> create({
    required String key,
    required String value,
    DateTime? updatedAt,
  }) async {
    this.value = value;
  }

  @override
  Future<int> update(String key, String value, {DateTime? updatedAt}) async {
    this.value = value;
    return 1;
  }
}
