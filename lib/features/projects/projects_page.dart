import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/database/repository_providers.dart';
import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/markdown_document_parser.dart';
import '../../core/markdown/markdown_storage_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../long_note/long_note_reader_page.dart';
import 'project_image_viewer_page.dart';
import 'project_markdown_service.dart';
import 'project_ordering.dart';
import 'project_store.dart';

class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  final _imagePicker = ImagePicker();
  var _projects = <_ProjectInfo>[];
  var _projectRecordHeatEntries = <_ProjectHeatEntry>[];
  String? _selectedProjectId;
  var _completedExpanded = false;
  var _loading = true;
  var _saving = false;
  var _addingProjectImage = false;
  var _addingProjectFile = false;

  _ProjectInfo? get _selectedProject {
    final selectedId = _selectedProjectId;
    if (selectedId != null) {
      final selected = _projectById(selectedId);
      if (selected != null) return selected;
    }
    return _firstProject(_activeProjects) ??
        (_completedExpanded ? _firstProject(_completedProjects) : null);
  }

  List<_ProjectInfo> get _activeProjects =>
      _projects.where((project) => project.isActiveForDaily).toList();

  List<_ProjectInfo> get _completedProjects =>
      _projects.where((project) => project.isCompleted).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProjects());
  }

  Future<void> _loadProjects() async {
    final settings = ref.read(appSettingsRepositoryProvider);
    final row = await settings.findByKey(projectsSettingsKey);
    final projects = _decodeProjects(row?['value'] as String?);
    final projectRecordHeatEntries = await _loadProjectRecordHeatEntries(
      projects,
    );
    if (!mounted) return;

    setState(() {
      _projects = projects;
      _projectRecordHeatEntries = projectRecordHeatEntries;
      _selectedProjectId =
          _projectById(_selectedProjectId ?? '')?.id ??
          _firstProject(_activeProjects)?.id;
      _loading = false;
    });
  }

  Future<void> _saveProjects(List<_ProjectInfo> projects) async {
    setState(() => _saving = true);
    try {
      final settings = ref.read(appSettingsRepositoryProvider);
      final value = jsonEncode(
        projects.map((project) => project.toJson()).toList(),
      );
      final existing = await settings.findByKey(projectsSettingsKey);
      if (existing == null) {
        await settings.create(key: projectsSettingsKey, value: value);
      } else {
        await settings.update(projectsSettingsKey, value);
      }
      ref.read(dataVersionProvider.notifier).increment();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _openAllProjects() async {
    final selectedId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _AllProjectsPage(
          projects: _projects,
          selectedId: _selectedProject?.id,
        ),
      ),
    );
    if (selectedId == null || !mounted) return;

    final nextIndex = _projects.indexWhere(
      (project) => project.id == selectedId,
    );
    if (nextIndex >= 0) {
      setState(() {
        _selectedProjectId = _projects[nextIndex].id;
        if (_projects[nextIndex].isCompleted) _completedExpanded = true;
      });
    }
  }

  void _reorderProjects(List<String> orderedProjectIds) {
    final nextProjects = reorderProjectSubset(
      projects: _projects,
      orderedIds: orderedProjectIds,
      idOf: (project) => project.id,
    );
    if (identical(nextProjects, _projects)) return;

    setState(() => _projects = nextProjects);
    unawaited(_saveProjects(nextProjects));
  }

  Future<void> _openAddProject() async {
    final draft = await Navigator.of(context).push<_ProjectDraft>(
      MaterialPageRoute(builder: (_) => const _AddProjectPage()),
    );
    if (draft == null || !mounted) return;

    final now = DateTime.now();
    final project = _ProjectInfo(
      id: now.microsecondsSinceEpoch.toString(),
      name: draft.name,
      status: draft.status,
      goal: draft.goal,
      lastUpdate: _formatUpdateTime(now),
      todos: [
        if (draft.firstTodo.isNotEmpty)
          _ProjectTodo(
            id: '${now.microsecondsSinceEpoch}-todo',
            title: draft.firstTodo,
          ),
      ],
      updates: [
        _ProjectUpdate(
          id: '${now.microsecondsSinceEpoch}-update',
          time: _formatUpdateTime(now),
          createdAt: now.millisecondsSinceEpoch,
          source: '项目',
          text: '创建项目：${draft.name}',
          colorValue: AppColors.primary.toARGB32(),
        ),
      ],
    );
    final nextProjects = [..._projects, project];
    setState(() {
      _projects = nextProjects;
      _selectedProjectId = project.id;
    });
    await _saveProjects(nextProjects);
    await _syncProjectArchive(
      project,
      entry: ProjectArchiveEntry(
        text: '创建项目：${draft.name}',
        source: '项目',
        createdAt: now,
      ),
      entryAsMajor: true,
    );
  }

  Future<void> _openEditProject(_ProjectInfo project) async {
    final draft = await showModalBottomSheet<_ProjectEditDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditProjectSheet(project: project),
    );
    if (draft == null || !mounted) return;

    final name = draft.name.trim();
    final status = draft.archiveRequested ? '归档' : draft.status.trim();
    if (name.isEmpty || (name == project.name && status == project.status)) {
      return;
    }

    final now = DateTime.now();
    final updatedProject = project.updateBasics(
      name: name,
      status: status,
      updatedAt: now,
    );
    final nextProjects = [
      for (final item in _projects)
        if (item.id == project.id) updatedProject else item,
    ];
    setState(() {
      _projects = nextProjects;
      if (status == '归档' || status == '完成') {
        _completedExpanded = false;
        _selectedProjectId = _firstProject(_activeProjects)?.id;
      } else {
        _selectedProjectId = updatedProject.id;
      }
      _projectRecordHeatEntries = _projectRecordHeatEntries
          .map(
            (entry) => entry.projectName == project.name
                ? entry.copyWith(projectName: name)
                : entry,
          )
          .toList();
    });
    await _saveProjects(nextProjects);
    await _syncProjectArchive(
      updatedProject,
      entry: ProjectArchiveEntry(
        text: _projectStatusChangeText(project, name, status),
        source: '项目',
        createdAt: now,
      ),
    );
  }

  Future<void> _toggleTodo(String todoId) async {
    final project = _selectedProject;
    if (project == null) return;
    final todo = project.todoById(todoId);
    if (todo == null) return;

    final now = DateTime.now();
    final willComplete = !todo.done;
    final nextProjects = [
      for (final item in _projects)
        if (item.id == project.id)
          item.toggleTodo(todoId, updatedAt: now)
        else
          item,
    ];
    setState(() => _projects = nextProjects);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    await _createProjectTimelineRecord(
      project: project,
      content: '${willComplete ? '完成待办' : '恢复待办'}：${todo.title}',
      entryType: 'todo',
      createdAt: now,
    );
    await _saveProjects(nextProjects);
    await _syncProjectArchive(
      _projectById(project.id) ?? project,
      entry: ProjectArchiveEntry(
        text: '${willComplete ? '完成待办' : '恢复待办'}：${todo.title}',
        source: '待办',
        createdAt: now,
      ),
    );
  }

  Future<void> _openAddTodo() async {
    final project = _selectedProject;
    if (project == null) return;

    final title = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProjectTextEntrySheet(
        title: '添加待办',
        subtitle: project.name,
        hintText: '例如：修复登录页 bug',
        submitLabel: '保存待办',
        emptyErrorText: '写一个具体的下一步。',
      ),
    );
    if (title == null || title.trim().isEmpty || !mounted) return;

    final now = DateTime.now();
    final nextProjects = [
      for (final item in _projects)
        if (item.id == project.id)
          item.addTodo(title.trim(), createdAt: now)
        else
          item,
    ];
    setState(() => _projects = nextProjects);
    await _createProjectTimelineRecord(
      project: project,
      content: '添加待办：${title.trim()}',
      entryType: 'todo',
      createdAt: now,
    );
    await _saveProjects(nextProjects);
    await _syncProjectArchive(
      _projectById(project.id) ?? project,
      entry: ProjectArchiveEntry(
        text: '添加待办：${title.trim()}',
        source: '待办',
        createdAt: now,
      ),
    );
  }

  Future<void> _openEditTodo(String todoId) async {
    final project = _selectedProject;
    final todo = project?.todoById(todoId);
    if (project == null || todo == null) return;

    final title = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProjectTextEntrySheet(
        title: '修改待办',
        subtitle: project.name,
        hintText: '例如：修复登录页 bug',
        submitLabel: '保存修改',
        initialText: todo.title,
        emptyErrorText: '待办内容不能为空。',
      ),
    );
    if (title == null || title.trim().isEmpty || !mounted) return;

    final now = DateTime.now();
    final nextProjects = [
      for (final item in _projects)
        if (item.id == project.id)
          item.renameTodo(todoId, title.trim(), updatedAt: now)
        else
          item,
    ];
    setState(() => _projects = nextProjects);
    await _createProjectTimelineRecord(
      project: project,
      content: '修改待办：${title.trim()}',
      entryType: 'todo',
      createdAt: now,
    );
    await _saveProjects(nextProjects);
    await _syncProjectArchive(
      _projectById(project.id) ?? project,
      entry: ProjectArchiveEntry(
        text: '修改待办：${title.trim()}',
        source: '待办',
        createdAt: now,
      ),
    );
  }

  Future<void> _openAddUpdate() async {
    final project = _selectedProject;
    if (project == null) return;

    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProjectTextEntrySheet(
        title: '添加最近更新',
        subtitle: project.name,
        hintText: '记录这个项目刚推进了什么',
        submitLabel: '保存更新',
        emptyErrorText: '写一点推进内容。',
        maxLines: 3,
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;

    final now = DateTime.now();
    final nextProjects = [
      for (final item in _projects)
        if (item.id == project.id)
          item.addUpdate(text.trim(), createdAt: now)
        else
          item,
    ];
    setState(() => _projects = nextProjects);
    await _createProjectTimelineRecord(
      project: project,
      content: text.trim(),
      entryType: 'update',
      createdAt: now,
    );
    await _saveProjects(nextProjects);
    await _syncProjectArchive(
      _projectById(project.id) ?? project,
      entry: ProjectArchiveEntry(
        text: text.trim(),
        source: '最近更新',
        createdAt: now,
      ),
      entryAsMajor: true,
    );
  }

  Future<void> _openAddProjectImageMaterial() async {
    final project = _selectedProject;
    if (project == null || _addingProjectImage) return;

    setState(() => _addingProjectImage = true);
    try {
      final images = await _imagePicker.pickMultiImage(imageQuality: 94);
      if (!mounted || images.isEmpty) return;

      final createdAt = DateTime.now();
      final firstImagePath = images.first.path;
      final imageTitle = await showDialog<String>(
        context: context,
        builder: (_) => _ProjectImageNameDialog(
          title: '保存图片资料',
          projectName: project.name,
          extension: p.extension(firstImagePath).isEmpty
              ? '.jpg'
              : p.extension(firstImagePath).toLowerCase(),
          createdAt: createdAt,
        ),
      );
      if (!mounted || imageTitle == null || imageTitle.trim().isEmpty) return;

      await addProjectImageMaterials(
        ref,
        projectId: project.id,
        projectName: project.name,
        sourceImagePaths: images.map((image) => image.path).toList(),
        title: imageTitle,
        createdAt: createdAt,
      );
      if (!mounted) return;
      await _loadProjects();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('图片资料已归到项目'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('添加图片资料失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _addingProjectImage = false);
    }
  }

  Future<void> _openAddProjectFileMaterial() async {
    final project = _selectedProject;
    if (project == null || _addingProjectFile) return;

    setState(() => _addingProjectFile = true);
    try {
      final material = await importProjectFileMaterial(
        ref,
        projectId: project.id,
        projectName: project.name,
        createdAt: DateTime.now(),
      );
      if (!mounted) return;
      if (material == null) {
        _showProjectSnack(Platform.isAndroid ? '没有选择文件' : '当前平台暂不支持从这里选择文件');
        return;
      }
      await _loadProjects();
      if (!mounted) return;
      _showProjectSnack('文件已归到项目');
    } catch (e) {
      if (!mounted) return;
      _showProjectSnack('添加文件失败：$e');
    } finally {
      if (mounted) setState(() => _addingProjectFile = false);
    }
  }

  Future<void> _saveArchiveSnapshot() async {
    final project = _selectedProject;
    if (project == null) return;
    await _syncProjectArchive(project, showConfirmation: true);
  }

  Future<void> _openProjectLongNote(_ProjectUpdate update) async {
    final path = update.notePath;
    if (path == null || path.isEmpty) return;
    try {
      final settings = ref.read(appSettingsRepositoryProvider);
      final storage = MarkdownStorageService(
        MarkdownDirectoryService(settings),
      );
      final raw = await storage.readTextFileLocation(path);
      final document = parseMarkdownDocument(raw, fallbackTitle: update.text);
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => LongNoteReaderPage(
            title: document.title,
            filePath: path,
            body: document.body,
            recordId: update.recordId,
            projectId: _selectedProject?.id,
          ),
        ),
      );
      if (saved == true && mounted) {
        await _loadProjects();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('打开长笔记失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _openProjectUpdate(_ProjectUpdate update) async {
    if (update.isLongNote) {
      await _openProjectLongNote(update);
      return;
    }
    if (update.isImageMaterial) {
      await _openProjectImage(update);
      return;
    }
    if (update.isFileMaterial) {
      await _openProjectFile(update);
    }
  }

  Future<void> _openProjectFile(_ProjectUpdate update) async {
    final relativePath = update.fileRelativePath;
    if (relativePath == null || relativePath.isEmpty) {
      _showProjectSnack('这个文件缺少项目路径');
      return;
    }

    try {
      final settings = ref.read(appSettingsRepositoryProvider);
      final directoryService = MarkdownDirectoryService(settings);
      final treeUri = await directoryService.getTreeRootUri();
      if (Platform.isAndroid && treeUri != null && treeUri.isNotEmpty) {
        final storage = MarkdownStorageService(directoryService);
        await storage.openTreeDocument(
          relativePath: relativePath,
          mimeType: update.mimeType ?? 'application/octet-stream',
        );
        return;
      }

      final explicitPath = update.filePath;
      final root = await directoryService.ensureRoot();
      final fallbackPath = p.joinAll([root, ...p.posix.split(relativePath)]);
      final file = File(
        explicitPath != null && explicitPath.isNotEmpty
            ? explicitPath
            : fallbackPath,
      );
      if (!await file.exists()) {
        throw StateError('文件不存在：$relativePath');
      }
      await _openLocalFile(file.path);
    } catch (e) {
      _showProjectSnack('打开文件失败：$e');
    }
  }

  Future<void> _openProjectImage(_ProjectUpdate update) async {
    final items = <ProjectImageViewerItem>[];
    final localPaths = update.allImagePaths;
    final relativePaths = update.allImageRelativePaths;
    final itemCount = localPaths.length > relativePaths.length
        ? localPaths.length
        : relativePaths.length;

    for (var i = 0; i < itemCount; i++) {
      final localPath = i < localPaths.length ? localPaths[i] : null;
      if (localPath != null && localPath.isNotEmpty) {
        final file = File(localPath);
        if (await file.exists()) {
          items.add(ProjectImageViewerItem(path: localPath));
          continue;
        }
      }

      final relativePath = i < relativePaths.length ? relativePaths[i] : null;
      if (relativePath == null || relativePath.isEmpty) continue;
      final settings = ref.read(appSettingsRepositoryProvider);
      final directoryService = MarkdownDirectoryService(settings);
      final root = await directoryService.ensureRoot();
      final file = File(p.joinAll([root, ...p.posix.split(relativePath)]));
      if (await file.exists()) {
        items.add(ProjectImageViewerItem(path: file.path));
      }
    }

    if (items.isNotEmpty) {
      await _showProjectImageViewer(update, items);
      return;
    }

    final relativePath = update.primaryImageRelativePath;
    if (relativePath == null || relativePath.isEmpty) {
      _showProjectSnack('这张图片资料缺少文件路径');
      return;
    }

    try {
      final settings = ref.read(appSettingsRepositoryProvider);
      final directoryService = MarkdownDirectoryService(settings);
      final treeUri = await directoryService.getTreeRootUri();
      if (Platform.isAndroid && treeUri != null && treeUri.isNotEmpty) {
        final storage = MarkdownStorageService(directoryService);
        await storage.openTreeDocument(
          relativePath: relativePath,
          mimeType: update.mimeType ?? 'image/jpeg',
        );
        return;
      }

      final root = await directoryService.ensureRoot();
      final file = File(p.joinAll([root, ...p.posix.split(relativePath)]));
      if (!await file.exists()) {
        throw StateError('图片文件不存在：$relativePath');
      }
      await _showProjectImageViewer(update, [
        ProjectImageViewerItem(path: file.path),
      ]);
    } catch (e) {
      _showProjectSnack('打开图片资料失败：$e');
    }
  }

  Future<void> _showProjectImageViewer(
    _ProjectUpdate update,
    List<ProjectImageViewerItem> images,
  ) async {
    if (!mounted) return;
    final result = await Navigator.of(context).push<ProjectImageViewerResult>(
      MaterialPageRoute(
        builder: (_) => ProjectImageViewerPage(
          title: update.text,
          images: images,
          requestRename: (context, title) {
            return showDialog<String>(
              context: context,
              builder: (_) => _ProjectImageNameDialog(
                title: '修改图片名称',
                initialTitle: _customTitleFromProjectImageName(title),
              ),
            );
          },
        ),
      ),
    );
    if (result == null || !mounted) return;

    final relativePath = update.primaryImageRelativePath;
    final project = _selectedProject;
    if (project == null || relativePath == null || relativePath.isEmpty) {
      _showProjectSnack('这张图片资料缺少项目路径');
      return;
    }

    try {
      switch (result.action) {
        case ProjectImageViewerAction.rename:
          final title = result.title?.trim();
          if (title == null || title.isEmpty) return;
          await updateProjectImageMaterialName(
            ref,
            projectId: project.id,
            projectName: project.name,
            imageRelativePath: relativePath,
            title: title,
            updatedAt: DateTime.now(),
          );
        case ProjectImageViewerAction.delete:
          await deleteProjectImageMaterial(
            ref,
            projectId: project.id,
            imageRelativePath: relativePath,
            updatedAt: DateTime.now(),
          );
      }
      if (!mounted) return;
      await _loadProjects();
      _showProjectSnack(
        result.action == ProjectImageViewerAction.delete
            ? '图片资料已删除'
            : '图片名称已更新',
      );
    } catch (e) {
      _showProjectSnack('处理图片资料失败：$e');
    }
  }

  void _showProjectSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _syncProjectArchive(
    _ProjectInfo project, {
    ProjectArchiveEntry? entry,
    bool entryAsMajor = false,
    bool showConfirmation = false,
  }) async {
    try {
      final settings = ref.read(appSettingsRepositoryProvider);
      final location = await ProjectMarkdownService(settings).syncArchive(
        project: project.toJson(),
        entry: entry,
        entryAsMajor: entryAsMajor,
      );
      if (!mounted) return;
      if (location != project.archiveLocation) {
        final nextProjects = [
          for (final item in _projects)
            if (item.id == project.id)
              item.copyWith(archiveLocation: location)
            else
              item,
        ];
        setState(() => _projects = nextProjects);
        await _saveProjects(nextProjects);
      }
      if (showConfirmation && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('项目档案已更新')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('项目档案暂时没有写入成功，项目内容已保存')));
    }
  }

  _ProjectInfo? _projectById(String projectId) {
    for (final project in _projects) {
      if (project.id == projectId) return project;
    }
    return null;
  }

  void _toggleCompletedStack() {
    setState(() {
      _completedExpanded = !_completedExpanded;
      final selected = _selectedProject;
      if (!_completedExpanded && (selected?.isCompleted ?? false)) {
        _selectedProjectId = _firstProject(_activeProjects)?.id;
      } else if (_completedExpanded && selected == null) {
        _selectedProjectId = _firstProject(_completedProjects)?.id;
      }
    });
  }

  Future<List<_ProjectHeatEntry>> _loadProjectRecordHeatEntries(
    List<_ProjectInfo> projects,
  ) async {
    if (projects.isEmpty) return const [];

    final projectNames = {
      for (final project in projects) project.id: project.name,
    };
    final records = ref.read(recordsRepositoryProvider);
    final today = _dateOnly(DateTime.now());
    final startDate = _heatmapStartDate(today);
    final entries = <_ProjectHeatEntry>[];

    for (var offset = 0; offset < 84; offset++) {
      final date = startDate.add(Duration(days: offset));
      if (date.isAfter(today)) break;

      final rows = await records.findByDate(date);
      for (final row in rows) {
        final metadata = _decodeMetadata(row['metadata']);
        if (metadata['projectEntryType'] != 'update') continue;

        final projectId = metadata['projectId'] as String?;
        if (projectId == null || !projectNames.containsKey(projectId)) {
          continue;
        }

        final createdAtMillis = row['created_at'] as int?;
        entries.add(
          _ProjectHeatEntry(
            projectName: projectNames[projectId]!,
            source: '文本记录',
            text: row['content'] as String? ?? '',
            createdAt: createdAtMillis == null
                ? date
                : DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
          ),
        );
      }
    }
    return entries;
  }

  Future<void> _createProjectTimelineRecord({
    required _ProjectInfo project,
    required String content,
    required String entryType,
    required DateTime createdAt,
  }) {
    return ref
        .read(recordsRepositoryProvider)
        .create(
          date: createdAt,
          type: 'memo',
          content: content,
          tags: ['项目', project.name],
          metadata: {
            'projectId': project.id,
            'projectName': project.name,
            'projectEntryType': entryType,
            'source': 'project_page',
          },
          createdAt: createdAt,
        );
  }

  @override
  Widget build(BuildContext context) {
    final project = _selectedProject;
    final activeProjects = _activeProjects;
    final completedProjects = _completedProjects;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _ProjectsHeader(
                      onOpenAllProjects: _projects.isEmpty
                          ? null
                          : _openAllProjects,
                      onAddProject: _openAddProject,
                      saving: _saving,
                    ),
                  ),
                  if (_projects.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyProjects(onAddProject: _openAddProject),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: _ProjectCardCarousel(
                        activeProjects: activeProjects,
                        completedProjects: completedProjects,
                        completedExpanded: _completedExpanded,
                        selectedProjectId: project?.id,
                        onSelected: (project) =>
                            setState(() => _selectedProjectId = project.id),
                        onEdit: _openEditProject,
                        onToggleCompleted: _toggleCompletedStack,
                        onReorderProjects: _reorderProjects,
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.containerMargin,
                        AppSpacing.md,
                        AppSpacing.containerMargin,
                        AppSpacing.xxl,
                      ),
                      sliver: SliverList.list(
                        children: [
                          if (project != null) ...[
                            _CurrentProjectHint(project: project),
                            const SizedBox(height: AppSpacing.md),
                            if (project.isArchived)
                              _ArchivedProjectNotice(
                                project: project,
                                onEdit: () => _openEditProject(project),
                              )
                            else ...[
                              _SmartTodoSection(
                                project: project,
                                onToggle: _toggleTodo,
                                onAddTodo: _openAddTodo,
                                onEditTodo: _openEditTodo,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _SmartUpdatesSection(
                                project: project,
                                onAddUpdate: _openAddUpdate,
                                onAddImage: _openAddProjectImageMaterial,
                                onAddFile: _openAddProjectFileMaterial,
                                onSaveArchive: _saveArchiveSnapshot,
                                onOpenUpdate: _openProjectUpdate,
                                addingImage: _addingProjectImage,
                                addingFile: _addingProjectFile,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.md),
                          ],
                          _HeatmapSection(
                            projects: _projects,
                            recordEntries: _projectRecordHeatEntries,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ProjectsHeader extends StatelessWidget {
  const _ProjectsHeader({
    required this.onOpenAllProjects,
    required this.onAddProject,
    required this.saving,
  });

  final VoidCallback? onOpenAllProjects;
  final VoidCallback onAddProject;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              onPressed: onOpenAllProjects,
              icon: const Icon(Icons.menu_rounded),
              tooltip: '项目总览',
              color: onOpenAllProjects == null
                  ? AppColors.muted.withAlpha(110)
                  : AppColors.ink,
            ),
            Expanded(
              child: Text(
                saving ? '项目 · 保存中' : '项目',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: onAddProject,
              icon: const Icon(Icons.add_rounded),
              tooltip: '添加项目',
              color: AppColors.ink,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.onAddProject});

  final VoidCallback onAddProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.containerMargin),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.flag_rounded,
              color: AppColors.primary,
              size: 34,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '先放一个想慢慢推进的事',
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '之后每天的记录、待办和专注，都可以慢慢归到项目下面。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onAddProject,
            icon: const Icon(Icons.add_rounded),
            label: const Text('新建第一个项目'),
          ),
        ],
      ),
    );
  }
}

class _ProjectCardCarousel extends StatelessWidget {
  const _ProjectCardCarousel({
    required this.activeProjects,
    required this.completedProjects,
    required this.completedExpanded,
    required this.selectedProjectId,
    required this.onSelected,
    required this.onEdit,
    required this.onToggleCompleted,
    required this.onReorderProjects,
  });

  final List<_ProjectInfo> activeProjects;
  final List<_ProjectInfo> completedProjects;
  final bool completedExpanded;
  final String? selectedProjectId;
  final ValueChanged<_ProjectInfo> onSelected;
  final ValueChanged<_ProjectInfo> onEdit;
  final VoidCallback onToggleCompleted;
  final ValueChanged<List<String>> onReorderProjects;

  @override
  Widget build(BuildContext context) {
    final cards = [
      ...activeProjects.map<_ProjectShelfItem>(_ProjectShelfCard.new),
      if (completedProjects.isNotEmpty)
        if (completedExpanded) ...[
          ...completedProjects.map<_ProjectShelfItem>(_ProjectShelfCard.new),
          _ProjectShelfStack(completedProjects),
        ] else
          _ProjectShelfStack(completedProjects),
    ];

    void handleReorder(int oldIndex, int newIndex) {
      if (oldIndex < 0 || oldIndex >= cards.length) return;
      if (cards[oldIndex] is! _ProjectShelfCard) return;

      final nextCards = [...cards];
      final moved = nextCards.removeAt(oldIndex);
      var insertionIndex = newIndex;
      if (insertionIndex > oldIndex) insertionIndex -= 1;
      final stackOffset =
          nextCards.isNotEmpty && nextCards.last is _ProjectShelfStack ? 1 : 0;
      final maxInsertionIndex = nextCards.length - stackOffset;
      insertionIndex = insertionIndex.clamp(0, maxInsertionIndex).toInt();
      nextCards.insert(insertionIndex, moved);

      onReorderProjects([
        for (final item in nextCards)
          if (item is _ProjectShelfCard) item.project.id,
      ]);
    }

    return SizedBox(
      height: 150,
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.only(left: AppSpacing.containerMargin),
        proxyDecorator: (child, _, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final t = Curves.easeOutCubic.transform(animation.value);
              return Transform.scale(
                scale: 1 + t * 0.03,
                child: Material(
                  color: Colors.transparent,
                  elevation: 8 * t,
                  borderRadius: BorderRadius.circular(12),
                  child: child,
                ),
              );
            },
            child: child,
          );
        },
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        onReorder: handleReorder,
        itemBuilder: (context, index) {
          final item = cards[index];
          if (item is _ProjectShelfStack) {
            return Padding(
              key: const ValueKey('completed-project-stack'),
              padding: const EdgeInsets.only(right: AppSpacing.containerMargin),
              child: _CompletedProjectsStack(
                projects: item.projects,
                expanded: completedExpanded,
                onTap: onToggleCompleted,
              ),
            );
          }
          final project = (item as _ProjectShelfCard).project;
          return Padding(
            key: ValueKey('project-card-${project.id}'),
            padding: EdgeInsets.only(
              right: index == cards.length - 1
                  ? AppSpacing.containerMargin
                  : AppSpacing.sm,
            ),
            child: _ProjectCard(
              project: project,
              selected: project.id == selectedProjectId,
              onTap: () => onSelected(project),
              onEdit: () => onEdit(project),
              reorderHandle: ReorderableDragStartListener(
                index: index,
                child: const _ProjectReorderHandle(),
              ),
            ),
          );
        },
      ),
    );
  }
}

