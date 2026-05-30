import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/database/repository_providers.dart';
import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/markdown_storage_service.dart';
import '../../core/markdown/project_markdown_paths.dart';
import '../../core/theme/app_colors.dart';
import 'project_markdown_service.dart';

const projectsSettingsKey = 'projects_state_v1';
const _projectUpdatesRetainLimit = 60;

final projectOptionsProvider = FutureProvider<List<ProjectOption>>((ref) async {
  ref.watch(dataVersionProvider);
  return loadProjectOptions(ref);
});

class ProjectOption {
  const ProjectOption({required this.id, required this.name});

  final String id;
  final String name;
}

class ProjectImageMaterial {
  const ProjectImageMaterial({
    required this.relativePath,
    required this.localPath,
    required this.mimeType,
    required this.fileName,
  });

  final String relativePath;
  final String localPath;
  final String mimeType;
  final String fileName;
}

Future<List<ProjectOption>> loadProjectOptions(Ref ref) async {
  final projects = await _loadProjects(ref);
  return [
    for (final project in projects)
      if (project['status'] != '归档')
        ProjectOption(
          id: project['id'] as String,
          name: project['name'] as String,
        ),
  ];
}

Future<ProjectOption?> findProjectOption(Ref ref, String projectId) async {
  final options = await loadProjectOptions(ref);
  for (final option in options) {
    if (option.id == projectId) return option;
  }
  return null;
}

Future<void> addProjectTodo(
  dynamic ref, {
  required String projectId,
  required String title,
  required DateTime updatedAt,
}) async {
  await _updateProject(
    ref,
    projectId: projectId,
    updatedAt: updatedAt,
    archiveEntry: ProjectArchiveEntry(
      text: '添加待办：$title',
      source: '待办',
      createdAt: updatedAt,
    ),
    update: (project) {
      final todos = _listOfMaps(project['todos']);
      final updates = _listOfMaps(project['updates']);
      final writtenAt = _formatProjectTime(updatedAt);
      return {
        ...project,
        'lastUpdate': writtenAt,
        'todos': [
          ...todos,
          {
            'id': '${updatedAt.microsecondsSinceEpoch}-todo',
            'title': title,
            'done': false,
          },
        ],
        'updates': [
          {
            'id': '${updatedAt.microsecondsSinceEpoch}-todo-update',
            'time': writtenAt,
            'createdAt': updatedAt.millisecondsSinceEpoch,
            'source': '待办',
            'text': '添加待办：$title',
            'colorValue': AppColors.todo.toARGB32(),
          },
          ...updates.take(_projectUpdatesRetainLimit - 1),
        ],
      };
    },
  );
}

Future<void> addProjectUpdate(
  dynamic ref, {
  required String projectId,
  required String text,
  required DateTime updatedAt,
}) async {
  await _updateProject(
    ref,
    projectId: projectId,
    updatedAt: updatedAt,
    archiveEntry: ProjectArchiveEntry(
      text: text,
      source: '文本记录',
      createdAt: updatedAt,
    ),
    archiveEntryAsMajor: true,
    update: (project) {
      final updates = _listOfMaps(project['updates']);
      final writtenAt = _formatProjectTime(updatedAt);
      return {
        ...project,
        'lastUpdate': writtenAt,
        'updates': [
          {
            'id': '${updatedAt.microsecondsSinceEpoch}-record-update',
            'time': writtenAt,
            'createdAt': updatedAt.millisecondsSinceEpoch,
            'source': '文本记录',
            'text': text,
            'colorValue': AppColors.primary.toARGB32(),
          },
          ...updates.take(_projectUpdatesRetainLimit - 1),
        ],
      };
    },
  );
}

