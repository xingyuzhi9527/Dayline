import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import 'project_markdown_service.dart';

const projectsSettingsKey = 'projects_state_v1';

final projectOptionsProvider = FutureProvider<List<ProjectOption>>((ref) async {
  ref.watch(dataVersionProvider);
  return loadProjectOptions(ref);
});

class ProjectOption {
  const ProjectOption({required this.id, required this.name});

  final String id;
  final String name;
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
  Ref ref, {
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
          ...updates.take(9),
        ],
      };
    },
  );
}

Future<void> addProjectUpdate(
  Ref ref, {
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
          ...updates.take(9),
        ],
      };
    },
  );
}

Future<void> _updateProject(
  Ref ref, {
  required String projectId,
  required DateTime updatedAt,
  ProjectArchiveEntry? archiveEntry,
  bool archiveEntryAsMajor = false,
  required Map<String, Object?> Function(Map<String, Object?> project) update,
}) async {
  final projects = await _loadProjects(ref);
  var changed = false;
  Map<String, Object?>? changedProject;
  final nextProjects = [
    for (final project in projects)
      if (project['id'] == projectId)
        () {
          changed = true;
          changedProject = update(project);
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

Future<List<Map<String, Object?>>> _loadProjects(Ref ref) async {
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
  Ref ref,
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
    'updates': _listOfMaps(raw['updates']),
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