sealed class _ProjectShelfItem {
  const _ProjectShelfItem();
}

class _ProjectShelfCard extends _ProjectShelfItem {
  const _ProjectShelfCard(this.project);

  final _ProjectInfo project;
}

class _ProjectShelfStack extends _ProjectShelfItem {
  const _ProjectShelfStack(this.projects);

  final List<_ProjectInfo> projects;
}

class _ProjectReorderHandle extends StatelessWidget {
  const _ProjectReorderHandle();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '拖动排序',
      child: SizedBox.square(
        dimension: 24,
        child: Center(
          child: Icon(
            Icons.drag_indicator_rounded,
            size: 18,
            color: AppColors.muted.withAlpha(150),
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    this.reorderHandle,
  });

  final _ProjectInfo project;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final Widget? reorderHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: '查看${project.name}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 216 : 190,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: selected ? AppColors.surface : AppColors.surfaceLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? AppColors.primary.withAlpha(130)
                    : AppColors.border,
              ),
              boxShadow: [
                if (selected)
                  BoxShadow(
                    color: AppColors.primary.withAlpha(18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (reorderHandle != null) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      reorderHandle!,
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  project.goal,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                    height: 1.5,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: AppColors.primary.withAlpha(150),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Expanded(
                      child: Text(
                        project.lastUpdate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _StatusEditPill(status: project.status, onEdit: onEdit),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletedProjectsStack extends StatelessWidget {
  const _CompletedProjectsStack({
    required this.projects,
    required this.expanded,
    required this.onTap,
  });

  final List<_ProjectInfo> projects;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topProject = projects.first;

    return Semantics(
      button: true,
      label: expanded ? '收起已完成项目' : '展开已完成项目',
      child: SizedBox(
        width: 154,
        height: 150,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 10,
              top: 14,
              right: 0,
              bottom: 4,
              child: _StackPaperLayer(alpha: 150),
            ),
            Positioned(
              left: 5,
              top: 8,
              right: 5,
              bottom: 10,
              child: _StackPaperLayer(alpha: 190),
            ),
            Positioned.fill(
              child: Material(
                color: AppColors.surface,
                elevation: 2,
                shadowColor: AppColors.softShadow,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_stories_rounded,
                              size: 18,
                              color: AppColors.tracker,
                            ),
                            const Spacer(),
                            _StatusPill(status: '完成'),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          expanded ? '收起完成' : '已完成',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          expanded ? '放回纸堆' : '${projects.length} 个项目',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          topProject.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StackPaperLayer extends StatelessWidget {
  const _StackPaperLayer({required this.alpha});

  final int alpha;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withAlpha(alpha),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withAlpha(180)),
      ),
    );
  }
}

class _CurrentProjectHint extends StatelessWidget {
  const _CurrentProjectHint({required this.project});

  final _ProjectInfo project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '当前查看：${project.name}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ArchivedProjectNotice extends StatelessWidget {
  const _ArchivedProjectNotice({required this.project, required this.onEdit});

  final _ProjectInfo project;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _SectionCard(
      title: '归档项目',
      trailing: '已收起',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${project.name} 已收进归档，日常项目区不会再显示它。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.unarchive_rounded, size: 18),
            label: const Text('恢复项目'),
          ),
        ],
      ),
    );
  }
}

