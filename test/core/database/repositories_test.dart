import 'package:dayline_app/core/database/local_database.dart';
import 'package:dayline_app/core/database/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  late RecordsRepository recordsRepository;
  late TodosRepository todosRepository;
  late TrackersRepository trackersRepository;
  late TrackerLogsRepository trackerLogsRepository;
  late FocusSessionsRepository focusSessionsRepository;
  late ExpensesRepository expensesRepository;
  late BodyLogsRepository bodyLogsRepository;
  late AppSettingsRepository appSettingsRepository;

  setUp(() {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    recordsRepository = RecordsRepository(database);
    todosRepository = TodosRepository(database);
    trackersRepository = TrackersRepository(database);
    trackerLogsRepository = TrackerLogsRepository(database);
    focusSessionsRepository = FocusSessionsRepository(database);
    expensesRepository = ExpensesRepository(database);
    bodyLogsRepository = BodyLogsRepository(database);
    appSettingsRepository = AppSettingsRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('inserts a memo record and queries records by date', () async {
    final today = DateTime(2026, 4, 30, 9);

    final recordId = await recordsRepository.create(
      date: today,
      type: 'memo',
      content: 'Morning note',
    );

    final todayRecords = await recordsRepository.findByDate(today);

    expect(recordId, isPositive);
    expect(todayRecords, hasLength(1));
    expect(todayRecords.single['id'], recordId);
    expect(todayRecords.single['type'], 'memo');
    expect(todayRecords.single['content'], 'Morning note');
  });

  test('creates, completes, and deletes a todo', () async {
    final today = DateTime(2026, 4, 30);

    final todoId = await todosRepository.create(
      date: today,
      title: 'Finish local database layer',
    );

    final createdTodos = await todosRepository.findByDate(today);
    expect(createdTodos, hasLength(1));
    expect(createdTodos.single['is_completed'], 0);

    await todosRepository.complete(todoId, completedAt: today);

    final completedTodo = await todosRepository.findById(todoId);
    expect(completedTodo?['is_completed'], 1);
    expect(completedTodo?['completed_at'], isNotNull);

    await todosRepository.delete(todoId);

    expect(await todosRepository.findById(todoId), isNull);
    expect(await todosRepository.findByDate(today), isEmpty);
  });

  test(
    'finds agenda todos across overdue, today, and upcoming tasks',
    () async {
      final today = DateTime(2026, 4, 30);
      final overdueId = await todosRepository.create(
        date: today.subtract(const Duration(days: 1)),
        title: 'Overdue task',
      );
      final todayId = await todosRepository.create(
        date: today,
        title: 'Today task',
      );
      final upcomingId = await todosRepository.create(
        date: today.add(const Duration(days: 3)),
        title: 'Upcoming task',
      );
      final farFutureId = await todosRepository.create(
        date: today.add(const Duration(days: 10)),
        title: 'Later task',
      );
      final completedPastId = await todosRepository.create(
        date: today.subtract(const Duration(days: 2)),
        title: 'Finished past task',
      );

      await todosRepository.complete(completedPastId, completedAt: today);

      final agenda = await todosRepository.findAgenda(anchorDate: today);
      final ids = agenda.map((todo) => todo['id']).toList();

      expect(ids, containsAll([overdueId, todayId, upcomingId]));
      expect(ids, isNot(contains(farFutureId)));
      expect(ids, isNot(contains(completedPastId)));
    },
  );

  test('updates record details', () async {
    final today = DateTime(2026, 4, 30);
    final recordId = await recordsRepository.create(
      date: today,
      type: 'memo',
      content: 'Morning note',
    );

    await recordsRepository.updateDetails(
      recordId,
      content: 'Updated note',
      time: '09:30',
      tags: const ['日常'],
    );

    final updated = await recordsRepository.findById(recordId);
    expect(updated?['content'], 'Updated note');
    expect(updated?['time'], '09:30');
    expect(updated?['tags'], '["日常"]');
  });

  test('updates todo details', () async {
    final today = DateTime(2026, 4, 30);
    final todoId = await todosRepository.create(date: today, title: 'Old task');

    await todosRepository.updateDetails(
      todoId,
      title: 'New task',
      note: 'Bring files',
      dueTime: '18:00',
      priority: 2,
      isCompleted: true,
    );

    final updated = await todosRepository.findById(todoId);
    expect(updated?['title'], 'New task');
    expect(updated?['note'], 'Bring files');
    expect(updated?['due_time'], '18:00');
    expect(updated?['priority'], 2);
    expect(updated?['is_completed'], 1);
    expect(updated?['completed_at'], isNotNull);
  });

  test('creates a tracker log and queries tracker logs by date', () async {
    final today = DateTime(2026, 4, 30);
    final trackerId = await trackersRepository.create(name: 'Drink water');

    final logId = await trackerLogsRepository.create(
      trackerId: trackerId,
      date: today,
      value: 1,
      note: 'First cup',
    );

    final todayLogs = await trackerLogsRepository.findByDate(today);

    expect(logId, isPositive);
    expect(todayLogs, hasLength(1));
    expect(todayLogs.single['tracker_id'], trackerId);
    expect(todayLogs.single['value'], 1);
  });

  test('updates tracker log details', () async {
    final today = DateTime(2026, 4, 30);
    final trackerId = await trackersRepository.create(name: 'Drink water');
    final logId = await trackerLogsRepository.create(
      trackerId: trackerId,
      date: today,
      value: 1,
      note: 'First cup',
    );

    await trackerLogsRepository.updateDetails(
      logId,
      value: 2,
      note: 'Two cups',
    );

    final updated = await trackerLogsRepository.findById(logId);
    expect(updated?['value'], 2);
    expect(updated?['note'], 'Two cups');
  });

  test('summarizes focus minutes by date', () async {
    final today = DateTime(2026, 4, 30);
    final yesterday = today.subtract(const Duration(days: 1));

    await focusSessionsRepository.create(
      date: today,
      startedAt: DateTime(2026, 4, 30, 9),
      durationMinutes: 25,
    );
    await focusSessionsRepository.create(
      date: today,
      startedAt: DateTime(2026, 4, 30, 10),
      durationMinutes: 15,
    );
    await focusSessionsRepository.create(
      date: yesterday,
      startedAt: DateTime(2026, 4, 29, 9),
      durationMinutes: 60,
    );

    expect(await focusSessionsRepository.sumMinutesByDate(today), 40);
  });

  test('updates focus session details', () async {
    final today = DateTime(2026, 4, 30);
    final sessionId = await focusSessionsRepository.create(
      date: today,
      startedAt: DateTime(2026, 4, 30, 9),
      durationMinutes: 25,
      note: 'Read',
    );

    await focusSessionsRepository.updateDetails(
      sessionId,
      durationMinutes: 45,
      note: 'Deep read',
    );

    final updated = await focusSessionsRepository.findById(sessionId);
    expect(updated?['duration_minutes'], 45);
    expect(updated?['note'], 'Deep read');
  });

  test('summarizes expense amount by date', () async {
    final today = DateTime(2026, 4, 30);
    final tomorrow = today.add(const Duration(days: 1));

    await expensesRepository.create(
      date: today,
      amount: 12.5,
      category: 'Food',
    );
    await expensesRepository.create(
      date: today,
      amount: 3.25,
      category: 'Transit',
    );
    await expensesRepository.create(
      date: tomorrow,
      amount: 99,
      category: 'Ignored',
    );

    expect(await expensesRepository.sumAmountByDate(today), 15.75);
  });

  test('updates expense details', () async {
    final today = DateTime(2026, 4, 30);
    final expenseId = await expensesRepository.create(
      date: today,
      amount: 12.5,
      category: 'Food',
      note: 'Lunch',
    );

    await expensesRepository.updateDetails(
      expenseId,
      amount: 15,
      category: 'Coffee',
      note: 'Latte',
      currency: 'CNY',
    );

    final updated = await expensesRepository.findById(expenseId);
    expect(updated?['amount'], 15);
    expect(updated?['category'], 'Coffee');
    expect(updated?['note'], 'Latte');
    expect(updated?['currency'], 'CNY');
  });

  test('creates, updates, queries, and deletes a body log', () async {
    final today = DateTime(2026, 4, 30);

    final logId = await bodyLogsRepository.create(
      date: today,
      metric: 'weight',
      value: 70.5,
      unit: 'kg',
    );

    await bodyLogsRepository.update(logId, {'value': 70.2});

    final todayLogs = await bodyLogsRepository.findByDate(today);
    expect(todayLogs, hasLength(1));
    expect(todayLogs.single['value'], 70.2);

    await bodyLogsRepository.delete(logId);

    expect(await bodyLogsRepository.findById(logId), isNull);
  });

  test('updates body log details', () async {
    final today = DateTime(2026, 4, 30);
    final logId = await bodyLogsRepository.create(
      date: today,
      metric: 'weight',
      value: 70.5,
      unit: 'kg',
      note: 'Morning',
    );

    await bodyLogsRepository.updateDetails(
      logId,
      metric: 'body_fat',
      value: 18.2,
      unit: '%',
      note: 'Evening',
    );

    final updated = await bodyLogsRepository.findById(logId);
    expect(updated?['metric'], 'body_fat');
    expect(updated?['value'], 18.2);
    expect(updated?['unit'], '%');
    expect(updated?['note'], 'Evening');
  });

  test('creates, updates, reads, and deletes an app setting', () async {
    await appSettingsRepository.create(key: 'theme_mode', value: 'system');

    expect(
      await appSettingsRepository.findByKey('theme_mode'),
      containsPair('value', 'system'),
    );

    await appSettingsRepository.update('theme_mode', 'dark');

    expect(
      await appSettingsRepository.findByKey('theme_mode'),
      containsPair('value', 'dark'),
    );

    await appSettingsRepository.delete('theme_mode');

    expect(await appSettingsRepository.findByKey('theme_mode'), isNull);
  });
}