Future<void> addProjectLongNote(
  dynamic ref, {
  required String projectId,
  required String title,
  required String path,
  required int recordId,
  required DateTime updatedAt,
}) async {
  await _updateProject(
    ref,
    projectId: projectId,
    updatedAt: updatedAt,
    archiveEntry: ProjectArchiveEntry(
      text: '长笔记：$title',
      source: '长笔记',
      createdAt: updatedAt,
    ),
    update: (project) {
      final updates = _listOfMaps(project['updates']);
      final writtenAt = _formatProjectTime(updatedAt);
      return {
        ...project,
        'lastUpdate': writtenAt,
        'updates': [
          {
            'id': '${updatedAt.microsecondsSinceEpoch}-long-note-update',
            'time': writtenAt,
            'createdAt': updatedAt.millisecondsSinceEpoch,
            'source': '长笔记',
            'text': title,
            'entryType': 'long_note',
            'notePath': path,
            'recordId': recordId,
            'colorValue': AppColors.primary.toARGB32(),
          },
          ...updates.take(_projectUpdatesRetainLimit - 1),
        ],
      };
    },
  );
}

Future<ProjectImageMaterial> addProjectImageMaterial(
  dynamic ref, {
  required String projectId,
  required String projectName,
  required String sourceImagePath,
  String? title,
  DateTime? createdAt,
}) async {
  final writtenAt = createdAt ?? DateTime.now();
  final sourceFile = File(sourceImagePath);
  if (!await sourceFile.exists()) {
    throw StateError('图片文件不存在：$sourceImagePath');
  }

  final settings = ref.read(appSettingsRepositoryProvider);
  final directoryService = MarkdownDirectoryService(settings);
  final storage = MarkdownStorageService(directoryService);
  final extension = p.extension(sourceImagePath).toLowerCase();
  final safeExtension = extension.isEmpty ? '.jpg' : extension;
  final fileName = _buildProjectImageFilename(
    projectName: projectName,
    writtenAt: writtenAt,
    customTitle: title,
    extension: safeExtension,
  );
  final relativePath = await _uniqueProjectImageRelativePath(
    directoryService,
    projectId: projectId,
    projectName: projectName,
    fileName: fileName,
  );
  final mimeType = _mimeTypeForPath(fileName);

  await storage.writeRelativeBinaryFile(
    relativePath: relativePath,
    sourcePath: sourceImagePath,
    mimeType: mimeType,
  );

  final localPath = await _ensureLocalProjectImageCopy(
    directoryService,
    relativePath: relativePath,
    sourceImagePath: sourceImagePath,
  );

  await _updateProject(
    ref,
    projectId: projectId,
    updatedAt: writtenAt,
    archiveEntry: ProjectArchiveEntry(
      text: '图片资料：$fileName',
      source: '图片资料',
      createdAt: writtenAt,
    ),
    update: (project) {
      final updates = _listOfMaps(project['updates']);
      final writtenTime = _formatProjectTime(writtenAt);
      return {
        ...project,
        'lastUpdate': writtenTime,
        'updates': [
          {
            'id': '${writtenAt.microsecondsSinceEpoch}-image-material',
            'time': writtenTime,
            'createdAt': writtenAt.millisecondsSinceEpoch,
            'source': '图片资料',
            'text': fileName,
            'entryType': 'image',
            'imagePath': localPath,
            'imageRelativePath': relativePath,
            'mimeType': mimeType,
            'colorValue': AppColors.secondary.toARGB32(),
          },
          ...updates.take(_projectUpdatesRetainLimit - 1),
        ],
      };
    },
  );

  return ProjectImageMaterial(
    relativePath: relativePath,
    localPath: localPath,
    mimeType: mimeType,
    fileName: fileName,
  );
}

