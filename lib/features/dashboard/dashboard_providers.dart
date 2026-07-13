import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repositories.dart';
import '../../core/database/repository_providers.dart';
import '../../core/performance/perf_trace.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.date,
    required this.recordCount,
    required this.totalTodos,
    required this.completedTodos,
    required this.trackerCount,
    required this.focusMinutes,
    required this.expenseTotal,
    required this.monthExpenseTotal,
    required this.expenseCount,
    required this.bodyLogCount,
    required this.topTags,
    required this.categoryCounts,
    required this.firstActivityTime,
    required this.lastActivityTime,
    required this.longestGapMinutes,
    required this.densestHourRange,
    required this.insights,
    required this.allTimestamps,
    required this.isReviewed,
  });

  final String date;
  final int recordCount;
  final int totalTodos;
  final int completedTodos;
  final int trackerCount;
  final int focusMinutes;
  final double expenseTotal;
  final double monthExpenseTotal;
  final int expenseCount;
  final int bodyLogCount;
  final List<String> topTags;
  final Map<String, int> categoryCounts;
  final int? firstActivityTime;
  final int? lastActivityTime;
  final int longestGapMinutes;
  final String densestHourRange;
  final List<String> insights;
  final List<int> allTimestamps;
  final bool isReviewed;

  bool get hasData =>
      recordCount > 0 ||
      totalTodos > 0 ||
      trackerCount > 0 ||
      focusMinutes > 0 ||
      expenseCount > 0 ||
      bodyLogCount > 0;

  bool get hasUnfinishedTodos => totalTodos > completedTodos;
}

final dashboardDayBundleForDateProvider = FutureProvider.autoDispose
    .family<DashboardDayBundle, String>((ref, dateValue) async {
      for (final domain in const [
        DataDomain.records,
        DataDomain.todos,
        DataDomain.trackerLogs,
        DataDomain.focus,
        DataDomain.expenses,
        DataDomain.bodyLogs,
        DataDomain.reviews,
      ]) {
        ref.watch(dataDomainVersionProvider(domain));
      }
      final day = _dayFromDateKey(dateValue);
      return PerfTrace.measure(
        'dashboard.day_bundle $dateValue',
        () => ref.read(dashboardRepositoryProvider).loadDayBundle(day),
      );
    });

/// Loads a dashboard for a canonical `yyyy-MM-dd` date key.
///
/// Keeping the family argument as a date-only string is intentional: using a
/// `DateTime` here would create a distinct provider/cache entry for every
/// timestamp passed by a caller, even when all those timestamps refer to the
/// same calendar day.
final dashboardSummaryForDateProvider = FutureProvider.autoDispose
    .family<DashboardSummary, String>((ref, dateValue) async {
      final day = _dayFromDateKey(dateValue);
      final bundle = await ref.watch(
        dashboardDayBundleForDateProvider(dateValue).future,
      );
      return _buildDashboardSummary(day, bundle);
    });

final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>((
  ref,
) {
  return ref.watch(
    dashboardSummaryForDateProvider(dateKey(DateTime.now())).future,
  );
});

String dashboardNarrativeDayLabel(DateTime date, {DateTime? today}) {
  final anchor = today ?? DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final todayOnly = DateTime(anchor.year, anchor.month, anchor.day);
  if (day == todayOnly) return '今天';
  if (day == todayOnly.subtract(const Duration(days: 1))) return '昨天';
  if (day == todayOnly.subtract(const Duration(days: 2))) return '前天';
  return '这一天';
}

String _pad(int n) => n.toString().padLeft(2, '0');

int _calcLongestGap(List<int> sortedTimestamps) {
  if (sortedTimestamps.length < 2) return 0;
  var maxGap = 0;
  for (var i = 1; i < sortedTimestamps.length; i++) {
    final gapMs = sortedTimestamps[i] - sortedTimestamps[i - 1];
    final gapMin = (gapMs / 60000).round();
    if (gapMin > maxGap) maxGap = gapMin;
  }
  return maxGap;
}

String _calcDensestHour(List<int> sortedTimestamps) {
  if (sortedTimestamps.isEmpty) return '-';
  final hourCounts = List.filled(24, 0);
  for (final ts in sortedTimestamps) {
    final hour = DateTime.fromMillisecondsSinceEpoch(ts).hour;
    hourCounts[hour]++;
  }
  var maxCount = 0;
  var densestHour = -1;
  for (var h = 0; h < 24; h++) {
    if (hourCounts[h] > maxCount) {
      maxCount = hourCounts[h];
      densestHour = h;
    }
  }
  if (maxCount == 0) return '-';
  return '${_pad(densestHour)}:00-${_pad((densestHour + 1) % 24)}:00';
}

