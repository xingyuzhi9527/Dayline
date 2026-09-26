import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repositories.dart';
import '../../core/database/repository_providers.dart';

const startupTodoReminderDismissalKey = 'startup_todo_reminder_dismissal';

class StartupTodoReminderItem {
  const StartupTodoReminderItem({
    required this.id,
    required this.title,
    required this.date,
    required this.createdAt,
    required this.priority,
    this.dueTime,
    this.note,
  });

  final int id;
  final String title;
  final DateTime date;
  final DateTime createdAt;
  final int priority;
  final String? dueTime;
  final String? note;

  bool get isToday => _sameDate(date, DateTime.now());

  String get dateLabel {
    final today = DateTime.now();
    if (_sameDate(date, today)) {
      if (dueTime != null) return '今天 $dueTime';
      return '今天';
    }
    return '${date.month}月${date.day}日 · 未完成';
  }
}

class StartupTodoReminderSnapshot {
  const StartupTodoReminderSnapshot({
    required this.items,
    required this.todayCount,
    required this.previousCount,
  });

  final List<StartupTodoReminderItem> items;
  final int todayCount;
  final int previousCount;

  int get totalCount => todayCount + previousCount;
}

final startupTodoReminderProvider =
    FutureProvider<StartupTodoReminderSnapshot?>((ref) async {
      ref.watch(dataDomainVersionProvider(DataDomain.todos));
      return loadStartupTodoReminderSnapshot(
        ref.read(todosRepositoryProvider),
        now: DateTime.now(),
      );
    });

class StartupTodoReminderRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final startupTodoReminderRequestProvider =
    NotifierProvider<StartupTodoReminderRequestNotifier, int>(
      StartupTodoReminderRequestNotifier.new,
    );

class StartupTodoReminderDayNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void rollover() => state++;
}

final startupTodoReminderDayProvider =
    NotifierProvider<StartupTodoReminderDayNotifier, int>(
      StartupTodoReminderDayNotifier.new,
    );

class StartupTodoExternalFlowNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setActive(bool active) => state = active;
}

final startupTodoExternalFlowProvider =
    NotifierProvider<StartupTodoExternalFlowNotifier, bool>(
      StartupTodoExternalFlowNotifier.new,
    );

Future<StartupTodoReminderSnapshot?> loadStartupTodoReminderSnapshot(
  TodosRepository repository, {
  required DateTime now,
}) async {
  final rows = await repository.findAgenda(anchorDate: now, futureDays: 0);
  final today = DateTime(now.year, now.month, now.day);
  final candidates = <StartupTodoReminderItem>[];

  for (final row in rows) {
    if ((row['is_completed'] as int? ?? 0) != 0) continue;
    final date = _parseDate(row['date']);
    if (date == null || date.isAfter(today)) continue;
    final id = row['id'];
    final title = row['title'];
    final createdAt = _parseEpoch(row['created_at']);
    if (id is! int || title is! String || title.trim().isEmpty) continue;
    if (createdAt == null) continue;
    final dueTime = _parseDueTime(row['due_time']);
    candidates.add(
      StartupTodoReminderItem(
        id: id,
        title: title,
        date: date,
        createdAt: createdAt,
        priority: row['priority'] as int? ?? 0,
        dueTime: dueTime,
        note: row['note'] as String?,
      ),
    );
  }

  candidates.sort((a, b) => _compareReminderItems(a, b, today));
  final todayCount = candidates
      .where((item) => _sameDate(item.date, today))
      .length;
  final previousCount = candidates.length - todayCount;
  return StartupTodoReminderSnapshot(
    items: List.unmodifiable(candidates.take(2)),
    todayCount: todayCount,
    previousCount: previousCount,
  );
}

class StartupTodoDismissal {
  const StartupTodoDismissal({required this.date, required this.closeCount});

  final String date;
  final int closeCount;

  bool get reachedLimit => closeCount >= 3;
}

Future<StartupTodoDismissal?> readStartupTodoDismissal(
  AppSettingsRepository repository, {
  required DateTime now,
}) async {
  final row = await repository.findByKey(startupTodoReminderDismissalKey);
  if (row == null || row['value'] is! String) return null;
  try {
    final decoded = jsonDecode(row['value']! as String);
    if (decoded is! Map) return null;
    final date = decoded['date'];
    final count = decoded['closeCount'];
    if (date is! String || count is! num) return null;
    final todayKey = _dateKey(now);
    if (date != todayKey) {
      return StartupTodoDismissal(date: todayKey, closeCount: 0);
    }
    return StartupTodoDismissal(
      date: date,
      closeCount: count.toInt().clamp(0, 3),
    );
  } catch (_) {
    return null;
  }
}

Future<void> saveStartupTodoDismissal(
  AppSettingsRepository repository, {
  required DateTime now,
  required int closeCount,
}) async {
  final value = jsonEncode({
    'date': _dateKey(now),
    'closeCount': closeCount.clamp(0, 3),
  });
  final existing = await repository.findByKey(startupTodoReminderDismissalKey);
  if (existing == null) {
    await repository.create(
      key: startupTodoReminderDismissalKey,
      value: value,
      updatedAt: now,
    );
  } else {
    await repository.update(
      startupTodoReminderDismissalKey,
      value,
      updatedAt: now,
    );
  }
}

int _compareReminderItems(
  StartupTodoReminderItem a,
  StartupTodoReminderItem b,
  DateTime today,
) {
  final aToday = _sameDate(a.date, today);
  final bToday = _sameDate(b.date, today);
  final aTimed = aToday && a.dueTime != null;
  final bTimed = bToday && b.dueTime != null;
  final aGroup = aTimed
      ? 0
      : aToday
      ? 2
      : 1;
  final bGroup = bTimed
      ? 0
      : bToday
      ? 2
      : 1;
  final group = aGroup.compareTo(bGroup);
  if (group != 0) return group;
  if (!aToday && !bToday) {
    final date = a.date.compareTo(b.date);
    if (date != 0) return date;
  }
  if (aTimed && bTimed) {
    final time = _dueMinutes(a.dueTime!).compareTo(_dueMinutes(b.dueTime!));
    if (time != 0) return time;
  }
  final priority = b.priority.compareTo(a.priority);
  if (priority != 0) return priority;
  final created = a.createdAt.compareTo(b.createdAt);
  if (created != 0) return created;
  return a.id.compareTo(b.id);
}

int _dueMinutes(String value) {
  final parts = value.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String? _parseDueTime(Object? raw) {
  if (raw is! String) return null;
  final match = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').firstMatch(raw.trim());
  return match == null ? null : raw.trim();
}

DateTime? _parseDate(Object? raw) {
  if (raw is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (match == null) return null;
  final date = DateTime.tryParse(raw);
  if (date == null || _dateKey(date) != raw) return null;
  return DateTime(date.year, date.month, date.day);
}

DateTime? _parseEpoch(Object? raw) {
  if (raw is! num || raw <= 0) return null;
  final value = raw.toInt();
  if (value < 1000000000 || value > 4102444800000) return null;
  return DateTime.fromMillisecondsSinceEpoch(value);
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
