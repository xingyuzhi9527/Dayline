import 'package:path/path.dart' as p;

import 'markdown_directory_service.dart';
import 'markdown_filename.dart';
import 'markdown_storage_service.dart';

class MarkdownNoteService {
  MarkdownNoteService(this._dirService)
    : _storage = MarkdownStorageService(_dirService);

  final MarkdownDirectoryService _dirService;
  final MarkdownStorageService _storage;

  Future<String> saveDailyNote(DateTime date, String markdownContent) async {
    final filename = MarkdownFilename.generate(
      date,
      mode: MarkdownNamingMode.date,
    );
    final relativePath = p.posix.join(
      'daily',
      MarkdownFilename.monthDir(date),
      filename,
    );
    return _storage.writeRelativeTextFile(
      relativePath: relativePath,
      content: markdownContent,
    );
  }

  Future<String> saveLongNote({
    required String? title,
    required String body,
    required DateTime dateTime,
  }) async {
    final filename = MarkdownFilename.generate(
      dateTime,
      title: title,
      mode: _dirService.namingMode,
    );
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
    final relativePath = p.posix.join(
      'notes',
      MarkdownFilename.monthDir(dateTime),
      filename,
    );
    return _storage.writeRelativeTextFile(
      relativePath: relativePath,
      content: content,
    );
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
