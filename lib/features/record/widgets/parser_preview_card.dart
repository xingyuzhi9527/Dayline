import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/parser/lui_lite_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../record_notifier.dart';

class ParserPreviewCard extends ConsumerWidget {
  const ParserPreviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordNotifierProvider);
    final parsed = state.parsedInput;
    if (parsed == null) return const SizedBox.shrink();

    final notifier = ref.read(recordNotifierProvider.notifier);
    final typeMeta = _TypeMeta.from(parsed.type);

    final rawText = state.inputText.isNotEmpty
        ? state.inputText
        : parsed.content;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OriginalRecordCard(text: rawText),
        const SizedBox(height: AppSpacing.md),
        _ParsedBentoGrid(
          parsed: parsed,
          typeMeta: typeMeta,
          enabled: !state.isSaving,
          onTypeChanged: notifier.updateParsedType,
        ),
        const SizedBox(height: AppSpacing.md),
        _EditableTagChips(tags: parsed.tags, enabled: !state.isSaving),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: state.isSaving ? null : () => notifier.changeToMemo(),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('存为备忘'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: state.isSaving ? null : () => notifier.confirm(),
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('确认保存'),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: TextButton(
            onPressed: state.isSaving ? null : () => notifier.cancel(),
            child: const Text('取消'),
          ),
        ),
      ],
    );
  }
}

class _OriginalRecordCard extends StatelessWidget {
  const _OriginalRecordCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '原始记录',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '"$text"',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParsedBentoGrid extends StatelessWidget {
  const _ParsedBentoGrid({
    required this.parsed,
    required this.typeMeta,
    required this.enabled,
    required this.onTypeChanged,
  });

  final ParsedInput parsed;
  final _TypeMeta typeMeta;
  final bool enabled;
  final ValueChanged<ParsedInputType> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    final duration = parsed.metadata['durationMinutes'];
    final amount = parsed.metadata['amount'];
    final value = parsed.metadata['value'];
    final detailsLabel = amount != null
        ? '金额'
        : value != null
        ? '数值'
        : '时长';
    final detailsValue = amount != null
        ? '¥$amount'
        : value != null
        ? '$value'
        : duration != null
        ? '$duration 分钟'
        : '未识别';

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.12,
      children: [
        _ParsedTile(
          icon: typeMeta.icon,
          label: '类别',
          color: typeMeta.color,
          child: _TypeMenu(
            selectedType: parsed.type,
            enabled: enabled,
            onChanged: onTypeChanged,
          ),
        ),
        _ParsedTile(
          icon: Icons.schedule_rounded,
          label: '时间',
          value: parsed.time ?? '现在',
          color: AppColors.secondaryContainer,
        ),
        _ParsedTile(
          icon: duration != null
              ? Icons.timer_rounded
              : amount != null
              ? Icons.payments_rounded
              : Icons.monitor_weight_rounded,
          label: detailsLabel,
          value: detailsValue,
          color: AppColors.accent,
        ),
        _ParsedTile(
          icon: Icons.tag_rounded,
          label: '标签',
          color: AppColors.primary,
          child: parsed.tags.isEmpty
              ? Text('无标签', style: Theme.of(context).textTheme.titleMedium)
              : Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    for (final tag in parsed.tags) _TagPreviewChip(tag: tag),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ParsedTile extends StatelessWidget {
  const _ParsedTile({
    required this.icon,
    required this.label,
    required this.color,
    this.value,
    this.child,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withAlpha(18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            child ??
                Text(
                  value ?? '',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _TagPreviewChip extends StatelessWidget {
  const _TagPreviewChip({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Text(
        '#$tag',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TypeMenu extends StatelessWidget {
  const _TypeMenu({
    required this.selectedType,
    required this.enabled,
    required this.onChanged,
  });

  final ParsedInputType selectedType;
  final bool enabled;
  final ValueChanged<ParsedInputType> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedMeta = _TypeMeta.from(selectedType);

    return PopupMenuButton<ParsedInputType>(
      enabled: enabled,
      initialValue: selectedType,
      tooltip: '修改类型',
      onSelected: onChanged,
      itemBuilder: (context) {
        return [
          for (final type in ParsedInputType.values)
            PopupMenuItem(
              value: type,
              child: Row(
                children: [
                  Icon(_TypeMeta.from(type).icon, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Text(_TypeMeta.from(type).label),
                ],
              ),
            ),
        ];
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            selectedMeta.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Icon(
            Icons.expand_more_rounded,
            size: 18,
            color: enabled ? AppColors.muted : Theme.of(context).disabledColor,
          ),
        ],
      ),
    );
  }
}

class _EditableTagChips extends ConsumerStatefulWidget {
  const _EditableTagChips({required this.tags, required this.enabled});

  final List<String> tags;
  final bool enabled;

  @override
  ConsumerState<_EditableTagChips> createState() => _EditableTagChipsState();
}

class _EditableTagChipsState extends ConsumerState<_EditableTagChips> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTags([String? rawValue]) {
    final additions = _parseTagInput(rawValue ?? _controller.text);
    if (additions.isEmpty) return;

    ref.read(recordNotifierProvider.notifier).updateParsedTags([
      ...widget.tags,
      ...additions,
    ]);
    _controller.clear();
  }

  void _removeTag(String tag) {
    ref
        .read(recordNotifierProvider.notifier)
        .updateParsedTags(widget.tags.where((value) => value != tag).toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('编辑标签', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final tag in widget.tags)
              InputChip(
                avatar: const Icon(Icons.tag, size: 14),
                label: Text('#$tag'),
                onDeleted: widget.enabled ? () => _removeTag(tag) : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 148, maxWidth: 220),
              child: TextField(
                controller: _controller,
                enabled: widget.enabled,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.tags.isEmpty ? '添加标签' : '继续添加',
                  prefixIcon: const Icon(Icons.tag, size: 18),
                  suffixIcon: IconButton(
                    tooltip: '添加标签',
                    onPressed: widget.enabled ? _addTags : null,
                    icon: const Icon(Icons.add_rounded, size: 18),
                  ),
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: _addTags,
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<String> _parseTagInput(String input) {
    return input
        .split(RegExp(r'[\s,，、#＃]+'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }
}

class _TypeMeta {
  const _TypeMeta(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  static _TypeMeta from(ParsedInputType type) => switch (type) {
    ParsedInputType.memo => const _TypeMeta(
      '备忘',
      Icons.edit_note_rounded,
      AppColors.primary,
    ),
    ParsedInputType.todo => const _TypeMeta(
      '待办',
      Icons.check_circle_outline,
      Color(0xFF4A90D9),
    ),
    ParsedInputType.tracker => const _TypeMeta(
      '打卡',
      Icons.directions_run_rounded,
      Color(0xFF7CB342),
    ),
    ParsedInputType.focus => const _TypeMeta(
      '专注',
      Icons.timer_rounded,
      Color(0xFFE67E22),
    ),
    ParsedInputType.expense => const _TypeMeta(
      '消费',
      Icons.payments_rounded,
      Color(0xFFE74C3C),
    ),
    ParsedInputType.body => const _TypeMeta(
      '身体',
      Icons.monitor_weight_rounded,
      Color(0xFF9B59B6),
    ),
    ParsedInputType.sleep => const _TypeMeta(
      '睡眠',
      Icons.bedtime_rounded,
      Color(0xFF5C6BC0),
    ),
  };
}