class _SmartTodoSection extends StatefulWidget {
  const _SmartTodoSection({
    required this.project,
    required this.onToggle,
    required this.onAddTodo,
    required this.onEditTodo,
  });

  final _ProjectInfo project;
  final ValueChanged<String> onToggle;
  final VoidCallback onAddTodo;
  final ValueChanged<String> onEditTodo;

  @override
  State<_SmartTodoSection> createState() => _SmartTodoSectionState();
}

class _SmartTodoSectionState extends State<_SmartTodoSection> {
  var _showOlderTodos = false;

  @override
  Widget build(BuildContext context) {
    final recentTodos = _sortProjectTodos(
      widget.project.todos.where(_isRecentProjectTodo).toList(),
    );
    final olderTodos = _sortProjectTodos(
      widget.project.todos
          .where((todo) => !_isRecentProjectTodo(todo))
          .toList(),
    );
    final doneCount = widget.project.todos.where((todo) => todo.done).length;

    return _SectionCard(
      title: '待办',
      trailing: widget.project.todos.isEmpty
          ? '还没有下一步'
          : '${recentTodos.length} 个近7天 · $doneCount 已完成',
      action: TextButton.icon(
        onPressed: widget.onAddTodo,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('添加'),
      ),
      child: widget.project.todos.isEmpty
          ? _EmptyTodoPrompt(onAddTodo: widget.onAddTodo)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (recentTodos.isEmpty)
                  const _SoftEmptyText('近7天没有待办，早一点的事项已经收进下面。')
                else
                  for (final todo in recentTodos)
                    _ExpandableTodoRow(
                      key: ValueKey(todo.id),
                      todo: todo,
                      onTap: () => widget.onToggle(todo.id),
                      onEdit: () => widget.onEditTodo(todo.id),
                    ),
                if (olderTodos.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _ArchiveBox(
                    title: '7天以外',
                    subtitle: '${olderTodos.length} 个待办已收纳',
                    expanded: _showOlderTodos,
                    onToggle: () =>
                        setState(() => _showOlderTodos = !_showOlderTodos),
                  ),
                ],
                if (_showOlderTodos)
                  for (final todo in olderTodos)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: _ExpandableTodoRow(
                        key: ValueKey(todo.id),
                        todo: todo,
                        onTap: () => widget.onToggle(todo.id),
                        onEdit: () => widget.onEditTodo(todo.id),
                      ),
                    ),
              ],
            ),
    );
  }
}

