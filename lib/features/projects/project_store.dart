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
    this.relativePaths = const [],
    this.localPaths = const [],
    this.mimeTypes = const [],
    this.fileNames = const [],
  });

  final String relativePath;
  final String localPath;
  final String mimeType;
  final String fileName;
  final List<String> relativePaths;
  final List<String> localPaths;
  final List<String> mimeTypes;
  final List<String> fileNames;

  List<String> get allRelativePaths =>
      relativePaths.isEmpty ? [relativePath] : relativePaths;
  List<String> get allLocalPaths =>
      localPaths.isEmpty ? [localPath] : localPaths;
  List<String> get allMimeTypes => mimeTypes.isEmpty ? [mimeType] : mimeTypes;
  List<String> get allFileNames => fileNames.isEmpty ? [fileName] : fileNames;
}

class ProjectFileMaterial {
  const ProjectFileMaterial({
    required this.relativePath,
    required this.fileName,
    required this.mimeType,
    this.localPath,
  });

  final String relativePath;
  final String fileName;
  final String mimeType;
  final String? localPath;
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
  String? relativePath,
  String? fileName,
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
            if (relativePath != null && relativePath.trim().isNotEmpty)
              'noteRelativePath': relativePath,
            if (fileName != null && fileName.trim().isNotEmpty)
              'noteFileName': fileName,
            'recordId': recordId,
            'colorValue': AppColors.primary.toARGB32(),
          },
          ...updates.take(_projectUpdatesRetainLimit - 1),
        ],
      };
    },
  );
}

Future<ProjectFileMaterial> addProjectFileMaterial(
  dynamic ref, {
  required String projectId,
  required String projectName,
  required String sourceFilePath,
  DateTime? createdAt,
}) async {
  final writtenAt = createdAt ?? DateTime.now();
  final sourceFile = File(sourceFilePath);
  if (!await sourceFile.exists()) {
    throw StateError('文件不存在：$sourceFilePath');
  }

  final settings = ref.read(appSettingsRepositoryProvider);
  final directoryService = MarkdownDirectoryService(settings);
  final storage = MarkdownStorageService(directoryService);
  await _ensureProjectMaterialsNoMedia(
    directoryService,
    storage,
    projectId: projectId,
    projectName: projectName,
  );

  final fileName = await _uniqueProjectMaterialFileName(
    directoryService,
    projectId: projectId,
    projectName: projectName,
    fileName: p.basename(sourceFilePath),
  );
  final relativePath = _projectFileMaterialRelativePath(
    projectId: projectId,
    projectName: projectName,
    filename: fileName,
  );
  final mimeType = _mimeTypeForPath(fileName);

  await storage.writeRelativeBinaryFile(
    relativePath: relativePath,
    sourcePath: sourceFilePath,
    mimeType: mimeType,
  );

  final root = await directoryService.ensureRoot();
  final localPath = _localPathForRelative(root, relativePath);
  if (!await File(localPath).exists()) {
    await File(localPath).parent.create(recursive: true);
    await sourceFile.copy(localPath);
  }

  await _recordProjectFileMaterial(
    ref,
    projectId: projectId,
    relativePath: relativePath,
    localPath: localPath,
    fileName: fileName,
    mimeType: mimeType,
    writtenAt: writtenAt,
  );

  return ProjectFileMaterial(
    relativePath: relativePath,
    localPath: localPath,
    fileName: fileName,
    mimeType: mimeType,
  );
}

Future<ProjectFileMaterial?> importProjectFileMaterial(
  dynamic ref, {
  required String projectId,
  required String projectName,
  DateTime? createdAt,
}) async {
  final writtenAt = createdAt ?? DateTime.now();
  final settings = ref.read(appSettingsRepositoryProvider);
  final directoryService = MarkdownDirectoryService(settings);
  final storage = MarkdownStorageService(directoryService);
  await _ensureProjectMaterialsNoMedia(
    directoryService,
    storage,
    projectId: projectId,
    projectName: projectName,
  );
  final materialDir = ProjectMarkdownPaths.projectMaterialDirectory(
    projectId: projectId,
    projectName: projectName,
  );
  final notesDir = ProjectMarkdownPaths.projectNotesDirectory(
    projectId: projectId,
    projectName: projectName,
  );
  final row = await storage.importDocumentToRelativePath(
    materialDir,
    markdownDirectory: notesDir,
  );
  if (row == null) return null;

  final relativePath = row['relativePath'] as String?;
  final fileName = row['name'] as String?;
  if (relativePath == null ||
      relativePath.trim().isEmpty ||
      fileName == null ||
      fileName.trim().isEmpty) {
    return null;
  }
  final mimeType = row['mimeType'] as String? ?? _mimeTypeForPath(relativePath);

  await _recordProjectFileMaterial(
    ref,
    projectId: projectId,
    relativePath: relativePath,
    fileName: fileName,
    mimeType: mimeType,
    writtenAt: writtenAt,
  );

  return ProjectFileMaterial(
    relativePath: relativePath,
    fileName: fileName,
    mimeType: mimeType,
  );
}

