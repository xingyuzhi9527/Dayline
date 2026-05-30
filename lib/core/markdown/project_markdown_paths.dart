import 'dart:convert';

import 'package:path/path.dart' as p;

import 'markdown_filename.dart';

class ProjectMarkdownPaths {
  const ProjectMarkdownPaths._();

  static String projectFolder({
    required String projectId,
    required String projectName,
  }) {
    final name = _safeFilePart(projectName, fallback: 'project');
    final cleanedId = _safeFilePart(projectId, fallback: 'project');
    final trimmedId = cleanedId.startsWith('project-')
        ? cleanedId.substring('project-'.length)
        : cleanedId;
    final suffixSource = trimmedId.isEmpty ? cleanedId : trimmedId;
    final suffix = String.fromCharCodes(suffixSource.runes.take(8));
    return p.posix.join('projects', '$name-$suffix');
  }

  static String projectArchive({
    required String projectId,
    required String projectName,
  }) {
    return p.posix.join(
      projectFolder(projectId: projectId, projectName: projectName),
      'project.md',
    );
  }

  static String projectLongNote({
    required String projectId,
    required String projectName,
    required DateTime dateTime,
    required String filename,
  }) {
    return p.posix.join(
      projectFolder(projectId: projectId, projectName: projectName),
      'notes',
      filename,
    );
  }

  static String projectImageMaterial({
    required String projectId,
    required String projectName,
    required String filename,
  }) {
    return p.posix.join(
      projectFolder(projectId: projectId, projectName: projectName),
      'materials',
      filename,
    );
  }

  static String normalLongNote({
    required DateTime dateTime,
    required String filename,
  }) {
    return p.posix.join('notes', MarkdownFilename.monthDir(dateTime), filename);
  }

  static String yamlString(String value) => jsonEncode(value);

  static String _safeFilePart(String value, {required String fallback}) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|#\r\n]+'), ' ')
        .replaceAll(RegExp(r'\s+'), '-');
    if (cleaned.isEmpty) return fallback;
    return String.fromCharCodes(cleaned.runes.take(36));
  }
}