List<String> _generateInsights({
  required String dayLabel,
  required int recordCount,
  required int totalTodos,
  required int completedTodos,
  required int focusMinutes,
  required List<String> topTags,
  required Map<String, int> tagCounts,
  required int? firstActivityTime,
  required int? lastActivityTime,
  required int longestGapMinutes,
  required String densestHourRange,
}) {
  final insights = <String>[];
  if (recordCount < 3) return insights;

  if (densestHourRange != '-') {
    insights.add('$dayLabel最密集的记录出现在 $densestHourRange。');
  }

  if (topTags.isNotEmpty) {
    final topTag = topTags.first;
    final topCount = tagCounts[topTag] ?? 0;
    if (topCount >= 2) {
      insights.add('$dayLabel"$topTag"相关内容最多。');
    }
  }

  if (longestGapMinutes >= 120) {
    final hours = longestGapMinutes ~/ 60;
    final mins = longestGapMinutes % 60;
    final gapText = hours > 0
        ? '$hours小时${mins > 0 ? '$mins分钟' : ''}'
        : '$longestGapMinutes分钟';
    insights.add('$dayLabel存在较长的空白时段（$gapText）。');
  }

  if (totalTodos > 0 && completedTodos == 0) {
    insights.add('$dayLabel有待办事项未完成，可以先标记。');
  }

  if (totalTodos > 0 && completedTodos == totalTodos) {
    insights.add('$dayLabel的待办全部完成。');
  }

  if (focusMinutes >= 60) {
    insights.add('$dayLabel专注了 $focusMinutes 分钟，表现很好。');
  }

  return insights.take(3).toList();
}

List<String> _parseTags(String raw) {
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<String>();
  } catch (_) {
    return const [];
  }
}

final dashboardReviewForDateProvider = FutureProvider.autoDispose
    .family<Map<String, Object?>?, String>((ref, dateValue) async {
      ref.watch(dataDomainVersionProvider(DataDomain.reviews));
      final bundle = await ref.watch(
        dashboardDayBundleForDateProvider(dateValue).future,
      );
      return bundle.review;
    });

final dashboardReviewProvider =
    FutureProvider.autoDispose<Map<String, Object?>?>((ref) {
      return ref.watch(
        dashboardReviewForDateProvider(dateKey(DateTime.now())).future,
      );
    });

DateTime _dayFromDateKey(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw ArgumentError.value(value, 'value', 'Expected a yyyy-MM-dd date');
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

DashboardSummary _buildDashboardSummary(
  DateTime day,
  DashboardDayBundle bundle,
) {
  final dateStr = dateKey(day);
  final records = _rowsOfKind(bundle.activityRows, 'record');
  final todos = _rowsOfKind(bundle.activityRows, 'todo');
  final trackerLogs = _rowsOfKind(bundle.activityRows, 'tracker');
  final focusSessions = _rowsOfKind(bundle.activityRows, 'focus');
  final expenses = _rowsOfKind(bundle.activityRows, 'expense');
  final bodyLogs = _rowsOfKind(bundle.activityRows, 'body');

  final focusMinutes = focusSessions.fold<int>(0, (sum, row) {
    return sum + _intValue(row['duration_minutes']);
  });
  final expenseTotal = expenses.fold<double>(0, (sum, row) {
    return sum + _doubleValue(row['amount']);
  });

  final tagCounts = <String, int>{};
  for (final r in records) {
    final tags = _parseTags((r['tags'] as String?) ?? '[]');
    for (final tag in tags) {
      tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
    }
  }
  final sortedTags = tagCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topTags = sortedTags.take(5).map((e) => e.key).toList();

  final timestamps = <int>[];
  for (final r in records) {
    timestamps.add(_intValue(r['created_at']));
  }
  for (final t in todos) {
    timestamps.add(_intValue(t['created_at']));
    final completedAt = _intValueOrNull(t['completed_at']);
    if (completedAt != null) timestamps.add(completedAt);
  }
  for (final l in trackerLogs) {
    timestamps.add(_intValue(l['created_at']));
  }
  for (final e in expenses) {
    timestamps.add(_intValue(e['created_at']));
  }
  for (final b in bodyLogs) {
    timestamps.add(_intValue(b['created_at']));
  }
  timestamps.sort();

  final firstActivityTime = timestamps.isNotEmpty ? timestamps.first : null;
  final lastActivityTime = timestamps.isNotEmpty ? timestamps.last : null;
  final longestGapMinutes = _calcLongestGap(timestamps);
  final densestHourRange = _calcDensestHour(timestamps);
  final completedTodos = todos
      .where((t) => _intValue(t['is_completed']) == 1)
      .length;
  final insights = _generateInsights(
    dayLabel: dashboardNarrativeDayLabel(day),
    recordCount: records.length,
    totalTodos: todos.length,
    completedTodos: completedTodos,
    focusMinutes: focusMinutes,
    topTags: topTags,
    tagCounts: tagCounts,
    firstActivityTime: firstActivityTime,
    lastActivityTime: lastActivityTime,
    longestGapMinutes: longestGapMinutes,
    densestHourRange: densestHourRange,
  );

  return DashboardSummary(
    date: dateStr,
    recordCount: records.length,
    totalTodos: todos.length,
    completedTodos: completedTodos,
    trackerCount: trackerLogs.length,
    focusMinutes: focusMinutes,
    expenseTotal: expenseTotal,
    monthExpenseTotal: bundle.monthExpenseTotal,
    expenseCount: expenses.length,
    bodyLogCount: bodyLogs.length,
    topTags: topTags,
    categoryCounts: tagCounts,
    firstActivityTime: firstActivityTime,
    lastActivityTime: lastActivityTime,
    longestGapMinutes: longestGapMinutes,
    densestHourRange: densestHourRange,
    insights: insights,
    allTimestamps: timestamps,
    isReviewed: bundle.review != null,
  );
}

List<DatabaseRow> _rowsOfKind(List<DatabaseRow> rows, String kind) {
  return rows.where((row) => row['kind'] == kind).toList(growable: false);
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

int? _intValueOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double _doubleValue(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
