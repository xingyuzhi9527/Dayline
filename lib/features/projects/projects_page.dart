import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'project_markdown_service.dart';
import 'project_store.dart';

class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  var _projects = <_ProjectInfo>[];
  var _selectedIndex = 0;
  var _loading = true;
  var _saving = false;

  _ProjectInfo? get _selectedProject {
    if (_projects.isEmpty) return null;
    return _projects[_selectedIndex.clamp(0, _projects.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProjects());
  }

  Future<void> _loadProjects() async {
    final settings = ref.read(appSettingsRepositoryProvider);
    final row = await settings.findByKey(projectsSettingsKey);
    if (!mounted) return;

    setState(() {
      _projects = _decodeProjects(row?['value'] as String?);
      _selectedIndex = _projects.isEmpty
          ? 0
          : _selectedIndex.clamp(0, _projects.length - 1);
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
      setState(() => _selectedIndex = nextIndex);
    }
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
      _selectedIndex = nextProjects.length - 1;
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

  Future<void> _saveArchiveSnapshot() async {
    final project = _selectedProject;
    if (project == null) return;
    await _syncProjectArchive(project, showConfirmation: true);
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
                        projects: _projects,
                        selectedIndex: _selectedIndex,
                        onSelected: (index) =>
                            setState(() => _selectedIndex = index),
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
                            _TodoSection(
                              project: project,
                              onToggle: _toggleTodo,
                              onAddTodo: _openAddTodo,
                              onEditTodo: _openEditTodo,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _UpdatesSection(
                              project: project,
                              onAddUpdate: _openAddUpdate,
                              onSaveArchive: _saveArchiveSnapshot,
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          _HeatmapSection(projects: _projects),
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
    required this.projects,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_ProjectInfo> projects;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 142,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.containerMargin,
        ),
        scrollDirection: Axis.horizontal,
        itemCount: projects.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          return _ProjectCard(
            project: projects[index],
            selected: index == selectedIndex,
            onTap: () => onSelected(index),
          );
        },
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
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
            width: selected ? 188 : 164,
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
                    _StatusPill(status: project.status),
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
                    Text(
                      project.lastUpdate,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

class _UpdatesSection extends StatelessWidget {
  const _UpdatesSection({
    required this.project,
    required this.onAddUpdate,
    required this.onSaveArchive,
  });

  final _ProjectInfo project;
  final VoidCallback onAddUpdate;
  final VoidCallback onSaveArchive;

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
  const _UpdateRow({required this.update, required this.isLast});

  final _ProjectUpdate update;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(update.colorValue);

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
                  Text(
                    update.text,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.ink,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeatmapSection extends StatefulWidget {
  const _HeatmapSection({required this.projects});

  final List<_ProjectInfo> projects;

  @override
  State<_HeatmapSection> createState() => _HeatmapSectionState();
}

class _HeatmapSectionState extends State<_HeatmapSection> {
  DateTime? _selectedDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _dateOnly(DateTime.now());
    final currentWeekStart = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );
    final startDate = currentWeekStart.subtract(const Duration(days: 77));
    final dayEntries = _buildDayEntries(widget.projects, startDate, today);
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
                  '${entry.projectName}：${entry.text}',
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
    required this.text,
    required this.createdAt,
  });

  final String projectName;
  final String text;
  final DateTime createdAt;
}

Map<String, List<_ProjectHeatEntry>> _buildDayEntries(
  List<_ProjectInfo> projects,
  DateTime startDate,
  DateTime today,
) {
  final result = <String, List<_ProjectHeatEntry>>{};
  for (final project in projects) {
    for (final update in project.updates) {
      final date = _dateOnly(
        DateTime.fromMillisecondsSinceEpoch(update.createdAt),
      );
      if (date.isBefore(startDate) || date.isAfter(today)) continue;
      result
          .putIfAbsent(_dateKey(date), () => [])
          .add(
            _ProjectHeatEntry(
              projectName: project.name,
              text: update.text,
              createdAt: date,
            ),
          );
    }
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
      if (_filter == '全部项目') return true;
      if (_filter == '归档') return false;
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
                for (final label in ['全部项目', '进行中', '暂停', '完成', '归档'])
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
                for (final status in ['进行中', '暂停', '未开始'])
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
    final color = switch (status) {
      '进行中' => AppColors.primary,
      '暂停' => AppColors.secondary,
      '完成' => AppColors.tracker,
      _ => AppColors.muted,
    };

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
        ...updates.take(9),
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
        ...updates.take(9),
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
        ...updates.take(9),
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
        ...updates.take(9),
      ],
    );
  }

  _ProjectInfo copyWith({
    String? lastUpdate,
    List<_ProjectTodo>? todos,
    List<_ProjectUpdate>? updates,
    String? archiveLocation,
  }) {
    return _ProjectInfo(
      id: id,
      name: name,
      status: status,
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
        for (final item in (raw['updates'] as List? ?? const []))
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
  });

  final String id;
  final String time;
  final int createdAt;
  final String source;
  final String text;
  final int colorValue;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'time': time,
      'createdAt': createdAt,
      'source': source,
      'text': text,
      'colorValue': colorValue,
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

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
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
