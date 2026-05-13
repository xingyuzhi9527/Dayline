import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/repository_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../long_note/long_note_editor_page.dart';
import '../../long_note/long_note_reader_page.dart';
import '../timeline_providers.dart';

extension _AsyncValueX<T> on AsyncValue<T> {
  T? get valueOrNull => switch (this) {
    AsyncData(value: final v) => v,
    _ => null,
  };
}

String _formatDate(DateTime date) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';
}

String _formatTime(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class TimelineDateBar extends ConsumerWidget {
  const TimelineDateBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(timelineDateProvider);
    final notifier = ref.read(timelineDateProvider.notifier);
    final isToday = _isSameDay(date, DateTime.now());
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('时间线', style: theme.textTheme.headlineMedium),
              const Spacer(),
              _TrashButton(),
              const SizedBox(width: AppSpacing.xs),
              if (!isToday)
                TextButton(
                  onPressed: notifier.goToToday,
                  child: const Text('回到今天'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '前一天',
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: notifier.goToPrevDay,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _formatDate(date),
                          style: theme.textTheme.titleMedium,
                        ),
                        Consumer(
                          builder: (context, ref, _) {
                            final events = ref.watch(timelineEventsProvider);
                            final count = events.valueOrNull?.length;
                            return Text(
                              count == null ? '加载中' : '$count 条记录',
                              style: theme.textTheme.bodySmall,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '后一天',
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: notifier.goToNextDay,
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

class TimelineBody extends ConsumerWidget {
  const TimelineBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(timelineEventsProvider);

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (events) {
        if (events.isEmpty) {
          return _EmptyTimeline(date: ref.watch(timelineDateProvider));
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xl,
          ),
          itemCount: events.length + 1,
          itemBuilder: (context, index) {
            if (index == events.length) {
              return const _TimelineEndMarker();
            }

            final nextEvent = index < events.length - 1
                ? events[index + 1]
                : null;
            return _TimelineTile(
              event: events[index],
              isLast: index == events.length - 1,
              gapAfter: nextEvent == null
                  ? null
                  : Duration(
                      milliseconds:
                          nextEvent.timestamp - events[index].timestamp,
                    ),
            );
          },
        );
      },
    );
  }
}

class _TimelineTile extends ConsumerWidget {
  const _TimelineTile({
    required this.event,
    required this.isLast,
    required this.gapAfter,
  });

  final TimelineEvent event;
  final bool isLast;
  final Duration? gapAfter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _colorForType(event.type);
    final isRight = event.source == TimelineEventSource.todo ||
        event.type == 'long_note';
    final theme = Theme.of(context);
    final card = _TimelineEventCard(
      event: event,
      color: color,
      theme: theme,
      onTap: event.type == 'long_note'
          ? () => _openReader(context, ref)
          : null,
      onEdit: () => _openEditor(context, ref),
    );

    return Column(
      children: [
        IntrinsicHeight(
          child: Padding(
            padding: EdgeInsets.zero,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.sm,
                      right: AppSpacing.md,
                    ),
                    child: isRight
                        ? const SizedBox.shrink()
                        : Align(
                            alignment: Alignment.topRight,
                            child: KeyedSubtree(
                              key: ValueKey('timeline-left-card-${event.id}'),
                              child: card,
                            ),
                          ),
                  ),
                ),
                _TimelineRail(color: color, isLast: isLast),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.md,
                      right: AppSpacing.sm,
                    ),
                    child: isRight
                        ? Align(
                            alignment: Alignment.topLeft,
                            child: KeyedSubtree(
                              key: ValueKey('timeline-right-card-${event.id}'),
                              child: card,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (gapAfter != null && gapAfter!.inMinutes > 0)
          _TimelineGap(gapAfter!),
      ],
    );
  }

  Future<void> _openReader(BuildContext context, WidgetRef ref) async {
    final rawMeta = event.data['metadata'];
    Map<String, Object?>? meta;
    if (rawMeta is String) {
      try { meta = Map<String, Object?>.from(jsonDecode(rawMeta)); } catch (_) {}
    } else if (rawMeta is Map) {
      meta = Map<String, Object?>.from(rawMeta);
    }
    final path = meta?['path'] as String?;
    final file = path != null ? File(path) : null;
    var body = '';
    if (file != null && await file.exists()) {
      final raw = await file.readAsString();
      final start = raw.indexOf('---\n');
      if (start == 0) {
        final end = raw.indexOf('\n---\n', start + 4);
        if (end != -1) body = raw.substring(end + 5).trim();
      }
      final firstNewline = body.indexOf('\n');
      if (body.startsWith('# ') && firstNewline != -1) {
        body = body.substring(firstNewline + 1).trim();
      }
    }
    if (!context.mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LongNoteReaderPage(
          title: event.title,
          filePath: path ?? '',
          body: body,
          recordId: event.sourceId,
        ),
      ),
    );
    if (saved == true && context.mounted) {
      ref.invalidate(timelineEventsProvider);
    }
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    if (event.type == 'long_note') {
      Map<String, Object?>? meta;
      final rawMeta = event.data['metadata'];
      if (rawMeta is String) {
        try { meta = Map<String, Object?>.from(jsonDecode(rawMeta)); } catch (_) {}
      } else if (rawMeta is Map) {
        meta = Map<String, Object?>.from(rawMeta as Map);
      }
      final path = meta?['path'] as String?;
      final file = path != null ? File(path) : null;
      var body = '';
      if (file != null && await file.exists()) {
        final raw = await file.readAsString();
        // Strip YAML front matter
        final start = raw.indexOf('---\n');
        if (start == 0) {
          final end = raw.indexOf('\n---\n', start + 4);
          if (end != -1) {
            body = raw.substring(end + 5).trim();
          } else {
            body = raw;
          }
        } else {
          body = raw;
        }
        // Strip leading "# Title" line
        final firstNewline = body.indexOf('\n');
        if (body.startsWith('# ') && firstNewline != -1) {
          body = body.substring(firstNewline + 1).trim();
        }
      }
      if (!context.mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => LongNoteEditorPage(
            initialTitle: event.title,
            initialBody: body,
            existingPath: path,
            recordId: event.sourceId,
          ),
        ),
      );
      if (saved == true && context.mounted) {
        ref.invalidate(timelineEventsProvider);
      }
      return;
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TimelineEventEditSheet(event: event),
    );

    if (saved != true || !context.mounted) return;

    ref.invalidate(timelineEventsProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('已修改'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 1),
        ),
      );
  }
}

