import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repositories.dart';
import '../../core/database/repository_providers.dart';

class DailySummary {
  const DailySummary({
    required this.date,
    required this.recordCount,
    required this.totalTodos,
    required this.completedTodos,
    required this.trackerCount,
    required this.focusMinutes,
    required this.expenseTotal,
    required this.topTags,
    required this.activeHourRange,
    required this.summaryText,
  });

  final String date;
  final int recordCount;
  final int totalTodos;
  final int completedTodos;
  final int trackerCount;
  final int focusMinutes;
  final double expenseTotal;
  final List<String> topTags;
  final String activeHourRange;
  final String summaryText;

  bool get hasData => recordCount > 0 || totalTodos > 0 || trackerCount > 0;
}

class ReviewDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();

  void goToPrevDay() => state = state.subtract(const Duration(days: 1));

  void goToNextDay() => state = state.add(const Duration(days: 1));

  void goToToday() => state = DateTime.now();
}

final reviewDateProvider = NotifierProvider<ReviewDateNotifier, DateTime>(
  ReviewDateNotifier.new,
);

final dailySummaryProvider = FutureProvider<DailySummary>((ref) async {
  final date = ref.watch(reviewDateProvider);
  ref.watch(dataVersionProvider);

  final dateStr = dateKey(date);

  // Fetch all data for the date
  final records = await ref.read(recordsRepositoryProvider).findByDate(date);
  final todos = await ref.read(todosRepositoryProvider).findByDate(date);
  final trackerLogs = await ref
      .read(trackerLogsRepositoryProvider)
      .findByDate(date);
  final focusMinutes = await ref
      .read(focusSessionsRepositoryProvider)
      .sumMinutesByDate(date);
  final expenseTotal = await ref
      .read(expensesRepositoryProvider)
      .sumAmountByDate(date);

  // Counts
  final recordCount = records.length;
  final totalTodos = todos.length;
  final completedTodos = todos
      .where((t) => (t['is_completed'] as int) == 1)
      .length;
  final trackerCount = trackerLogs.length;

  // Top tags from records
  final tagCounts = <String, int>{};
  for (final r in records) {
    final tags = _parseTags(r['tags'] as String);
    for (final tag in tags) {
      tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
    }
  }
  final sortedTags = tagCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topTags = sortedTags.take(5).map((e) => e.key).toList(growable: false);

  // Active hour range — collect all meaningful timestamps
  final timestamps = <int>[];
  for (final r in records) {
    timestamps.add(r['created_at'] as int);
  }
  for (final t in todos) {
    timestamps.add(t['created_at'] as int);
    if (t['completed_at'] != null) {
      timestamps.add(t['completed_at'] as int);
    }
  }
  for (final l in trackerLogs) {
    timestamps.add(l['created_at'] as int);
  }

  String activeHourRange = '-';
  if (timestamps.isNotEmpty) {
    timestamps.sort();
    final earliest = DateTime.fromMillisecondsSinceEpoch(timestamps.first);
    final latest = DateTime.fromMillisecondsSinceEpoch(timestamps.last);
    activeHourRange =
        '${_pad(earliest.hour)}:${_pad(earliest.minute)} - '
        '${_pad(latest.hour)}:${_pad(latest.minute)}';
  }

  // Build summary text
  final tagText = topTags.isNotEmpty ? '今日关键词包括：${topTags.join('、')}。' : '';

  final summaryText =
      '今天共记录 $recordCount 条内容，'
      '完成 $completedTodos/$totalTodos 个待办，'
      '打卡 $trackerCount 次，'
      '专注 $focusMinutes 分钟。'
      '最活跃的时间段是 $activeHourRange。'
      '$tagText';

  return DailySummary(
    date: dateStr,
    recordCount: recordCount,
    totalTodos: totalTodos,
    completedTodos: completedTodos,
    trackerCount: trackerCount,
    focusMinutes: focusMinutes,
    expenseTotal: expenseTotal,
    topTags: topTags,
    activeHourRange: activeHourRange,
    summaryText: summaryText,
  );
});

String _pad(int n) => n.toString().padLeft(2, '0');

List<String> _parseTags(String raw) {
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<String>();
  } catch (_) {
    return const [];
  }
}