class _ArchiveBox extends StatelessWidget {
  const _ArchiveBox({
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onToggle,
  });

  final String title;
  final String subtitle;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.surfaceLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: AppColors.muted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandableTodoRow extends StatefulWidget {
  const _ExpandableTodoRow({
    super.key,
    required this.todo,
    required this.onTap,
    required this.onEdit,
  });

  final _ProjectTodo todo;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  State<_ExpandableTodoRow> createState() => _ExpandableTodoRowState();
}

class _ExpandableTodoRowState extends State<_ExpandableTodoRow> {
  static const _collapsedTextLines = 2;
  static const _longTextThreshold = 34;

  var _expanded = false;
  bool? _optimisticDone;
  var _tapQueued = false;

  bool get _displayDone => _optimisticDone ?? widget.todo.done;

  @override
  void didUpdateWidget(covariant _ExpandableTodoRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.todo.id != widget.todo.id) {
      _optimisticDone = null;
      _tapQueued = false;
      return;
    }
    if (_optimisticDone == widget.todo.done) {
      _optimisticDone = null;
    }
  }

  void _handleTap() {
    if (_tapQueued) return;
    final nextDone = !_displayDone;
    final onTap = widget.onTap;
    setState(() {
      _optimisticDone = nextDone;
      _tapQueued = true;
    });
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 180)).then((_) {
        onTap();
        if (mounted) {
          setState(() => _tapQueued = false);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canToggleText = widget.todo.title.runes.length > _longTextThreshold;
    final done = _displayDone;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          onTap: _handleTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: done
                        ? AppColors.primary.withAlpha(24)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: done
                          ? AppColors.primary
                          : AppColors.outlineVariant,
                    ),
                  ),
                  child: done
                      ? const Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: AppColors.primary,
                        )
                      : null,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.todo.title,
                        maxLines: _expanded ? null : _collapsedTextLines,
                        overflow: _expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: done ? AppColors.muted : AppColors.ink,
                          height: 1.45,
                          decoration: done ? TextDecoration.lineThrough : null,
                          decorationColor: AppColors.muted,
                        ),
                      ),
                      if (canToggleText) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 16,
                          ),
                          label: Text(_expanded ? '收起' : '展开'),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '修改待办',
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_rounded),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _TodoSection extends StatelessWidget {
  const _TodoSection({
    required this.project,
    required this.onToggle,
    required this.onAddTodo,
    required this.onEditTodo,
  });

  final _ProjectInfo project;
  final ValueChanged<String> onToggle;
  final VoidCallback onAddTodo;
  final ValueChanged<String> onEditTodo;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '待办',
      trailing: project.todos.isEmpty
          ? '还没有下一步'
          : '${project.todos.length} 个下一步',
      action: TextButton.icon(
        onPressed: onAddTodo,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('添加'),
      ),
      child: project.todos.isEmpty
          ? _EmptyTodoPrompt(onAddTodo: onAddTodo)
          : Column(
              children: [
                for (final todo in project.todos)
                  _TodoRow(
                    todo: todo,
                    onTap: () => onToggle(todo.id),
                    onEdit: () => onEditTodo(todo.id),
                  ),
              ],
            ),
    );
  }
}