Future<void> _recordProjectFileMaterial(
  dynamic ref, {
  required String projectId,
  required String relativePath,
  String? localPath,
  required String fileName,
  required String mimeType,
  required DateTime writtenAt,
}) async {
  await _updateProject(
    ref,
    projectId: projectId,
    updatedAt: writtenAt,
    archiveEntry: ProjectArchiveEntry(
      text: '文件：$fileName',
      source: '文件',
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
            'id': '${writtenAt.microsecondsSinceEpoch}-file-material',
            'time': writtenTime,
            'createdAt': writtenAt.millisecondsSinceEpoch,
            'source': '文件',
            'text': fileName,
            'entryType': 'file',
            'fileRelativePath': relativePath,
            if (localPath != null && localPath.trim().isNotEmpty)
              'filePath': localPath,
            'mimeType': mimeType,
            'colorValue': AppColors.secondary.toARGB32(),
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
  await _ensureProjectMaterialsNoMedia(
    directoryService,
    storage,
    projectId: projectId,
    projectName: projectName,
  );
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

Future<ProjectImageMaterial> addProjectImageMaterials(
  dynamic ref, {
  required String projectId,
  required String projectName,
  required List<String> sourceImagePaths,
  String? title,
  DateTime? createdAt,
}) async {
  if (sourceImagePaths.isEmpty) {
    throw StateError('No project images selected.');
  }
  if (sourceImagePaths.length == 1) {
    return addProjectImageMaterial(
      ref,
      projectId: projectId,
      projectName: projectName,
      sourceImagePath: sourceImagePaths.single,
      title: title,
      createdAt: createdAt,
    );
  }

  final writtenAt = createdAt ?? DateTime.now();
  for (final sourceImagePath in sourceImagePaths) {
    final sourceFile = File(sourceImagePath);
    if (!await sourceFile.exists()) {
      throw StateError('Project image file not found: $sourceImagePath');
    }
  }

  final settings = ref.read(appSettingsRepositoryProvider);
  final directoryService = MarkdownDirectoryService(settings);
  final storage = MarkdownStorageService(directoryService);
  final folderName = await _uniqueProjectImageFolderName(
    directoryService,
    projectId: projectId,
    projectName: projectName,
    folderName: _buildProjectImageFolderName(
      projectName: projectName,
      writtenAt: writtenAt,
      customTitle: title,
    ),
  );
  await _ensureProjectMaterialsNoMedia(
    directoryService,
    storage,
    projectId: projectId,
    projectName: projectName,
    folderName: folderName,
  );

  final usedNames = <String>{};
  final relativePaths = <String>[];
  final localPaths = <String>[];
  final mimeTypes = <String>[];
  final fileNames = <String>[];

  for (final sourceImagePath in sourceImagePaths) {
    final fileName = _uniqueBasename(p.basename(sourceImagePath), usedNames);
    final relativePath = ProjectMarkdownPaths.projectImageMaterial(
      projectId: projectId,
      projectName: projectName,
      folderName: folderName,
      filename: fileName,
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
    relativePaths.add(relativePath);
    localPaths.add(localPath);
    mimeTypes.add(mimeType);
    fileNames.add(fileName);
  }

  final displayName = '$folderName（${fileNames.length}张）';
  await _updateProject(
    ref,
    projectId: projectId,
    updatedAt: writtenAt,
    archiveEntry: ProjectArchiveEntry(
      text: '图片资料：$displayName',
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
            'text': displayName,
            'entryType': 'image',
            'imagePath': localPaths.first,
            'imageRelativePath': relativePaths.first,
            'mimeType': mimeTypes.first,
            'imagePaths': localPaths,
            'imageRelativePaths': relativePaths,
            'mimeTypes': mimeTypes,
            'colorValue': AppColors.secondary.toARGB32(),
          },
          ...updates.take(_projectUpdatesRetainLimit - 1),
        ],
      };
    },
  );

  return ProjectImageMaterial(
    relativePath: relativePaths.first,
    localPath: localPaths.first,
    mimeType: mimeTypes.first,
    fileName: fileNames.first,
    relativePaths: relativePaths,
    localPaths: localPaths,
    mimeTypes: mimeTypes,
    fileNames: fileNames,
  );
}

Future<void> deleteProjectImageMaterial(
  dynamic ref, {
  required String projectId,
  required String imageRelativePath,
  required DateTime updatedAt,
}) async {
  final settings = ref.read(appSettingsRepositoryProvider);
  final directoryService = MarkdownDirectoryService(settings);
  final storage = MarkdownStorageService(directoryService);
  final root = await directoryService.ensureRoot();

  Map<String, Object?>? removedUpdate;
  await _updateProject(
    ref,
    projectId: projectId,
    updatedAt: updatedAt,
    update: (project) {
      final updates = _listOfMaps(project['updates']);
      final nextUpdates = <Map<String, Object?>>[];
      for (final update in updates) {
        if (_matchesImageMaterialUpdate(
          update,
          imageRelativePath: imageRelativePath,
        )) {
          removedUpdate = update;
        } else {
          nextUpdates.add(update);
        }
      }
      if (removedUpdate == null) return project;
      return {
        ...project,
        'lastUpdate': _formatProjectTime(updatedAt),
        'updates': nextUpdates,
      };
    },
  );

  final update = removedUpdate;
  if (update == null) return;

  for (final relativePath in _imageRelativePathsForUpdate(update)) {
    await _deleteLocalProjectFile(root, relativePath);
    await _deleteTreeProjectFile(storage, relativePath);
  }
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
                'imagePaths': _replaceStringList(
                  update['imagePaths'],
                  oldLocalPath ?? sourceLocalFile.path,
                  newLocalPath,
                ),
                'imageRelativePaths': _replaceStringList(
                  update['imageRelativePaths'],
                  oldRelativePath,
                  newRelativePath,
                ),
                'mimeTypes': _replaceStringList(
                  update['mimeTypes'],
                  _mimeTypeForPath(oldRelativePath),
                  _mimeTypeForPath(newRelativePath),
                  replaceFirstOnly: true,
                ),
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
  final relativePaths = update['imageRelativePaths'];
  if (relativePaths is List && relativePaths.contains(imageRelativePath)) {
    return true;
  }
  return update['imageRelativePath'] == imageRelativePath;
}

List<String> _imageRelativePathsForUpdate(Map<String, Object?> update) {
  final relativePaths = update['imageRelativePaths'];
  if (relativePaths is List) {
    final paths = [
      for (final path in relativePaths)
        if (path is String && path.isNotEmpty) path,
    ];
    if (paths.isNotEmpty) return paths;
  }
  final single = update['imageRelativePath'];
  return single is String && single.isNotEmpty ? [single] : const [];
}

Future<void> _deleteLocalProjectFile(String root, String relativePath) async {
  try {
    final file = File(_localPathForRelative(root, relativePath));
    if (await file.exists()) {
      await file.delete();
    }
    await _deleteEmptyParentDir(file.parent);
  } catch (_) {}
}

Future<void> _deleteTreeProjectFile(
  MarkdownStorageService storage,
  String relativePath,
) async {
  try {
    await storage.deleteTreeDocument(relativePath: relativePath);
  } catch (_) {}
}

Future<void> _deleteEmptyParentDir(Directory dir) async {
  try {
    if (!await dir.exists()) return;
    final entries = await dir.list().toList();
    final visibleEntries = entries.where(
      (entry) => p.basename(entry.path) != '.nomedia',
    );
    if (visibleEntries.isNotEmpty) return;
    for (final entry in entries) {
      if (entry is File) {
        await entry.delete();
      }
    }
    await dir.delete();
  } catch (_) {}
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

Future<void> _ensureProjectMaterialsNoMedia(
  MarkdownDirectoryService directoryService,
  MarkdownStorageService storage, {
  required String projectId,
  required String projectName,
  String? folderName,
}) async {
  final base = ProjectMarkdownPaths.projectFolder(
    projectId: projectId,
    projectName: projectName,
  );
  final relativePath = p.posix.joinAll([
    base,
    'materials',
    if (folderName != null && folderName.trim().isNotEmpty) folderName,
    '.nomedia',
  ]);
  try {
    await storage.writeRelativeTextFile(
      relativePath: relativePath,
      content: '',
    );
  } catch (_) {}

  try {
    final root = await directoryService.ensureRoot();
    final file = File(_localPathForRelative(root, relativePath));
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      await file.writeAsString('');
    }
  } catch (_) {}
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

Future<String> _uniqueProjectMaterialFileName(
  MarkdownDirectoryService directoryService, {
  required String projectId,
  required String projectName,
  required String fileName,
}) async {
  final root = await directoryService.ensureRoot();
  final fallback = _safeMaterialFilename(fileName);
  final extension = p.extension(fallback);
  final base = extension.isEmpty
      ? fallback
      : fallback.substring(0, fallback.length - extension.length);
  for (var index = 1; index < 100; index++) {
    final candidate = index == 1 ? fallback : '$base-$index$extension';
    final relativePath = _projectFileMaterialRelativePath(
      projectId: projectId,
      projectName: projectName,
      filename: candidate,
    );
    if (!await File(_localPathForRelative(root, relativePath)).exists()) {
      return candidate;
    }
  }
  return '$base-${DateTime.now().millisecondsSinceEpoch}$extension';
}

String _projectFileMaterialRelativePath({
  required String projectId,
  required String projectName,
  required String filename,
}) {
  if (_isMarkdownFileName(filename)) {
    return p.posix.join(
      ProjectMarkdownPaths.projectNotesDirectory(
        projectId: projectId,
        projectName: projectName,
      ),
      filename,
    );
  }
  return ProjectMarkdownPaths.projectMaterial(
    projectId: projectId,
    projectName: projectName,
    filename: filename,
  );
}

Future<String> _uniqueProjectImageFolderName(
  MarkdownDirectoryService directoryService, {
  required String projectId,
  required String projectName,
  required String folderName,
}) async {
  final root = await directoryService.ensureRoot();
  final base = _safeFilenamePart(folderName, fallback: '图片资料');
  for (var index = 1; index < 100; index++) {
    final candidate = index == 1 ? base : '$base-$index';
    final probePath = ProjectMarkdownPaths.projectImageMaterial(
      projectId: projectId,
      projectName: projectName,
      folderName: candidate,
      filename: '.probe',
    );
    final dir = Directory(p.dirname(_localPathForRelative(root, probePath)));
    if (!await dir.exists()) return candidate;
  }
  return '$base-${DateTime.now().millisecondsSinceEpoch}';
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

String _buildProjectImageFolderName({
  required String projectName,
  required DateTime writtenAt,
  required String? customTitle,
}) {
  final project = _safeFilenamePart(projectName, fallback: '项目');
  final date = '${writtenAt.month}.${writtenAt.day}';
  final custom = _safeFilenamePart(customTitle ?? '', fallback: '图片资料');
  return '$project-$date-$custom';
}

String _uniqueBasename(String basename, Set<String> usedNames) {
  final fallback = basename.trim().isEmpty ? 'image.jpg' : basename.trim();
  final extension = p.extension(fallback);
  final base = extension.isEmpty
      ? fallback
      : fallback.substring(0, fallback.length - extension.length);
  for (var index = 1; index < 100; index++) {
    final candidate = index == 1 ? fallback : '$base-$index$extension';
    if (usedNames.add(candidate)) return candidate;
  }
  final candidate = '$base-${DateTime.now().millisecondsSinceEpoch}$extension';
  usedNames.add(candidate);
  return candidate;
}

List<String> _replaceStringList(
  Object? raw,
  String oldValue,
  String newValue, {
  bool replaceFirstOnly = false,
}) {
  if (raw is! List) return const [];
  var replaced = false;
  return [
    for (final item in raw)
      if (item is String)
        if (item == oldValue && (!replaceFirstOnly || !replaced))
          () {
            replaced = true;
            return newValue;
          }()
        else
          item,
  ];
}

String _mimeTypeForPath(String path) {
  final extension = p.extension(path).toLowerCase();
  return switch (extension) {
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    '.heic' || '.heif' => 'image/heic',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.gif' => 'image/gif',
    '.pdf' => 'application/pdf',
    '.md' || '.markdown' => 'text/markdown',
    '.txt' => 'text/plain',
    '.csv' => 'text/csv',
    '.json' => 'application/json',
    '.doc' => 'application/msword',
    '.docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.xls' => 'application/vnd.ms-excel',
    '.xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.ppt' => 'application/vnd.ms-powerpoint',
    '.pptx' =>
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    '.zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}

bool _isMarkdownFileName(String fileName) {
  final extension = p.extension(fileName).toLowerCase();
  return extension == '.md' || extension == '.markdown';
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

String _safeMaterialFilename(String value) {
  final cleaned = value
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|#\r\n]+'), ' ')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .trim();
  if (cleaned.isEmpty) return 'file';
  return String.fromCharCodes(cleaned.runes.take(80));
}
