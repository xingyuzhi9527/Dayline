import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/review/review_providers.dart';
import '../database/repositories.dart';
import '../database/repository_providers.dart';
import 'export_service.dart';

final exportDirectoryProvider = FutureProvider<String>((ref) async {
  final dir = await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  return dir.path;
});

Future<String> exportMarkdownToFile(WidgetRef ref, DateTime date) async {
  final dateStr = dateKey(date);

  final records = await ref.read(recordsRepositoryProvider).findByDate(date);
  final todos = await ref.read(todosRepositoryProvider).findByDate(date);
  final trackerLogs = await ref
      .read(trackerLogsRepositoryProvider)
      .findByDate(date);
  final focusSessions = await ref
      .read(focusSessionsRepositoryProvider)
      .findByDate(date);
  final expenses = await ref.read(expensesRepositoryProvider).findByDate(date);
  final bodyLogs = await ref.read(bodyLogsRepositoryProvider).findByDate(date);

  final summary = await ref.read(dailySummaryProvider.future);

  final trackers = await ref.read(trackersRepositoryProvider).findAll();
  final trackerNames = <int, String>{};
  for (final t in trackers) {
    trackerNames[t['id'] as int] = t['name'] as String;
  }

  final md = ExportService.exportMarkdown(
    date: date,
    summaryText: summary.summaryText,
    records: records,
    todos: todos,
    trackerLogs: trackerLogs,
    focusSessions: focusSessions,
    expenses: expenses,
    bodyLogs: bodyLogs,
    trackerNames: trackerNames,
  );

  final dir = await ref.read(exportDirectoryProvider.future);
  final filename = 'liflow_$dateStr.md';
  return ExportService.saveFile(md, filename, dir);
}

Future<String> exportJsonToFile(WidgetRef ref, DateTime date) async {
  final records = await ref.read(recordsRepositoryProvider).findByDate(date);
  final todos = await ref.read(todosRepositoryProvider).findByDate(date);
  final trackerLogs = await ref
      .read(trackerLogsRepositoryProvider)
      .findByDate(date);
  final focusSessions = await ref
      .read(focusSessionsRepositoryProvider)
      .findByDate(date);
  final expenses = await ref.read(expensesRepositoryProvider).findByDate(date);
  final bodyLogs = await ref.read(bodyLogsRepositoryProvider).findByDate(date);

  final summary = await ref.read(dailySummaryProvider.future);

  final dateStr = dateKey(date);
  final json = ExportService.exportJson(
    date: date,
    summary: {
      'date': summary.date,
      'recordCount': summary.recordCount,
      'totalTodos': summary.totalTodos,
      'completedTodos': summary.completedTodos,
      'trackerCount': summary.trackerCount,
      'focusMinutes': summary.focusMinutes,
      'expenseTotal': summary.expenseTotal,
      'topTags': summary.topTags,
      'activeHourRange': summary.activeHourRange,
      'summaryText': summary.summaryText,
    },
    records: records,
    todos: todos,
    trackerLogs: trackerLogs,
    focusSessions: focusSessions,
    expenses: expenses,
    bodyLogs: bodyLogs,
  );

  final dir = await ref.read(exportDirectoryProvider.future);
  final filename = 'liflow_$dateStr.json';
  return ExportService.saveFile(json, filename, dir);
}