class _EmptyTodoPrompt extends StatelessWidget {
  const _EmptyTodoPrompt({required this.onAddTodo});

  final VoidCallback onAddTodo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '这里放这个项目自己的下一步。',
          style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onAddTodo,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('添加待办'),
        ),
      ],
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({
    required this.todo,
    required this.onTap,
    required this.onEdit,
  });

  final _ProjectTodo todo;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: todo.done
                        ? AppColors.primary.withAlpha(24)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: todo.done
                          ? AppColors.primary
                          : AppColors.outlineVariant,
                    ),
                  ),
                  child: todo.done
                      ? const Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: AppColors.primary,
                        )
                      : null,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    todo.title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: todo.done ? AppColors.muted : AppColors.ink,
                      height: 1.45,
                      decoration: todo.done ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.muted,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '修改待办',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmartUpdatesSection extends StatefulWidget {
  const _SmartUpdatesSection({
    required this.project,
    required this.onAddUpdate,
    required this.onAddImage,
    required this.onAddFile,
    required this.onSaveArchive,
    required this.onOpenUpdate,
    required this.addingImage,
    required this.addingFile,
  });

  final _ProjectInfo project;
  final VoidCallback onAddUpdate;
  final VoidCallback onAddImage;
  final VoidCallback onAddFile;
  final VoidCallback onSaveArchive;
  final ValueChanged<_ProjectUpdate> onOpenUpdate;
  final bool addingImage;
  final bool addingFile;

  @override
  State<_SmartUpdatesSection> createState() => _SmartUpdatesSectionState();
}

class _SmartUpdatesSectionState extends State<_SmartUpdatesSection> {
  static const _visibleUpdateCount = 10;

  var _showOlderUpdates = false;

  @override
  Widget build(BuildContext context) {
    final updates = widget.project.updates;
    final visibleUpdates = updates.take(_visibleUpdateCount).toList();
    final olderCount = updates.length - visibleUpdates.length;
    final olderUpdates = _showOlderUpdates
        ? updates.skip(_visibleUpdateCount).toList()
        : const <_ProjectUpdate>[];

    return _SectionCard(
      title: '最近更新',
      trailing: olderCount <= 0 ? '来自项目和待办' : '保留10条 · $olderCount 条已收纳',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: widget.onSaveArchive,
            icon: const Icon(Icons.save_alt_rounded, size: 16),
            label: const Text('存档'),
          ),
          _ProjectUpdateAddMenu(
            adding: widget.addingImage || widget.addingFile,
            onAddUpdate: widget.onAddUpdate,
            onAddImage: widget.onAddImage,
            onAddFile: widget.onAddFile,
          ),
        ],
      ),
      child: updates.isEmpty
          ? _EmptyUpdatePrompt(onAddUpdate: widget.onAddUpdate)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < visibleUpdates.length; i++)
                  _UpdateRow(
                    update: visibleUpdates[i],
                    isLast: i == visibleUpdates.length - 1 && olderCount == 0,
                    onTap:
                        visibleUpdates[i].isLongNote ||
                            visibleUpdates[i].isImageMaterial ||
                            visibleUpdates[i].isFileMaterial
                        ? () => widget.onOpenUpdate(visibleUpdates[i])
                        : null,
                  ),
                if (olderCount > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _ArchiveBox(
                    title: '收纳框',
                    subtitle: '$olderCount 条较早更新',
                    expanded: _showOlderUpdates,
                    onToggle: () =>
                        setState(() => _showOlderUpdates = !_showOlderUpdates),
                  ),
                ],
                if (_showOlderUpdates)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Column(
                      children: [
                        for (var i = 0; i < olderUpdates.length; i++)
                          _UpdateRow(
                            update: olderUpdates[i],
                            isLast: i == olderUpdates.length - 1,
                            onTap:
                                olderUpdates[i].isLongNote ||
                                    olderUpdates[i].isImageMaterial ||
                                    olderUpdates[i].isFileMaterial
                                ? () => widget.onOpenUpdate(olderUpdates[i])
                                : null,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

enum _ProjectUpdateAddAction { update, image, file }

class _ProjectUpdateAddMenu extends StatelessWidget {
  const _ProjectUpdateAddMenu({
    required this.adding,
    required this.onAddUpdate,
    required this.onAddImage,
    required this.onAddFile,
  });

  final bool adding;
  final VoidCallback onAddUpdate;
  final VoidCallback onAddImage;
  final VoidCallback onAddFile;

  @override
  Widget build(BuildContext context) {
    if (adding) {
      return TextButton.icon(
        onPressed: null,
        icon: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: const Text('添加'),
      );
    }

    return PopupMenuButton<_ProjectUpdateAddAction>(
      tooltip: '添加',
      onSelected: (action) {
        switch (action) {
          case _ProjectUpdateAddAction.update:
            onAddUpdate();
          case _ProjectUpdateAddAction.image:
            onAddImage();
          case _ProjectUpdateAddAction.file:
            onAddFile();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _ProjectUpdateAddAction.update,
          child: ListTile(
            leading: Icon(Icons.edit_note_rounded),
            title: Text('写更新'),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: _ProjectUpdateAddAction.image,
          child: ListTile(
            leading: Icon(Icons.add_photo_alternate_rounded),
            title: Text('图片'),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: _ProjectUpdateAddAction.file,
          child: ListTile(
            leading: Icon(Icons.attach_file_rounded),
            title: Text('文件'),
            dense: true,
          ),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 16),
            SizedBox(width: 6),
            Text('添加'),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _UpdatesSection extends StatelessWidget {
  const _UpdatesSection({
    required this.project,
    required this.onAddUpdate,
    required this.onSaveArchive,
    required this.onOpenUpdate,
  });

  final _ProjectInfo project;
  final VoidCallback onAddUpdate;
  final VoidCallback onSaveArchive;
  final ValueChanged<_ProjectUpdate> onOpenUpdate;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '最近更新',
      trailing: '来自项目和待办',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: onSaveArchive,
            icon: const Icon(Icons.save_alt_rounded, size: 16),
            label: const Text('存档'),
          ),
          TextButton.icon(
            onPressed: onAddUpdate,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('添加'),
          ),
        ],
      ),
      child: project.updates.isEmpty
          ? _EmptyUpdatePrompt(onAddUpdate: onAddUpdate)
          : Column(
              children: [
                for (var i = 0; i < project.updates.length; i++)
                  _UpdateRow(
                    update: project.updates[i],
                    isLast: i == project.updates.length - 1,
                    onTap: project.updates[i].isLongNote
                        ? () => onOpenUpdate(project.updates[i])
                        : null,
                  ),
              ],
            ),
    );
  }
}

class _EmptyUpdatePrompt extends StatelessWidget {
  const _EmptyUpdatePrompt({required this.onAddUpdate});

  final VoidCallback onAddUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '项目推进的片刻会出现在这里。',
          style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onAddUpdate,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('添加更新'),
        ),
      ],
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.update, required this.isLast, this.onTap});

  final _ProjectUpdate update;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(update.colorValue);

    final text = Text(
      update.text,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: onTap == null ? AppColors.ink : AppColors.primary,
        height: 1.45,
        fontWeight: onTap == null ? null : FontWeight.w700,
      ),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    color: AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _SourceChip(label: update.source, color: color),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        update.time,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  if (onTap == null)
                    text
                  else
                    InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(child: text),
                            const SizedBox(width: AppSpacing.xs),
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 16,
                              color: AppColors.primary.withAlpha(180),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (update.isImageMaterial &&
                      update.allImagePaths.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    _ProjectImagePreviewStrip(paths: update.allImagePaths),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectImagePreviewStrip extends StatelessWidget {
  const _ProjectImagePreviewStrip({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          return Stack(
            children: [
              _ProjectImagePreview(path: paths[index]),
              if (index == 0 && paths.length > 1)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(150),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${paths.length}张',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProjectImagePreview extends StatelessWidget {
  const _ProjectImagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        width: 104,
        height: 76,
        color: AppColors.canvas,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Icon(
            Icons.image_not_supported_rounded,
            color: AppColors.muted.withAlpha(170),
          ),
        ),
      ),
    );
  }
}

class _ProjectImageNameDialog extends StatefulWidget {
  const _ProjectImageNameDialog({
    required this.title,
    this.initialTitle = '',
    this.projectName,
    this.extension,
    this.createdAt,
  });

  final String title;
  final String initialTitle;
  final String? projectName;
  final String? extension;
  final DateTime? createdAt;

  @override
  State<_ProjectImageNameDialog> createState() =>
      _ProjectImageNameDialogState();
}

class _ProjectImageNameDialogState extends State<_ProjectImageNameDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _errorText = '自定义说明不能为空。');
      return;
    }
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    final projectName = widget.projectName;
    final createdAt = widget.createdAt;
    final extension = widget.extension;
    final preview =
        projectName == null || createdAt == null || extension == null
        ? null
        : '$projectName-${createdAt.month}.${createdAt.day}-自定义$extension';
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: '自定义说明',
          hintText: '例如：竞品截图-首页',
          helperText: preview == null ? null : '格式：$preview',
          errorText: _errorText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