class _TimelineRail extends StatelessWidget {
  const _TimelineRail({required this.color, required this.isLast});

  final Color color;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: 1.4,
                margin: const EdgeInsets.only(top: 14),
                color: isLast
                    ? Colors.transparent
                    : AppColors.muted.withAlpha(26),
              ),
            ),
          ),
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: color.withAlpha(50), width: 1.4),
            ),
            child: Center(
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: color.withAlpha(200),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineGap extends StatelessWidget {
  const _TimelineGap(this.gap);

  final Duration gap;

  @override
  Widget build(BuildContext context) {
    final height = _gapHeightForDuration(gap);
    if (height <= 0) return const SizedBox.shrink();

    return SizedBox(
      height: height,
      child: Row(
        children: [
          const Expanded(child: SizedBox.shrink()),
          SizedBox(
            width: 30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 1.4,
                  height: height,
                  color: AppColors.muted.withAlpha(18),
                ),
              ],
            ),
          ),
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _TimelineEventCard extends StatelessWidget {
  const _TimelineEventCard({
    required this.event,
    required this.color,
    required this.theme,
    this.onTap,
    required this.onEdit,
  });

  final TimelineEvent event;
  final Color color;
  final ThemeData theme;
  final VoidCallback? onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final hasDetails = event.description.isNotEmpty || event.tags.isNotEmpty;

    final card = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(70),
          ),
          boxShadow: const [
            BoxShadow(
              color: AppColors.softShadow,
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: color.withAlpha(190)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${_formatTime(event.timestamp)} · ${_labelForType(event.type)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: IconButton(
                          key: ValueKey('edit-${event.id}'),
                          tooltip: '修改',
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_rounded),
                          iconSize: 15,
                          visualDensity: VisualDensity.compact,
                          color: AppColors.muted,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: hasDetails ? 2 : 0),
                    child: Text(
                      event.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.28,
                      ),
                    ),
                  ),
                  if (event.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: Text(
                        event.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.muted,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ),
                  if (event.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 0,
                        children: event.tags
                            .map(
                              (tag) => Text(
                                '#$tag',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: color.withAlpha(160),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      );
    }
    return card;
  }
}

class _TimelineEventEditSheet extends ConsumerStatefulWidget {
  const _TimelineEventEditSheet({required this.event});

  final TimelineEvent event;

  @override
  ConsumerState<_TimelineEventEditSheet> createState() =>
      _TimelineEventEditSheetState();
}

class _TimelineEventEditSheetState
    extends ConsumerState<_TimelineEventEditSheet> {
  final _contentController = TextEditingController();
  final _timeController = TextEditingController();
  final _tagsController = TextEditingController();
  final _noteController = TextEditingController();
  final _dueTimeController = TextEditingController();
  final _priorityController = TextEditingController();
  final _valueController = TextEditingController();
  final _durationController = TextEditingController();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  final _currencyController = TextEditingController();
  final _metricController = TextEditingController();
  final _unitController = TextEditingController();

  bool _isCompleted = false;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final data = widget.event.data;

    switch (widget.event.source) {
      case TimelineEventSource.record:
        _contentController.text =
            (data['content'] as String?) ?? widget.event.title;
        _timeController.text = (data['time'] as String?) ?? '';
        _tagsController.text = _decodeTags(data['tags']).join(' ');

      case TimelineEventSource.todo:
        _contentController.text =
            (data['title'] as String?) ?? widget.event.title;
        _noteController.text = (data['note'] as String?) ?? '';
        _dueTimeController.text = (data['due_time'] as String?) ?? '';
        _priorityController.text = '${data['priority'] ?? 0}';
        _isCompleted = (data['is_completed'] as int? ?? 0) == 1;

      case TimelineEventSource.trackerLog:
        _contentController.text =
            (data['tracker_name'] as String?) ?? widget.event.title;
        _valueController.text = _numberText(data['value'] ?? 1);
        _noteController.text = (data['note'] as String?) ?? '';

      case TimelineEventSource.focusSession:
        _durationController.text = '${data['duration_minutes'] ?? ''}';
        _noteController.text = (data['note'] as String?) ?? '';

      case TimelineEventSource.expense:
        _amountController.text = _numberText(data['amount']);
        _categoryController.text = (data['category'] as String?) ?? '';
        _noteController.text = (data['note'] as String?) ?? '';
        _currencyController.text = (data['currency'] as String?) ?? 'CNY';

      case TimelineEventSource.bodyLog:
        _metricController.text = (data['metric'] as String?) ?? '';
        _valueController.text = _numberText(data['value']);
        _unitController.text = (data['unit'] as String?) ?? '';
        _noteController.text = (data['note'] as String?) ?? '';
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    _timeController.dispose();
    _tagsController.dispose();
    _noteController.dispose();
    _dueTimeController.dispose();
    _priorityController.dispose();
    _valueController.dispose();
    _durationController.dispose();
    _amountController.dispose();
    _categoryController.dispose();
    _currencyController.dispose();
    _metricController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '修改${_labelForType(widget.event.type)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ..._buildFields(theme),
                if (_errorText != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _errorText!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                    ),
                    if (widget.event.source == TimelineEventSource.record) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _deleteRecord,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            side: const BorderSide(color: AppColors.accent),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          label: const Text('删除'),
                        ),
                      ),
                    ],
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('timeline-edit-save'),
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 18),
                        label: const Text('保存'),
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

  List<Widget> _buildFields(ThemeData theme) {
    return switch (widget.event.source) {
      TimelineEventSource.record => [
        _textField(
          controller: _contentController,
          label: '内容',
          minLines: 2,
          maxLines: 4,
        ),
        _textField(controller: _tagsController, label: '标签'),
      ],
      TimelineEventSource.todo => [
        _textField(controller: _contentController, label: '标题'),
        _textField(
          controller: _noteController,
          label: '备注',
          minLines: 2,
          maxLines: 3,
        ),
        _textField(controller: _dueTimeController, label: '截止时间'),
        _textField(
          controller: _priorityController,
          label: '优先级',
          keyboardType: TextInputType.number,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('已完成'),
          value: _isCompleted,
          onChanged: _saving
              ? null
              : (value) => setState(() => _isCompleted = value),
        ),
      ],
      TimelineEventSource.trackerLog => [
        _readOnlyValue(theme, '打卡项', _contentController.text),
        _textField(
          controller: _valueController,
          label: '数值',
          keyboardType: TextInputType.number,
        ),
        _textField(
          controller: _noteController,
          label: '备注',
          minLines: 2,
          maxLines: 3,
        ),
      ],
      TimelineEventSource.focusSession => [
        _textField(
          controller: _durationController,
          label: '时长（分钟）',
          keyboardType: TextInputType.number,
        ),
        _textField(
          controller: _noteController,
          label: '备注',
          minLines: 2,
          maxLines: 3,
        ),
      ],
      TimelineEventSource.expense => [
        _textField(
          controller: _amountController,
          label: '金额',
          keyboardType: TextInputType.number,
        ),
        _textField(controller: _categoryController, label: '分类'),
        _textField(controller: _currencyController, label: '币种'),
        _textField(
          controller: _noteController,
          label: '备注',
          minLines: 2,
          maxLines: 3,
        ),
      ],
      TimelineEventSource.bodyLog => [
        _textField(controller: _metricController, label: '指标'),
        _textField(
          controller: _valueController,
          label: '数值',
          keyboardType: TextInputType.number,
        ),
        _textField(controller: _unitController, label: '单位'),
        _textField(
          controller: _noteController,
          label: '备注',
          minLines: 2,
          maxLines: 3,
        ),
      ],
    };
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 1,
  }) {
    final isMultiline = maxLines > 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        controller: controller,
        enabled: !_saving,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        textInputAction: isMultiline
            ? TextInputAction.newline
            : TextInputAction.done,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _readOnlyValue(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
      ),
    );
  }

  Future<void> _deleteRecord() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await ref
          .read(recordsRepositoryProvider)
          .softDelete(widget.event.sourceId);
      ref.read(dataVersionProvider.notifier).increment();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _errorText = '删除失败：$e';
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      switch (widget.event.source) {
        case TimelineEventSource.record:
          final content = _requiredText(_contentController, '内容');
          if (content == null) return;
          await ref
              .read(recordsRepositoryProvider)
              .updateDetails(
                widget.event.sourceId,
                content: content,
                tags: _parseTagInput(_tagsController.text),
                metadata: _decodeMetadata(widget.event.data['metadata']),
              );

        case TimelineEventSource.todo:
          final title = _requiredText(_contentController, '标题');
          if (title == null) return;
          await ref
              .read(todosRepositoryProvider)
              .updateDetails(
                widget.event.sourceId,
                title: title,
                note: _optionalText(_noteController),
                dueTime: _optionalText(_dueTimeController),
                priority: int.tryParse(_priorityController.text.trim()) ?? 0,
                isCompleted: _isCompleted,
                completedAt: widget.event.data['completed_at'] as int?,
              );

        case TimelineEventSource.trackerLog:
          final value = _requiredDouble(_valueController, '数值');
          if (value == null) return;
          await ref
              .read(trackerLogsRepositoryProvider)
              .updateDetails(
                widget.event.sourceId,
                value: value,
                note: _optionalText(_noteController),
              );

        case TimelineEventSource.focusSession:
          final duration = _requiredInt(_durationController, '时长');
          if (duration == null) return;
          await ref
              .read(focusSessionsRepositoryProvider)
              .updateDetails(
                widget.event.sourceId,
                durationMinutes: duration,
                note: _optionalText(_noteController),
              );

        case TimelineEventSource.expense:
          final amount = _requiredDouble(_amountController, '金额');
          final category = _requiredText(_categoryController, '分类');
          if (amount == null || category == null) return;
          await ref
              .read(expensesRepositoryProvider)
              .updateDetails(
                widget.event.sourceId,
                amount: amount,
                category: category,
                note: _optionalText(_noteController),
                currency: _optionalText(_currencyController) ?? 'CNY',
              );

        case TimelineEventSource.bodyLog:
          final metric = _requiredText(_metricController, '指标');
          final value = _requiredDouble(_valueController, '数值');
          if (metric == null || value == null) return;
          await ref
              .read(bodyLogsRepositoryProvider)
              .updateDetails(
                widget.event.sourceId,
                metric: metric,
                value: value,
                unit: _optionalText(_unitController),
                note: _optionalText(_noteController),
              );
      }

      ref.read(dataVersionProvider.notifier).increment();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = '保存失败：$e';
      });
    }
  }

  String? _requiredText(TextEditingController controller, String label) {
    final value = controller.text.trim();
    if (value.isNotEmpty) return value;
    _showValidationError('$label不能为空');
    return null;
  }

  double? _requiredDouble(TextEditingController controller, String label) {
    final value = double.tryParse(controller.text.trim());
    if (value != null) return value;
    _showValidationError('$label需要是数字');
    return null;
  }

  int? _requiredInt(TextEditingController controller, String label) {
    final value = int.tryParse(controller.text.trim());
    if (value != null && value > 0) return value;
    _showValidationError('$label需要是大于 0 的整数');
    return null;
  }

  void _showValidationError(String message) {
    setState(() {
      _saving = false;
      _errorText = message;
    });
  }
}

