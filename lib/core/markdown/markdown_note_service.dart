import 'dart:io';

import 'package:path/path.dart' as p;

import 'markdown_directory_service.dart';
import 'markdown_filename.dart';

class MarkdownNoteService {
  MarkdownNoteService(this._dirService);

  final MarkdownDirectoryService _dirService;

  Future<String> saveDailyNote(
    DateTime date,
    String markdownContent,
  ) async {
    final dir = await _dirService.ensureDailyDir(date);
    final filename = MarkdownFilename.generate(
      date,
      mode: MarkdownNamingMode.date,
    );
    final file = File(p.join(dir, filename));
    await file.writeAsString(markdownContent);
    return file.path;
  }

  Future<String> saveLongNote({
    required String? title,
    required String body,
    required DateTime dateTime,
  }) async {
    final dir = await _dirService.ensureNotesDir(dateTime);
    final filename = MarkdownFilename.generate(
      dateTime,
      title: title,
      mode: _dirService.namingMode,
    );
    final file = File(p.join(dir, filename));

    final dateStr = _fmtDate(dateTime);
    final timeStr = _fmtTime(dateTime);
    final resolvedTitle = (title != null && title.trim().isNotEmpty)
        ? title.trim()
        : '$dateStr $timeStr';

    final front = _buildFrontMatter(
      type: 'note',
      title: resolvedTitle,
      dateTime: dateTime,
    );
    final content = '$front\n# $resolvedTitle\n\n$body\n';

    await file.writeAsString(content);
    return file.path;
  }

  String _buildFrontMatter({
    required String type,
    required String title,
    required DateTime dateTime,
  }) {
    final iso = dateTime.toIso8601String();
    return '---\n'
        'type: $type\n'
        'source: liflow\n'
        'created_at: $iso\n'
        'updated_at: $iso\n'
        'title: $title\n'
        'tags: []\n'
        '---\n';
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