String _customTitleFromProjectImageName(String fileName) {
  final withoutExtension = fileName.replaceFirst(
    RegExp(r'\.[A-Za-z0-9]{2,5}$'),
    '',
  );
  final parts = withoutExtension.split('-');
  if (parts.length >= 3 && RegExp(r'^\d{1,2}\.\d{1,2}$').hasMatch(parts[1])) {
    return parts.skip(2).join('-');
  }
  return withoutExtension;
}

class _HeatmapSection extends StatefulWidget {
  const _HeatmapSection({required this.projects, required this.recordEntries});

  final List<_ProjectInfo> projects;
  final List<_ProjectHeatEntry> recordEntries;

  @override
  State<_HeatmapSection> createState() => _HeatmapSectionState();
}

class _HeatmapSectionState extends State<_HeatmapSection> {
  DateTime? _selectedDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _dateOnly(DateTime.now());
    final startDate = _heatmapStartDate(today);
    final dayEntries = _buildDayEntries(
      widget.projects,
      widget.recordEntries,
      startDate,
      today,
    );
    final selectedDate = _selectedDate;
    final selectedEntries = selectedDate == null
        ? const <_ProjectHeatEntry>[]
        : dayEntries[_dateKey(selectedDate)] ?? const <_ProjectHeatEntry>[];

    return _SectionCard(
      title: '全部项目推进',
      trailing: '全部项目',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '项目更新、待办变化和归属项目的记录都会点亮这里。',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          _ContributionCalendar(
            startDate: startDate,
            today: today,
            entriesByDate: dayEntries,
            selectedDate: selectedDate,
            onSelected: (date) => setState(() => _selectedDate = date),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('少', style: theme.textTheme.bodySmall),
              const SizedBox(width: AppSpacing.xxs),
              for (final alpha in [28, 70, 120, 180])
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(alpha),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const SizedBox(width: AppSpacing.xxs),
              Text('多', style: theme.textTheme.bodySmall),
            ],
          ),
          if (selectedDate != null) ...[
            const SizedBox(height: AppSpacing.md),
            _SelectedDayProjectEntries(
              date: selectedDate,
              entries: selectedEntries,
            ),
          ],
        ],
      ),
    );
  }
}

class _ContributionCalendar extends StatelessWidget {
  const _ContributionCalendar({
    required this.startDate,
    required this.today,
    required this.entriesByDate,
    required this.selectedDate,
    required this.onSelected,
  });

