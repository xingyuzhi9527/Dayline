import 'dart:convert';

import '../../core/database/repositories.dart';
import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/project_markdown_paths.dart';
import '../../core/markdown/markdown_storage_service.dart';

class ProjectArchiveEntry {
  const ProjectArchiveEntry({
    required this.text,
    required this.source,
    required this.createdAt,
  });

  final String text;
  final String source;
  final DateTime createdAt;
}

class ProjectMarkdownService {
  ProjectMarkdownService(AppSettingsRepository settings)
    : _storage = MarkdownStorageService(MarkdownDirectoryService(settings));

  static const archiveLocationKey = 'archiveLocation';
  static const _majorStart = '<!-- dayline:major:start -->';
  static const _majorEnd = '<!-- dayline:major:end -->';
  static const _logStart = '<!-- dayline:log:start -->';
  static const _logEnd = '<!-- dayline:log:end -->';

  final MarkdownStorageService _storage;

  Future<String> syncArchive({
    required Map<String, Object?> project,
    ProjectArchiveEntry? entry,
    bool entryAsMajor = false,
    DateTime? updatedAt,
  }) async {
    final location = project[archiveLocationKey] as String?;
    final existing = location == null ? '' : await _readOrEmpty(location);
    final nextLocation =
        location ??
        await _storage.writeRelativeTextFile(
          relativePath: _relativePath(project),
          content: '',
        );

    final content = _buildArchive(
      project: project,
      existing: existing,
      entry: entry,
      entryAsMajor: entryAsMajor,
      updatedAt: updatedAt ?? entry?.createdAt ?? DateTime.now(),
    );
    await _storage.writeTextFileLocation(nextLocation, content);
    return nextLocation;
  }

  Future<String> _readOrEmpty(String location) async {
    try {
      return await _storage.readTextFileLocation(location);
    } catch (_) {
      return '';
    }
  }

  String _buildArchive({
    required Map<String, Object?> project,
    required String existing,
    required ProjectArchiveEntry? entry,
    required bool entryAsMajor,
    required DateTime updatedAt,
  }) {
    final name = _string(project['name'], fallback: '未命名项目');
    final goal = _string(project['goal'], fallback: '慢慢推进这件事');
    final status = _string(project['status'], fallback: '进行中');
    final lastUpdate = _string(project['lastUpdate'], fallback: '刚刚');
    final todos = _listOfMaps(project['todos']);
    final updates = _listOfMaps(project['updates']);
    var majorBody = _markedBody(existing, _majorStart, _majorEnd);
    var logBody = _markedBody(existing, _logStart, _logEnd);

    if (entry != null) {
      final logLine =
          '- ${_formatDateTime(entry.createdAt)} ${entry.source}：${_oneLine(entry.text)}';
      logBody = _prepend(logBody, logLine);
      if (entryAsMajor) {
        final majorEntry =
            '### ${_formatDateTime(entry.createdAt)}\n\n${entry.text.trim()}';
        majorBody = _prepend(majorBody, majorEntry);
      }
    }

    return '${_frontMatter(project, updatedAt)}\n'
        '# $name\n\n'
        '## 目标\n'
        '$goal\n\n'
        '## 当前状态\n'
        '- 状态：$status\n'
        '- 最近更新：$lastUpdate\n'
        '- 档案更新：${_formatDateTime(updatedAt)}\n\n'
        '## 待办\n'
        '${_formatTodos(todos)}\n\n'
        '## 最近更新\n'
        '${_formatUpdates(updates)}\n\n'
        '## 重大更新\n'
        '$_majorStart\n'
        '${majorBody.trim().isEmpty ? '_暂无重大更新。_' : majorBody.trim()}\n'
        '$_majorEnd\n\n'
        '## 更新日志\n'
        '$_logStart\n'
        '${logBody.trim().isEmpty ? '_暂无更新日志。_' : logBody.trim()}\n'
        '$_logEnd\n';
  }

  String _frontMatter(Map<String, Object?> project, DateTime updatedAt) {
    final name = _string(project['name'], fallback: '未命名项目');
    final id = _string(project['id'], fallback: '');
    final status = _string(project['status'], fallback: '进行中');
    return '---\n'
        'type: project\n'
        'source: liflow\n'
        'project_id: ${_yamlString(id)}\n'
        'title: ${_yamlString(name)}\n'
        'status: ${_yamlString(status)}\n'
        'updated_at: ${updatedAt.toIso8601String()}\n'
        'tags: [项目]\n'
        '---\n';
  }

  String _formatTodos(List<Map<String, Object?>> todos) {
    if (todos.isEmpty) return '_暂无待办。_';
    return todos
        .map((todo) {
          final done = todo['done'] == true ? 'x' : ' ';
          final title = _oneLine(_string(todo['title'], fallback: '未命名待办'));
          return '- [$done] $title';
        })
        .join('\n');
  }

  String _formatUpdates(List<Map<String, Object?>> updates) {
    if (updates.isEmpty) return '_暂无最近更新。_';
    return updates
        .map((update) {
          final time = _string(update['time'], fallback: '刚刚');
          final source = _string(update['source'], fallback: '项目');
          final text = _oneLine(_string(update['text'], fallback: ''));
          return '- $time · $source：$text';
        })
        .join('\n');
  }

  String _relativePath(Map<String, Object?> project) {
    final name = _string(project['name'], fallback: 'project');
    final id = _string(project['id'], fallback: DateTime.now().toString());
    return ProjectMarkdownPaths.projectArchive(
      projectId: id,
      projectName: name,
    );
  }

  String _markedBody(String source, String start, String end) {
    final startIndex = source.indexOf(start);
    final endIndex = source.indexOf(end);
    if (startIndex < 0 || endIndex < 0 || endIndex <= startIndex) return '';
    final body = source.substring(startIndex + start.length, endIndex).trim();
    if (body.startsWith('_暂无')) return '';
    return body;
  }

  String _prepend(String existing, String value) {
    final trimmed = existing.trim();
    if (trimmed.isEmpty || trimmed.startsWith('_暂无')) return value.trim();
    return '${value.trim()}\n\n$trimmed';
  }

  List<Map<String, Object?>> _listOfMaps(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) item.cast<String, Object?>(),
    ];
  }

  String _string(Object? value, {required String fallback}) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  String _oneLine(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');

  String _yamlString(String value) => jsonEncode(value);

  String _formatDateTime(DateTime dateTime) {
    final date =
        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    final time =
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}