Future<void> updateProjectLongNoteTitle(
  dynamic ref, {
  required String projectId,
  required String title,
  required String path,
  int? recordId,
  required DateTime updatedAt,
}) async {
  await _updateProject(
    ref,
    projectId: projectId,
    updatedAt: updatedAt,
    update: (project) {
      final updates = _listOfMaps(project['updates']);
      var changed = false;
      final nextUpdates = [
        for (final update in updates)
          if (_matchesLongNoteUpdate(update, path: path, recordId: recordId))
            () {
              changed = true;
              return {...update, 'text': title};
            }()
          else
            update,
      ];
      if (!changed) return project;
      return {
        ...project,
        'lastUpdate': _formatProjectTime(updatedAt),
        'updates': nextUpdates,
      };
    },
  );
}

Future<void> updateProjectImageMaterialName(
  dynamic ref, {
  required String projectId,
  required String projectName,
  required String imageRelativePath,
  required String title,
  required DateTime updatedAt,
}) async {
  final nextTitle = title.trim();
  if (nextTitle.isEmpty) return;

  final settings = ref.read(appSettingsRepositoryProvider);
  final directoryService = MarkdownDirectoryService(settings);
  final storage = MarkdownStorageService(directoryService);
  final root = await directoryService.ensureRoot();
  final existingLocalFile = File(
    _localPathForRelative(root, imageRelativePath),
  );

  await _updateProject(
    ref,
    projectId: projectId,
    updatedAt: updatedAt,
    update: (project) async {
      final updates = _listOfMaps(project['updates']);
      var changed = false;
      Map<String, Object?>? matchedUpdate;
      final nextUpdates = [
        for (final update in updates)
          if (_matchesImageMaterialUpdate(
            update,
            imageRelativePath: imageRelativePath,
          ))
            () {
              changed = true;
              matchedUpdate = update;
              return update;
            }()
          else
            update,
      ];
      if (!changed) return project;

      final update = matchedUpdate;
      final createdAtMillis = update?['createdAt'] as int?;
      final imageCreatedAt = createdAtMillis == null
          ? updatedAt
          : DateTime.fromMillisecondsSinceEpoch(createdAtMillis);
      final oldRelativePath = imageRelativePath;
      final oldLocalPath = update?['imagePath'] as String?;
      final sourceLocalFile = oldLocalPath == null || oldLocalPath.isEmpty
          ? existingLocalFile
          : File(oldLocalPath);
      final oldExtension = p.extension(oldRelativePath).toLowerCase();
      final safeExtension = oldExtension.isEmpty ? '.jpg' : oldExtension;
      final newFileName = _buildProjectImageFilename(
        projectName: projectName,
        writtenAt: imageCreatedAt,
        customTitle: nextTitle,
        extension: safeExtension,
      );
      final newRelativePath = await _uniqueProjectImageRelativePath(
        directoryService,
        projectId: projectId,
        projectName: projectName,
        fileName: newFileName,
        exceptRelativePath: oldRelativePath,
      );
      final newLocalPath = _localPathForRelative(root, newRelativePath);
      final changedPath = newRelativePath != oldRelativePath;

      if (changedPath) {
        await _renameLocalProjectImage(
          sourceLocalFile: sourceLocalFile,
          targetPath: newLocalPath,
        );
        await _renameVisibleProjectImage(
          storage,
          oldRelativePath: oldRelativePath,
          newRelativePath: newRelativePath,
          sourcePath: newLocalPath,
          mimeType: _mimeTypeForPath(newRelativePath),
        );
      }

      return {
        ...project,
        'lastUpdate': _formatProjectTime(updatedAt),
        'updates': [
          for (final update in nextUpdates)
            if (_matchesImageMaterialUpdate(
              update,
              imageRelativePath: imageRelativePath,
            ))
              {
                ...update,
                'text': p.basename(newRelativePath),
                'imagePath': newLocalPath,
                'imageRelativePath': newRelativePath,
                'mimeType': _mimeTypeForPath(newRelativePath),
              }
            else
              update,
        ],
      };
    },
  );
}

