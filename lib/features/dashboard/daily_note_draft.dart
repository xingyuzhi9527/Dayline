import '../../core/database/repositories.dart';
import '../../core/database/repository_providers.dart';
import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/markdown_note_service.dart';
import '../../core/markdown/markdown_storage_service.dart';

enum DailyNoteStatus { missing, draft, finalNote }

class DailyNoteInfo {
  const DailyNoteInfo({
    required this.date,
    required this.status,
    this.location,
  });

  final DateTime date;
  final DailyNoteStatus status;
  final String? location;

  bool get exists => location != null;
  bool get isDraft => status == DailyNoteStatus.draft;
}

Future<DailyNoteInfo> loadDailyNoteInfo(Object ref, DateTime date) async {
  final day = _dateOnly(date);
  final settings = _read(ref, appSettingsRepositoryProvider);
  final dirService = MarkdownDirectoryService(settings);
  if (!await dirService.isConfigured()) {
    return DailyNoteInfo(date: day, status: DailyNoteStatus.missing);
  }

  final noteService = MarkdownNoteService(dirService);
  final location = await noteService.findDailyNote(day);
  if (location == null) {
    return DailyNoteInfo(date: day, status: DailyNoteStatus.missing);
  }

  final storage = MarkdownStorageService(dirService);
  final raw = await storage.readTextFileLocation(location);
  return DailyNoteInfo(
    date: day,
    status: isDailyNoteDraftContent(raw)
        ? DailyNoteStatus.draft
        : DailyNoteStatus.finalNote,
    location: location,
  );
}

Future<void> ensureDailyDraftAfterActivity(Object ref, DateTime date) async {
  try {
    final day = _dateOnly(date);
    final settings = _read(ref, appSettingsRepositoryProvider);
    final dirService = MarkdownDirectoryService(settings);
    if (!await dirService.isConfigured()) return;

    final noteService = MarkdownNoteService(dirService);
    final activityCount = await _activityCount(ref, day);
    final location = await noteService.findDailyNote(day);
    if (location != null) {
      final storage = MarkdownStorageService(dirService);
      final raw = await storage.readTextFileLocation(location);
      if (!isDailyNoteDraftContent(raw)) return;

      final updated = refreshDailyDraftActivityCount(
        raw,
        activityCount: activityCount,
      );
      if (updated != raw) {
        await storage.writeTextFileLocation(location, updated);
      }
      return;
    }

    if (activityCount == 0) return;
    await noteService.saveDailyNote(
      day,
      buildDailyDraftMarkdown(date: day, activityCount: activityCount),
    );
  } catch (_) {
    // Recording should never fail just because the optional Markdown draft did.
  }
}

bool isDailyNoteDraftContent(String raw) {
  return RegExp(r'^status:\s*draft\s*$', multiLine: true).hasMatch(raw);
}

String refreshDailyDraftActivityCount(
  String raw, {
  required int activityCount,
  DateTime? generatedAt,
}) {
  if (!isDailyNoteDraftContent(raw)) return raw;

  var updated = raw;
  final now = (generatedAt ?? DateTime.now()).toIso8601String();
  updated = _upsertFrontMatterLine(updated, 'generated_at', now);
  updated = _upsertFrontMatterLine(updated, 'record_count', '$activityCount');
  return updated;
}

String _upsertFrontMatterLine(String raw, String key, String value) {
  final frontMatterEnd = raw.indexOf('\n---\n', 4);
  if (!raw.startsWith('---\n') || frontMatterEnd == -1) return raw;

  final linePattern = RegExp('^$key:.*\$', multiLine: true);
  if (linePattern.hasMatch(raw.substring(0, frontMatterEnd))) {
    return raw.replaceFirst(linePattern, '$key: $value');
  }

  return '${raw.substring(0, frontMatterEnd)}\n$key: $value${raw.substring(frontMatterEnd)}';
}

String buildDailyDraftMarkdown({
  required DateTime date,
  required int activityCount,
}) {
  final day = dateKey(date);
  final now = DateTime.now().toIso8601String();
  return '''
---
date: $day
title: $day 日记草稿
source: liflow
version: 1
status: draft
generated_at: $now
record_count: $activityCount
tags: []
---

# $day 日记草稿

## 今日概览

今天已经开始记录，晚上可以把这些片段整理成最终日记。

## 晚间复盘

### 今天值得保留的是

...

### 今天可以调整的是

...

### 明天最小行动是

...

## 原始记录索引

本节保留给未来 AI 检索与结构化分析。
''';
}

Future<int> _activityCount(Object ref, DateTime date) async {
  final records = await _read(ref, recordsRepositoryProvider).countByDate(date);
  final todos = await _read(ref, todosRepositoryProvider).countByDate(date);
  final trackerLogs = await _read(
    ref,
    trackerLogsRepositoryProvider,
  ).countByDate(date);
  final focusSessions = await _read(
    ref,
    focusSessionsRepositoryProvider,
  ).findByDate(date);
  final expenses = await _read(
    ref,
    expensesRepositoryProvider,
  ).findByDate(date);
  final bodyLogs = await _read(
    ref,
    bodyLogsRepositoryProvider,
  ).findByDate(date);

  return records +
      todos +
      trackerLogs +
      focusSessions.length +
      expenses.length +
      bodyLogs.length;
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

T _read<T>(Object ref, dynamic provider) {
  return (ref as dynamic).read(provider) as T;
}
