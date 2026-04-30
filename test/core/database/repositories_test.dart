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