Future<void> _updateProject(
  dynamic ref, {
  required String projectId,
  required DateTime updatedAt,
  ProjectArchiveEntry? archiveEntry,
  bool archiveEntryAsMajor = false,
  required FutureOr<Map<String, Object?>> Function(Map<String, Object?> project)
  update,
}) async {
  final projects = await _loadProjects(ref);
  var changed = false;
  Map<String, Object?>? changedProject;
  final nextProjects = [
    for (final project in projects)
      if (project['id'] == projectId)
        await () async {
          changed = true;
          changedProject = await update(project);
          return changedProject!;
        }()
      else
        project,
  ];
  if (!changed) return;
  var projectsToSave = nextProjects;
  final archiveProject = changedProject;
  if (archiveProject != null) {
    try {
      final settings = ref.read(appSettingsRepositoryProvider);
      final location = await ProjectMarkdownService(settings).syncArchive(
        project: archiveProject,
        entry: archiveEntry,
        entryAsMajor: archiveEntryAsMajor,
        updatedAt: updatedAt,
      );
      if (location !=
          archiveProject[ProjectMarkdownService.archiveLocationKey]) {
        projectsToSave = [
          for (final project in nextProjects)
            if (project['id'] == projectId)
              {...project, ProjectMarkdownService.archiveLocationKey: location}
            else
              project,
        ];
      }
    } catch (_) {
      projectsToSave = nextProjects;
    }
  }
  await _saveProjects(ref, projectsToSave, updatedAt: updatedAt);
}

bool _matchesLongNoteUpdate(
  Map<String, Object?> update, {
  required String path,
  required int? recordId,
}) {
  if (update['entryType'] != 'long_note') return false;
  if (recordId != null && update['recordId'] == recordId) return true;
  return update['notePath'] == path;
}

bool _matchesImageMaterialUpdate(
  Map<String, Object?> update, {
  required String imageRelativePath,
}) {
  if (update['entryType'] != 'image') return false;
  return update['imageRelativePath'] == imageRelativePath;
}

Future<List<Map<String, Object?>>> _loadProjects(dynamic ref) async {
  final settings = ref.read(appSettingsRepositoryProvider);
  final row = await settings.findByKey(projectsSettingsKey);
  final raw = row?['value'] as String?;
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (_normalizeProject(item) != null) _normalizeProject(item)!,
    ];
  } catch (_) {
    return const [];
  }
}

Future<void> _saveProjects(
  dynamic ref,
  List<Map<String, Object?>> projects, {
  required DateTime updatedAt,
}) async {
  final settings = ref.read(appSettingsRepositoryProvider);
  final value = jsonEncode(projects);
  final existing = await settings.findByKey(projectsSettingsKey);
  if (existing == null) {
    await settings.create(
      key: projectsSettingsKey,
      value: value,
      updatedAt: updatedAt,
    );
  } else {
    await settings.update(projectsSettingsKey, value, updatedAt: updatedAt);
  }
  ref.read(dataVersionProvider.notifier).increment();
}

Map<String, Object?>? _normalizeProject(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'] as String?;
  final name = raw['name'] as String?;
  if (id == null || name == null || name.trim().isEmpty) return null;
  return {
    'id': id,
    'name': name,
    'status': raw['status'] as String? ?? '进行中',
    'goal': raw['goal'] as String? ?? '慢慢推进这件事',
    'lastUpdate': raw['lastUpdate'] as String? ?? '刚刚',
    if (raw['archiveLocation'] is String)
      'archiveLocation': raw['archiveLocation'] as String,
    'todos': _listOfMaps(raw['todos']),
    'updates': _listOfMaps(
      raw['updates'],
    ).take(_projectUpdatesRetainLimit).toList(),
  };
}

List<Map<String, Object?>> _listOfMaps(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) item.cast<String, Object?>(),
  ];
}

String _formatProjectTime(DateTime time) {
  final now = DateTime.now();
  final sameDay =
      time.year == now.year && time.month == now.month && time.day == now.day;
  if (sameDay) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '今天 $hour:$minute';
  }
  return '${time.month}月${time.day}日';
}