  final DateTime startDate;
  final DateTime today;
  final Map<String, List<_ProjectHeatEntry>> entriesByDate;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final columns = List.generate(12, (week) {
      return List.generate(7, (weekday) {
        return startDate.add(Duration(days: week * 7 + weekday));
      });
    });
    final monthLabels = <int, String>{};
    for (var index = 0; index < columns.length; index++) {
      final monthStart = columns[index].firstWhere(
        (date) => index == 0 || date.day == 1,
        orElse: () => columns[index].first,
      );
      if (index == 0 || monthStart.day == 1) {
        monthLabels[index] = '${monthStart.month}月';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 16,
          child: Row(
            children: [
              for (var column = 0; column < columns.length; column++)
                SizedBox(
                  width: 18,
                  child: Text(
                    monthLabels[column] ?? '',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final week in columns)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Column(
                  children: [
                    for (final date in week)
                      _HeatmapCell(
                        date: date,
                        count: date.isAfter(today)
                            ? 0
                            : entriesByDate[_dateKey(date)]?.length ?? 0,
                        selected:
                            selectedDate != null &&
                            _sameDay(selectedDate!, date),
                        enabled: !date.isAfter(today),
                        onTap: () => onSelected(date),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SelectedDayProjectEntries extends StatelessWidget {
  const _SelectedDayProjectEntries({required this.date, required this.entries});

  final DateTime date;
  final List<_ProjectHeatEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = '${date.month}月${date.day}日';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withAlpha(120),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entries.isEmpty
                ? '$label · 暂无项目推进'
                : '$label · ${entries.length} 条项目推进',
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.primary,
            ),
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            for (final entry in entries.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Text(
                  '${entry.source} · ${entry.projectName}：${entry.text}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.ink,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProjectHeatEntry {
  const _ProjectHeatEntry({
    required this.projectName,
    required this.source,
    required this.text,
    required this.createdAt,
  });

  final String projectName;
  final String source;
  final String text;
  final DateTime createdAt;

  _ProjectHeatEntry copyWith({String? projectName}) {
    return _ProjectHeatEntry(
      projectName: projectName ?? this.projectName,
      source: source,
      text: text,
      createdAt: createdAt,
    );
  }
}

Map<String, List<_ProjectHeatEntry>> _buildDayEntries(
  List<_ProjectInfo> projects,
  List<_ProjectHeatEntry> recordEntries,
  DateTime startDate,
  DateTime today,
) {
  final result = <String, List<_ProjectHeatEntry>>{};
  final seen = <String>{};

  void addEntry(_ProjectHeatEntry entry) {
    final date = _dateOnly(entry.createdAt);
    if (date.isBefore(startDate) || date.isAfter(today)) return;

    final key =
        '${_dateKey(date)}|${entry.projectName}|${entry.source}|${entry.text}';
    if (!seen.add(key)) return;

    result.putIfAbsent(_dateKey(date), () => []).add(entry);
  }

  for (final project in projects) {
    for (final update in project.updates) {
      final date = _dateOnly(
        DateTime.fromMillisecondsSinceEpoch(update.createdAt),
      );
      addEntry(
        _ProjectHeatEntry(
          projectName: project.name,
          source: update.source,
          text: update.text,
          createdAt: date,
        ),
      );
    }
  }
  for (final entry in recordEntries) {
    addEntry(entry);
  }
  return result;
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.date,
    required this.count,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final DateTime date;
  final int count;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final alpha = switch (count) {
      0 => 26,
      1 => 62,
      2 => 104,
      3 => 150,
      _ => 205,
    };

    return Semantics(
      button: true,
      label: '${date.month}月${date.day}日，$count 条项目推进',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 13,
          height: 13,
          margin: const EdgeInsets.only(bottom: 5),
          decoration: BoxDecoration(
            color: enabled
                ? AppColors.primary.withAlpha(alpha)
                : AppColors.border.withAlpha(90),
            borderRadius: BorderRadius.circular(3),
            border: selected ? Border.all(color: AppColors.primary) : null,
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
    this.action,
  });

  final String title;
  final String? trailing;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  Flexible(
                    child: Text(
                      trailing!,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
                if (action != null) ...[
                  if (trailing == null) const Spacer(),
                  const SizedBox(width: AppSpacing.xs),
                  action!,
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

class _SoftEmptyText extends StatelessWidget {
  const _SoftEmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
    );
  }
}

class _AllProjectsPage extends StatefulWidget {
  const _AllProjectsPage({required this.projects, required this.selectedId});

  final List<_ProjectInfo> projects;
  final String? selectedId;

  @override
  State<_AllProjectsPage> createState() => _AllProjectsPageState();
}

class _AllProjectsPageState extends State<_AllProjectsPage> {
  var _filter = '全部项目';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleProjects = widget.projects.where((project) {
      if (_filter == '全部项目') return !project.isArchived;
      if (_filter == '归档') return project.isArchived;
      return project.status == _filter;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('所有项目'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          tooltip: '关闭',
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.containerMargin,
            AppSpacing.md,
            AppSpacing.containerMargin,
            AppSpacing.xl,
          ),
          children: [
            Text(
              '把暂时不推进的项目收进归档，记录不会丢失。',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.muted,
                height: 1.55,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final label in ['全部项目', ..._projectStatuses, '归档'])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == label,
                    onSelected: (_) => setState(() => _filter = label),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (visibleProjects.isEmpty)
              const _SoftEmptyText('这里暂时没有项目。')
            else
              for (final project in visibleProjects)
                _AllProjectRow(
                  project: project,
                  selected: project.id == widget.selectedId,
                  onTap: () => Navigator.of(context).pop(project.id),
                ),
          ],
        ),
      ),
    );
  }
}

class _AllProjectRow extends StatelessWidget {
  const _AllProjectRow({
    required this.project,
    required this.selected,
    required this.onTap,
  });

  final _ProjectInfo project;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withAlpha(18) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.primary.withAlpha(90) : AppColors.border,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        title: Row(
          children: [
            Flexible(
              child: Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _StatusPill(status: project.status),
          ],
        ),
        subtitle: Text(
          project.goal,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        trailing: selected
            ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
            : const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
      ),
    );
  }
}

class _AddProjectPage extends StatefulWidget {
  const _AddProjectPage();

  @override
  State<_AddProjectPage> createState() => _AddProjectPageState();
}

class _ProjectTextEntrySheet extends StatefulWidget {
  const _ProjectTextEntrySheet({
    required this.title,
    required this.subtitle,
    required this.hintText,
    required this.submitLabel,
    required this.emptyErrorText,
    this.initialText = '',
    this.maxLines = 1,
  });

  final String title;
  final String subtitle;
  final String hintText;
  final String submitLabel;
  final String emptyErrorText;
  final String initialText;
  final int maxLines;

  @override
  State<_ProjectTextEntrySheet> createState() => _ProjectTextEntrySheetState();
}

class _ProjectTextEntrySheetState extends State<_ProjectTextEntrySheet> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _errorText = widget.emptyErrorText);
      return;
    }
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.containerMargin,
          AppSpacing.lg,
          AppSpacing.containerMargin,
          AppSpacing.lg + bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              widget.subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              minLines: widget.maxLines,
              maxLines: widget.maxLines,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(hintText: widget.hintText),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _errorText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.accent,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.check_rounded),
                label: Text(widget.submitLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditProjectSheet extends StatefulWidget {
  const _EditProjectSheet({required this.project});

  final _ProjectInfo project;

  @override
  State<_EditProjectSheet> createState() => _EditProjectSheetState();
}

class _EditProjectSheetState extends State<_EditProjectSheet> {
  late final TextEditingController _nameController;
  late String _status;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.project.name);
    _status = widget.project.isArchived ? '暂停' : widget.project.status;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '项目名称不能为空。');
      return;
    }
    Navigator.of(context).pop(_ProjectEditDraft(name: name, status: _status));
  }

  void _archive() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '项目名称不能为空。');
      return;
    }
    Navigator.of(context).pop(
      _ProjectEditDraft(name: name, status: _status, archiveRequested: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.containerMargin,
          AppSpacing.lg,
          AppSpacing.containerMargin,
          AppSpacing.lg + bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '编辑项目',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              widget.project.isArchived
                  ? '保存后会从归档恢复到日常项目。'
                  : '名称和状态会同步到项目总览与 Markdown 档案。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _ProjectTextField(
              controller: _nameController,
              label: '项目名称',
              hintText: '例如：做 Dayline',
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '当前状态',
              style: theme.textTheme.labelLarge?.copyWith(color: AppColors.ink),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final status in _projectStatuses)
                  ChoiceChip(
                    label: Text(status),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
              ],
            ),
            if (_errorText != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _errorText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.accent,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.check_rounded),
                label: Text(widget.project.isArchived ? '恢复项目' : '保存修改'),
              ),
            ),
            if (!widget.project.isArchived) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _archive,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('归档项目'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddProjectPageState extends State<_AddProjectPage> {
  final _nameController = TextEditingController();
  final _goalController = TextEditingController();
  final _todoController = TextEditingController();
  var _status = '进行中';
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _goalController.dispose();
    _todoController.dispose();
    super.dispose();
  }

  void _createProject() {
    final name = _nameController.text.trim();
    final goal = _goalController.text.trim();
    final firstTodo = _todoController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '先写一个项目名称。');
      return;
    }

    Navigator.of(context).pop(
      _ProjectDraft(
        name: name,
        goal: goal.isEmpty ? '慢慢推进这件事' : goal,
        status: _status,
        firstTodo: firstTodo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('添加项目')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.containerMargin,
            AppSpacing.md,
            AppSpacing.containerMargin,
            AppSpacing.xl,
          ),
          children: [
            Text(
              '先写下一个想慢慢推进的事，之后每天的记录都可以归到这里。',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.muted,
                height: 1.55,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ProjectTextField(
              controller: _nameController,
              label: '项目名称',
              hintText: '例如：做 Dayline',
            ),
            const SizedBox(height: AppSpacing.md),
            _ProjectTextField(
              controller: _goalController,
              label: '一句话目标',
              hintText: '想长期推进什么？',
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '当前状态',
              style: theme.textTheme.labelLarge?.copyWith(color: AppColors.ink),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final status in _projectStatuses)
                  ChoiceChip(
                    label: Text(status),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _ProjectTextField(
              controller: _todoController,
              label: '第一条待办（可选）',
              hintText: '先写一个很小的下一步',
            ),
            if (_errorText != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _errorText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.accent,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _createProject,
              icon: const Icon(Icons.check_rounded),
              label: const Text('创建项目'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '稍后再补充也可以',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectTextField extends StatelessWidget {
  const _ProjectTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hintText),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _StatusEditPill extends StatelessWidget {
  const _StatusEditPill({required this.status, required this.onEdit});

  final String status;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);

    return Material(
      color: color.withAlpha(20),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.edit_rounded, size: 13, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

Color _statusColor(String status) {
  return switch (status) {
    '进行中' => AppColors.primary,
    '暂停' => AppColors.secondary,
    '完成' => AppColors.tracker,
    '未开始' => AppColors.focus,
    '归档' => AppColors.muted,
    _ => AppColors.muted,
  };
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _ProjectDraft {
  const _ProjectDraft({
    required this.name,
    required this.goal,
    required this.status,
    required this.firstTodo,
  });

  final String name;
  final String goal;
  final String status;
  final String firstTodo;
}

class _ProjectEditDraft {
  const _ProjectEditDraft({
    required this.name,
    required this.status,
    this.archiveRequested = false,
  });

  final String name;
  final String status;
  final bool archiveRequested;
}

const _projectStatuses = ['进行中', '暂停', '未开始', '完成'];
const _projectUpdatesRetainLimit = 60;

class _ProjectInfo {
  const _ProjectInfo({
    required this.id,
    required this.name,
    required this.status,
    required this.goal,
    required this.lastUpdate,
    required this.todos,
    required this.updates,
    this.archiveLocation,
  });

  final String id;
  final String name;
  final String status;
  final String goal;
  final String lastUpdate;
  final List<_ProjectTodo> todos;
  final List<_ProjectUpdate> updates;
  final String? archiveLocation;

  bool get isCompleted => status == '完成';
  bool get isArchived => status == '归档';
  bool get isActiveForDaily => !isCompleted && !isArchived;

  _ProjectTodo? todoById(String todoId) {
    for (final todo in todos) {
      if (todo.id == todoId) return todo;
    }
    return null;
  }

  _ProjectInfo toggleTodo(String todoId, {required DateTime updatedAt}) {
    final writtenAt = _formatUpdateTime(updatedAt);
    _ProjectTodo? changedTodo;
    final nextTodos = [
      for (final todo in todos)
        if (todo.id == todoId)
          changedTodo = todo.copyWith(done: !todo.done)
        else
          todo,
    ];
    final changed = changedTodo;
    if (changed == null) return this;

    return copyWith(
      lastUpdate: writtenAt,
      todos: nextTodos,
      updates: [
        _ProjectUpdate(
          id: '${updatedAt.microsecondsSinceEpoch}-update',
          time: writtenAt,
          createdAt: updatedAt.millisecondsSinceEpoch,
          source: '待办',
          text: '${changed.done ? '完成' : '恢复'}：${changed.title}',
          colorValue: AppColors.todo.toARGB32(),
        ),
        ...updates.take(_projectUpdatesRetainLimit - 1),
      ],
    );
  }

  _ProjectInfo renameTodo(
    String todoId,
    String title, {
    required DateTime updatedAt,
  }) {
    final writtenAt = _formatUpdateTime(updatedAt);
    var changed = false;
    final nextTodos = [
      for (final todo in todos)
        if (todo.id == todoId)
          () {
            changed = true;
            return todo.copyWith(title: title);
          }()
        else
          todo,
    ];
    if (!changed) return this;

    return copyWith(
      lastUpdate: writtenAt,
      todos: nextTodos,
      updates: [
        _ProjectUpdate(
          id: '${updatedAt.microsecondsSinceEpoch}-todo-edit-update',
          time: writtenAt,
          createdAt: updatedAt.millisecondsSinceEpoch,
          source: '待办',
          text: '修改待办：$title',
          colorValue: AppColors.todo.toARGB32(),
        ),
        ...updates.take(_projectUpdatesRetainLimit - 1),
      ],
    );
  }

  _ProjectInfo addUpdate(String text, {required DateTime createdAt}) {
    final writtenAt = _formatUpdateTime(createdAt);
    return copyWith(
      lastUpdate: writtenAt,
      updates: [
        _ProjectUpdate(
          id: '${createdAt.microsecondsSinceEpoch}-manual-update',
          time: writtenAt,
          createdAt: createdAt.millisecondsSinceEpoch,
          source: '文本记录',
          text: text,
          colorValue: AppColors.primary.toARGB32(),
        ),
        ...updates.take(_projectUpdatesRetainLimit - 1),
      ],
    );
  }

  _ProjectInfo addTodo(String title, {required DateTime createdAt}) {
    final writtenAt = _formatUpdateTime(createdAt);
    return copyWith(
      lastUpdate: writtenAt,
      todos: [
        ...todos,
        _ProjectTodo(
          id: '${createdAt.microsecondsSinceEpoch}-todo',
          title: title,
        ),
      ],
      updates: [
        _ProjectUpdate(
          id: '${createdAt.microsecondsSinceEpoch}-todo-update',
          time: writtenAt,
          createdAt: createdAt.millisecondsSinceEpoch,
          source: '待办',
          text: '添加待办：$title',
          colorValue: AppColors.todo.toARGB32(),
        ),
        ...updates.take(_projectUpdatesRetainLimit - 1),
      ],
    );
  }

  _ProjectInfo updateBasics({
    required String name,
    required String status,
    required DateTime updatedAt,
  }) {
    final writtenAt = _formatUpdateTime(updatedAt);
    return copyWith(
      name: name,
      status: status,
      lastUpdate: writtenAt,
      updates: [
        _ProjectUpdate(
          id: '${updatedAt.microsecondsSinceEpoch}-project-edit-update',
          time: writtenAt,
          createdAt: updatedAt.millisecondsSinceEpoch,
          source: '项目',
          text: '更新项目：${this.name} → $name，状态：$status',
          colorValue: AppColors.primary.toARGB32(),
        ),
        ...updates.take(_projectUpdatesRetainLimit - 1),
      ],
    );
  }

  _ProjectInfo copyWith({
    String? name,
    String? status,
    String? lastUpdate,
    List<_ProjectTodo>? todos,
    List<_ProjectUpdate>? updates,
    String? archiveLocation,
  }) {
    return _ProjectInfo(
      id: id,
      name: name ?? this.name,
      status: status ?? this.status,
      goal: goal,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      todos: todos ?? this.todos,
      updates: updates ?? this.updates,
      archiveLocation: archiveLocation ?? this.archiveLocation,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'status': status,
      'goal': goal,
      'lastUpdate': lastUpdate,
      'todos': todos.map((todo) => todo.toJson()).toList(),
      'updates': updates.map((update) => update.toJson()).toList(),
      if (archiveLocation != null) 'archiveLocation': archiveLocation,
    };
  }

  static _ProjectInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String?;
    final name = raw['name'] as String?;
    if (id == null || name == null || name.trim().isEmpty) return null;

    return _ProjectInfo(
      id: id,
      name: name,
      status: raw['status'] as String? ?? '进行中',
      goal: raw['goal'] as String? ?? '慢慢推进这件事',
      lastUpdate: raw['lastUpdate'] as String? ?? '刚刚',
      archiveLocation: raw['archiveLocation'] as String?,
      todos: [
        for (final item in (raw['todos'] as List? ?? const []))
          if (_ProjectTodo.fromJson(item) != null) _ProjectTodo.fromJson(item)!,
      ],
      updates: [
        for (final item in (raw['updates'] as List? ?? const []).take(
          _projectUpdatesRetainLimit,
        ))
          if (_ProjectUpdate.fromJson(item) != null)
            _ProjectUpdate.fromJson(item)!,
      ],
    );
  }
}

class _ProjectTodo {
  const _ProjectTodo({
    required this.id,
    required this.title,
    this.done = false,
  });

  final String id;
  final String title;
  final bool done;

  DateTime get createdAt => _dateFromProjectId(id);

  _ProjectTodo copyWith({String? title, bool? done}) {
    return _ProjectTodo(
      id: id,
      title: title ?? this.title,
      done: done ?? this.done,
    );
  }

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'done': done};

  static _ProjectTodo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String?;
    final title = raw['title'] as String?;
    if (id == null || title == null || title.trim().isEmpty) return null;
    return _ProjectTodo(id: id, title: title, done: raw['done'] == true);
  }
}

class _ProjectUpdate {
  const _ProjectUpdate({
    required this.id,
    required this.time,
    required this.createdAt,
    required this.source,
    required this.text,
    required this.colorValue,
    this.entryType,
    this.notePath,
    this.imagePath,
    this.imageRelativePath,
    this.imagePaths = const [],
    this.imageRelativePaths = const [],
    this.mimeTypes = const [],
    this.mimeType,
    this.filePath,
    this.fileRelativePath,
    this.recordId,
  });

  final String id;
  final String time;
  final int createdAt;
  final String source;
  final String text;
  final int colorValue;
  final String? entryType;
  final String? notePath;
  final String? imagePath;
  final String? imageRelativePath;
  final List<String> imagePaths;
  final List<String> imageRelativePaths;
  final List<String> mimeTypes;
  final String? mimeType;
  final String? filePath;
  final String? fileRelativePath;
  final int? recordId;

  DateTime get createdDate => DateTime.fromMillisecondsSinceEpoch(createdAt);

  bool get isLongNote =>
      entryType == 'long_note' && notePath != null && notePath!.isNotEmpty;

  bool get isImageMaterial =>
      entryType == 'image' &&
      ((imagePath != null && imagePath!.isNotEmpty) ||
          (imageRelativePath != null && imageRelativePath!.isNotEmpty) ||
          imagePaths.isNotEmpty ||
          imageRelativePaths.isNotEmpty);

  bool get isFileMaterial =>
      entryType == 'file' &&
      ((filePath != null && filePath!.isNotEmpty) ||
          (fileRelativePath != null && fileRelativePath!.isNotEmpty));

  String? get primaryImagePath {
    if (imagePaths.isNotEmpty) return imagePaths.first;
    return imagePath;
  }

  List<String> get allImagePaths {
    if (imagePaths.isNotEmpty) return imagePaths;
    final path = imagePath;
    if (path == null || path.isEmpty) return const [];
    return [path];
  }

  String? get primaryImageRelativePath {
    if (imageRelativePaths.isNotEmpty) return imageRelativePaths.first;
    return imageRelativePath;
  }

  List<String> get allImageRelativePaths {
    if (imageRelativePaths.isNotEmpty) return imageRelativePaths;
    final path = imageRelativePath;
    if (path == null || path.isEmpty) return const [];
    return [path];
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'time': time,
      'createdAt': createdAt,
      'source': source,
      'text': text,
      'colorValue': colorValue,
      if (entryType != null) 'entryType': entryType,
      if (notePath != null) 'notePath': notePath,
      if (imagePath != null) 'imagePath': imagePath,
      if (imageRelativePath != null) 'imageRelativePath': imageRelativePath,
      if (imagePaths.isNotEmpty) 'imagePaths': imagePaths,
      if (imageRelativePaths.isNotEmpty)
        'imageRelativePaths': imageRelativePaths,
      if (mimeTypes.isNotEmpty) 'mimeTypes': mimeTypes,
      if (mimeType != null) 'mimeType': mimeType,
      if (filePath != null) 'filePath': filePath,
      if (fileRelativePath != null) 'fileRelativePath': fileRelativePath,
      if (recordId != null) 'recordId': recordId,
    };
  }

  static _ProjectUpdate? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String?;
    final text = raw['text'] as String?;
    if (id == null || text == null || text.trim().isEmpty) return null;
    return _ProjectUpdate(
      id: id,
      time: raw['time'] as String? ?? '刚刚',
      createdAt: raw['createdAt'] as int? ?? _createdAtFromProjectUpdateId(id),
      source: raw['source'] as String? ?? '项目',
      text: text,
      colorValue: raw['colorValue'] as int? ?? AppColors.primary.toARGB32(),
      entryType: raw['entryType'] as String?,
      notePath: raw['notePath'] as String?,
      imagePath: raw['imagePath'] as String?,
      imageRelativePath: raw['imageRelativePath'] as String?,
      imagePaths: _stringList(raw['imagePaths']),
      imageRelativePaths: _stringList(raw['imageRelativePaths']),
      mimeTypes: _stringList(raw['mimeTypes']),
      mimeType: raw['mimeType'] as String?,
      filePath: raw['filePath'] as String?,
      fileRelativePath: raw['fileRelativePath'] as String?,
      recordId: raw['recordId'] as int?,
    );
  }
}

List<_ProjectInfo> _decodeProjects(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (_ProjectInfo.fromJson(item) != null) _ProjectInfo.fromJson(item)!,
    ];
  } catch (_) {
    return const [];
  }
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is String && item.isNotEmpty) item,
  ];
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

