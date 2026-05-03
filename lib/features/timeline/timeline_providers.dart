import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repositories.dart';
import '../../core/database/repository_providers.dart';

class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.timestamp,
    required this.date,
    required this.icon,
    required this.tags,
  });

  final String id;
  final String type;
  final String title;
  final String description;
  final int timestamp;
  final String date;
  final IconData icon;
  final List<String> tags;
}

class TimelineDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();

  void goToPrevDay() => state = state.subtract(const Duration(days: 1));

  void goToNextDay() => state = state.add(const Duration(days: 1));

  void goToToday() => state = DateTime.now();
}

final timelineDateProvider = NotifierProvider<TimelineDateNotifier, DateTime>(
  TimelineDateNotifier.new,
);

final timelineEventsProvider = FutureProvider<List<TimelineEvent>>((ref) async {
  final date = ref.watch(timelineDateProvider);
  ref.watch(dataVersionProvider);

  return loadTimelineEventsForDate(ref, date);
});

Future<List<TimelineEvent>> loadTimelineEventsForDate(
  Ref ref,
  DateTime date,
) async {
  final dateStr = dateKey(date);
  final events = <TimelineEvent>[];

  final trackerNames = <int, String>{};
  try {
    final trackers = await ref.read(trackersRepositoryProvider).findAll();
    for (final t in trackers) {
      trackerNames[t['id'] as int] = t['name'] as String;
    }
  } catch (_) {}

  try {
    final records = await ref.read(recordsRepositoryProvider).findByDate(date);
    for (final r in records) {
      final type = r['type'] as String;
      events.add(
        TimelineEvent(
          id: 'records:${r['id']}',
          type: type,
          title: r['content'] as String,
          description: (r['time'] as String?) ?? '',
          timestamp: r['created_at'] as int,
          date: dateStr,
          icon: _iconForType(type),
          tags: _parseTags(r['tags'] as String),
        ),
      );
    }
  } catch (_) {}

  try {
    final todos = await ref.read(todosRepositoryProvider).findByDate(date);
    for (final t in todos) {
      final isCompleted = (t['is_completed'] as int) == 1;
      events.add(
        TimelineEvent(
          id: 'todos:${t['id']}',
          type: 'todo',
          title: t['title'] as String,
          description: isCompleted ? '已完成' : '待完成',
          timestamp: t['created_at'] as int,
          date: dateStr,
          icon: isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
          tags: const [],
        ),
      );
    }
  } catch (_) {}

  try {
    final logs = await ref.read(trackerLogsRepositoryProvider).findByDate(date);
    for (final l in logs) {
      final trackerId = l['tracker_id'] as int;
      final name = trackerNames[trackerId] ?? '打卡';
      events.add(
        TimelineEvent(
          id: 'tracker_logs:${l['id']}',
          type: 'tracker',
          title: name,
          description: (l['note'] as String?) ?? '打卡 ×${l['value'] ?? 1}',
          timestamp: l['created_at'] as int,
          date: dateStr,
          icon: Icons.check_rounded,
          tags: const [],
        ),
      );
    }
  } catch (_) {}

  try {
    final sessions = await ref
        .read(focusSessionsRepositoryProvider)
        .findByDate(date);
    for (final s in sessions) {
      final mins = s['duration_minutes'] as int;
      events.add(
        TimelineEvent(
          id: 'focus_sessions:${s['id']}',
          type: 'focus',
          title: (s['note'] as String?) ?? '专注 $mins 分钟',
          description: '$mins min',
          timestamp: s['created_at'] as int,
          date: dateStr,
          icon: Icons.timer_rounded,
          tags: const [],
        ),
      );
    }
  } catch (_) {}

  try {
    final expenses = await ref
        .read(expensesRepositoryProvider)
        .findByDate(date);
    for (final e in expenses) {
      final amount = e['amount'] as num;
      final category = e['category'] as String;
      events.add(
        TimelineEvent(
          id: 'expenses:${e['id']}',
          type: 'expense',
          title: '$category ¥${amount.toStringAsFixed(2)}',
          description: (e['note'] as String?) ?? '',
          timestamp: e['created_at'] as int,
          date: dateStr,
          icon: Icons.payments_rounded,
          tags: const [],
        ),
      );
    }
  } catch (_) {}

  try {
    final bodyLogs = await ref
        .read(bodyLogsRepositoryProvider)
        .findByDate(date);
    for (final b in bodyLogs) {
      final metric = b['metric'] as String;
      final value = b['value'] as num;
      final unit = (b['unit'] as String?) ?? '';
      events.add(
        TimelineEvent(
          id: 'body_logs:${b['id']}',
          type: 'body',
          title: '$metric: $value${unit.isNotEmpty ? ' $unit' : ''}',
          description: (b['note'] as String?) ?? '',
          timestamp: b['created_at'] as int,
          date: dateStr,
          icon: Icons.monitor_weight_rounded,
          tags: const [],
        ),
      );
    }
  } catch (_) {}

  events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return events;
}

IconData _iconForType(String type) => switch (type) {
  'memo' => Icons.notes_rounded,
  'todo' => Icons.check_circle_outline,
  'tracker' => Icons.check_rounded,
  'focus' => Icons.timer_rounded,
  'expense' => Icons.payments_rounded,
  'body' => Icons.monitor_weight_rounded,
  'sleep' => Icons.bedtime_rounded,
  _ => Icons.notes_rounded,
};

List<String> _parseTags(String raw) {
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<String>();
  } catch (_) {
    return const [];
  }
}
