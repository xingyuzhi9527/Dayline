import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../database/repositories.dart';

class ExportService {
  const ExportService._();

  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  static String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日 ${_weekdays[date.weekday - 1]}';
  }

  static String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String exportMarkdown({
    required DateTime date,
    required String summaryText,
    required List<Map<String, Object?>> records,
    required List<Map<String, Object?>> todos,
    required List<Map<String, Object?>> trackerLogs,
    required List<Map<String, Object?>> focusSessions,
    required List<Map<String, Object?>> expenses,
    required List<Map<String, Object?>> bodyLogs,
    required Map<int, String> trackerNames,
  }) {
    final buf = StringBuffer();

    buf.writeln('# Dayline 复盘');
    buf.writeln();
    buf.writeln('**日期**：${_formatDate(date)}');
    buf.writeln();

    buf.writeln('## 总结');
    buf.writeln();
    buf.writeln(summaryText);
    buf.writeln();

    final timeline = _buildTimeline(
      records: records,
      todos: todos,
      trackerLogs: trackerLogs,
      focusSessions: focusSessions,
      expenses: expenses,
      bodyLogs: bodyLogs,
      trackerNames: trackerNames,
    );
    if (timeline.isNotEmpty) {
      buf.writeln('## 时间线');
      buf.writeln();
      for (final item in timeline) {
        buf.writeln('- ${item['time']} ${item['text']}');
      }
      buf.writeln();
    }

    if (todos.isNotEmpty) {
      buf.writeln('## 待办');
      buf.writeln();
      for (final t in todos) {
        final done = (t['is_completed'] as int) == 1;
        buf.writeln('- ${done ? '[x]' : '[ ]'} ${t['title']}');
      }
      buf.writeln();
    }

    final memos = records.where((r) => r['type'] == 'memo').toList();
    if (memos.isNotEmpty) {
      buf.writeln('## 备忘');
      buf.writeln();
      for (final memo in memos) {
        final time = memo['time'] as String?;
        final content = memo['content'];
        final tags = _parseTags(memo['tags'] as String);
        final tagText = tags.map((tag) => '#$tag').join(' ');
        final timePart = time != null ? '($time) ' : '';
        buf.writeln('- $timePart$content ${tagText.isNotEmpty ? tagText : ''}');
      }
      buf.writeln();
    }

    if (focusSessions.isNotEmpty) {
      buf.writeln('## 专注');
      buf.writeln();
      for (final focus in focusSessions) {
        final mins = focus['duration_minutes'] as int;
        final note = focus['note'] as String?;
        final startedAt = focus['started_at'] as int;
        buf.writeln('- ${note ?? '专注'}，$mins 分钟（${_formatTime(startedAt)}）');
      }
      buf.writeln();
    }

    if (expenses.isNotEmpty) {
      buf.writeln('## 消费');
      buf.writeln();
      for (final expense in expenses) {
        final amount = expense['amount'] as num;
        final category = expense['category'] as String;
        final note = expense['note'] as String?;
        final noteText = note != null && note.isNotEmpty ? '，$note' : '';
        buf.writeln('- $category：¥${amount.toStringAsFixed(2)}$noteText');
      }
      buf.writeln();
    }

    if (bodyLogs.isNotEmpty) {
      buf.writeln('## 身体');
      buf.writeln();
      for (final body in bodyLogs) {
        final metric = body['metric'] as String;
        final value = body['value'] as num;
        final unit = body['unit'] as String?;
        buf.writeln('- $metric：$value${unit != null ? ' $unit' : ''}');
      }
      buf.writeln();
    }

    return buf.toString();
  }

  static List<Map<String, String>> _buildTimeline({
    required List<Map<String, Object?>> records,
    required List<Map<String, Object?>> todos,
    required List<Map<String, Object?>> trackerLogs,
    required List<Map<String, Object?>> focusSessions,
    required List<Map<String, Object?>> expenses,
    required List<Map<String, Object?>> bodyLogs,
    required Map<int, String> trackerNames,
  }) {
    final items = <Map<String, String>>[];

    for (final record in records) {
      items.add({
        'time': _formatTime(record['created_at'] as int),
        'text': '${record['content']}',
        'ts': '${record['created_at']}',
      });
    }

    for (final todo in todos) {
      final done = (todo['is_completed'] as int) == 1;
      items.add({
        'time': _formatTime(todo['created_at'] as int),
        'text': '${done ? '完成' : '待办'}：${todo['title']}',
        'ts': '${todo['created_at']}',
      });
    }

    for (final log in trackerLogs) {
      final trackerId = log['tracker_id'] as int;
      final name = trackerNames[trackerId] ?? '打卡';
      items.add({
        'time': _formatTime(log['created_at'] as int),
        'text': '打卡：$name',
        'ts': '${log['created_at']}',
      });
    }

    for (final focus in focusSessions) {
      final mins = focus['duration_minutes'] as int;
      final note = focus['note'] as String?;
      items.add({
        'time': _formatTime(focus['started_at'] as int),
        'text': '专注：${note ?? '专注'}（$mins 分钟）',
        'ts': '${focus['started_at']}',
      });
    }

    for (final expense in expenses) {
      final amount = expense['amount'] as num;
      final category = expense['category'] as String;
      items.add({
        'time': _formatTime(expense['created_at'] as int),
        'text': '消费：$category ¥${amount.toStringAsFixed(2)}',
        'ts': '${expense['created_at']}',
      });
    }

    for (final body in bodyLogs) {
      final metric = body['metric'] as String;
      final value = body['value'] as num;
      items.add({
        'time': _formatTime(body['created_at'] as int),
        'text': '身体：$metric $value',
        'ts': '${body['created_at']}',
      });
    }

    items.sort((a, b) => a['ts']!.compareTo(b['ts']!));
    for (final item in items) {
      item.remove('ts');
    }

    return items;
  }

  static String exportJson({
    required DateTime date,
    required Map<String, Object?> summary,
    required List<Map<String, Object?>> records,
    required List<Map<String, Object?>> todos,
    required List<Map<String, Object?>> trackerLogs,
    required List<Map<String, Object?>> focusSessions,
    required List<Map<String, Object?>> expenses,
    required List<Map<String, Object?>> bodyLogs,
  }) {
    final map = <String, dynamic>{
      'date': dateKey(date),
      'summary': summary,
      'records': records,
      'todos': todos,
      'tracker_logs': trackerLogs,
      'focus_sessions': focusSessions,
      'expenses': expenses,
      'body_logs': bodyLogs,
    };

    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static Future<String> saveFile(
    String content,
    String filename,
    String directory,
  ) async {
    final file = File(p.join(directory, filename));
    await file.writeAsString(content);
    return file.path;
  }
}

List<String> _parseTags(String raw) {
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<String>();
  } catch (_) {
    return const [];
  }
}