List<_ProjectTodo> _sortProjectTodos(List<_ProjectTodo> todos) {
  return [...todos]..sort((a, b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    return b.createdAt.compareTo(a.createdAt);
  });
}

bool _isRecentProjectTodo(_ProjectTodo todo) {
  final createdAt = _dateOnly(todo.createdAt);
  final today = _dateOnly(DateTime.now());
  return !createdAt.isBefore(today.subtract(const Duration(days: 6)));
}

_ProjectInfo? _firstProject(List<_ProjectInfo> projects) {
  return projects.isEmpty ? null : projects.first;
}

String _projectStatusChangeText(
  _ProjectInfo previous,
  String nextName,
  String nextStatus,
) {
  if (nextStatus == '归档') return '归档项目：$nextName';
  if (previous.isArchived) return '恢复项目：$nextName，状态：$nextStatus';
  return '更新项目：${previous.name} → $nextName，状态：$nextStatus';
}

Future<void> _openLocalFile(String path) async {
  if (Platform.isWindows) {
    await Process.start('cmd', ['/c', 'start', '', path]);
    return;
  }
  if (Platform.isMacOS) {
    await Process.start('open', [path]);
    return;
  }
  if (Platform.isLinux) {
    await Process.start('xdg-open', [path]);
    return;
  }
  throw StateError('当前平台暂不支持打开本地文件');
}

DateTime _heatmapStartDate(DateTime today) {
  final currentWeekStart = today.subtract(
    Duration(days: today.weekday - DateTime.monday),
  );
  return currentWeekStart.subtract(const Duration(days: 77));
}

String _dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

Map<String, Object?> _decodeMetadata(Object? raw) {
  if (raw is! String || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return decoded.cast<String, Object?>();
  } catch (_) {
    return const {};
  }
  return const {};
}

int _createdAtFromProjectUpdateId(String id) {
  final rawMicroseconds = int.tryParse(id.split('-').first);
  if (rawMicroseconds == null) {
    return DateTime.now().millisecondsSinceEpoch;
  }
  return DateTime.fromMicrosecondsSinceEpoch(
    rawMicroseconds,
  ).millisecondsSinceEpoch;
}

DateTime _dateFromProjectId(String id) {
  final rawMicroseconds = int.tryParse(id.split('-').first);
  if (rawMicroseconds == null) return DateTime.now();
  return DateTime.fromMicrosecondsSinceEpoch(rawMicroseconds);
}

String _formatUpdateTime(DateTime time) {
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