Future<String> _ensureLocalProjectImageCopy(
  MarkdownDirectoryService directoryService, {
  required String relativePath,
  required String sourceImagePath,
}) async {
  final root = await directoryService.ensureRoot();
  final target = File(_localPathForRelative(root, relativePath));
  if (await target.exists()) return target.path;

  await target.parent.create(recursive: true);
  await File(sourceImagePath).copy(target.path);
  return target.path;
}

Future<String> _uniqueProjectImageRelativePath(
  MarkdownDirectoryService directoryService, {
  required String projectId,
  required String projectName,
  required String fileName,
  String? exceptRelativePath,
}) async {
  final root = await directoryService.ensureRoot();
  final parsed = p.posix.extension(fileName);
  final base = parsed.isEmpty
      ? fileName
      : fileName.substring(0, fileName.length - parsed.length);
  for (var index = 1; index < 100; index++) {
    final candidateFileName = index == 1 ? fileName : '$base-$index$parsed';
    final relativePath = ProjectMarkdownPaths.projectImageMaterial(
      projectId: projectId,
      projectName: projectName,
      filename: candidateFileName,
    );
    if (relativePath == exceptRelativePath) return relativePath;
    if (!await File(_localPathForRelative(root, relativePath)).exists()) {
      return relativePath;
    }
  }
  final fallbackFileName =
      '$base-${DateTime.now().millisecondsSinceEpoch}$parsed';
  return ProjectMarkdownPaths.projectImageMaterial(
    projectId: projectId,
    projectName: projectName,
    filename: fallbackFileName,
  );
}

Future<void> _renameLocalProjectImage({
  required File sourceLocalFile,
  required String targetPath,
}) async {
  if (!await sourceLocalFile.exists()) {
    throw StateError('图片文件不存在：${sourceLocalFile.path}');
  }
  final target = File(targetPath);
  await target.parent.create(recursive: true);
  if (p.normalize(sourceLocalFile.path) == p.normalize(target.path)) return;
  if (await target.exists()) {
    throw StateError('目标图片文件已存在：${target.path}');
  }
  await sourceLocalFile.rename(target.path);
}

Future<void> _renameVisibleProjectImage(
  MarkdownStorageService storage, {
  required String oldRelativePath,
  required String newRelativePath,
  required String sourcePath,
  required String mimeType,
}) async {
  try {
    await storage.writeRelativeBinaryFile(
      relativePath: newRelativePath,
      sourcePath: sourcePath,
      mimeType: mimeType,
    );
    await storage.deleteTreeDocument(relativePath: oldRelativePath);
  } catch (_) {
    // Local roots were already renamed above. Document-tree renames are best-effort
    // because the user may have changed or revoked the folder grant.
  }
}

String _localPathForRelative(String root, String relativePath) {
  return p.joinAll([root, ...p.posix.split(relativePath)]);
}

String _buildProjectImageFilename({
  required String projectName,
  required DateTime writtenAt,
  required String? customTitle,
  required String extension,
}) {
  final project = _safeFilenamePart(projectName, fallback: '项目');
  final date = '${writtenAt.month}.${writtenAt.day}';
  final custom = _safeFilenamePart(customTitle ?? '', fallback: '图片资料');
  return '$project-$date-$custom$extension';
}

String _mimeTypeForPath(String path) {
  final extension = p.extension(path).toLowerCase();
  return switch (extension) {
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    '.heic' || '.heif' => 'image/heic',
    _ => 'image/jpeg',
  };
}

String _safeFilenamePart(String value, {required String fallback}) {
  final cleaned = value
      .trim()
      .replaceFirst(RegExp(r'\.[A-Za-z0-9]{2,5}$'), '')
      .replaceAll(RegExp(r'[\\/:*?"<>|#\r\n]+'), ' ')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .trim();
  if (cleaned.isEmpty) return fallback;
  return String.fromCharCodes(cleaned.runes.take(36));
}