class _TimelineEndMarker extends StatelessWidget {
  const _TimelineEndMarker();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(bottom: AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(date, DateTime.now());
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_note_rounded,
              size: 64,
              color: AppColors.muted.withAlpha(85),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              isToday ? '今天还没有记录' : '这一天还没有记录',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('写下一句话开始整理这一天。', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

String? _optionalText(TextEditingController controller) {
  final value = controller.text.trim();
  return value.isEmpty ? null : value;
}

String _numberText(Object? value) {
  if (value == null) return '';
  if (value is num) {
    final asDouble = value.toDouble();
    if (asDouble == asDouble.roundToDouble()) {
      return asDouble.toInt().toString();
    }
    return asDouble.toString();
  }
  return value.toString();
}

List<String> _decodeTags(Object? raw) {
  if (raw is List<String>) return raw;
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }
  return const [];
}

Map<String, Object?> _decodeMetadata(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.cast<String, Object?>();
    } catch (_) {
      return const {};
    }
  }
  return const {};
}

List<String> _parseTagInput(String raw) {
  return raw
      .split(RegExp(r'[\s,，、#]+'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList();
}

String _labelForType(String type) => switch (type) {
  'memo' => '备忘',
  'long_note' => '长笔记',
  'todo' => '待办',
  'tracker' => '打卡',
  'focus' => '专注',
  'expense' => '消费',
  'body' => '身体',
  'sleep' => '睡眠',
  'mood' => '情绪',
  _ => type,
};

Color _colorForType(String type) => switch (type) {
  'memo' => AppColors.primary,
  'long_note' => const Color(0xFF2E7D32),
  'todo' => const Color(0xFF4A90D9),
  'tracker' => const Color(0xFF7CB342),
  'focus' => const Color(0xFFE67E22),
  'expense' => const Color(0xFFE74C3C),
  'body' => const Color(0xFF9B59B6),
  'sleep' => const Color(0xFF5C6BC0),
  'mood' => const Color(0xFFD5952F),
  _ => AppColors.muted,
};

class _TrashButton extends ConsumerWidget {
  const _TrashButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deletedAsync = ref.watch(deletedRecordsProvider);
    final count = deletedAsync.valueOrNull?.length ?? 0;

    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: '回收站',
      onPressed: () => _showTrashSheet(context, ref),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.delete_outline_rounded,
            size: 22,
            color: count > 0
                ? AppColors.accent.withAlpha(180)
                : AppColors.muted.withAlpha(120),
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showTrashSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final deletedAsync = ref.watch(deletedRecordsProvider);
        return deletedAsync.when(
          data: (deleted) {
            if (deleted.isEmpty) {
              return const SizedBox(
                height: 120,
                child: Center(
                  child: Text('回收站是空的', style: TextStyle(color: AppColors.muted)),
                ),
              );
            }
            return SizedBox(
              height: 320,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.accent),
                        const SizedBox(width: AppSpacing.xs),
                        Text('回收站 (${deleted.length})',
                            style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      itemCount: deleted.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final row = deleted[i];
                        final content = row['content'] as String? ?? '';
                        final id = row['id'] as int;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                iconSize: 18,
                                tooltip: '恢复',
                                icon: const Icon(Icons.restore_rounded, color: AppColors.tracker),
                                onPressed: () async {
                                  await ref.read(recordsRepositoryProvider).restore(id);
                                  ref.invalidate(deletedRecordsProvider);
                                  ref.invalidate(timelineEventsProvider);
                                  ref.read(dataVersionProvider.notifier).increment();
                                },
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                iconSize: 18,
                                tooltip: '彻底删除',
                                icon: Icon(Icons.delete_forever_rounded,
                                    color: AppColors.accent.withAlpha(180)),
                                onPressed: () async {
                                  await ref.read(recordsRepositoryProvider).permanentDelete(id);
                                  ref.invalidate(deletedRecordsProvider);
                                  ref.read(dataVersionProvider.notifier).increment();
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox(
            height: 80, child: Center(child: CircularProgressIndicator())),
          error: (_, __) => const SizedBox(
            height: 80, child: Center(child: Text('加载失败'))),
        );
      },
    );
  }
}

double _gapHeightForDuration(Duration gap) {
  final minutes = gap.inMinutes;
  if (minutes <= 0) return 0;
  if (minutes < 10) return 22;
  if (minutes < 30) return 34;
  if (minutes < 60) return 48;
  if (minutes < 120) return 72;
  if (minutes < 240) return 100;
  return 132;
}
