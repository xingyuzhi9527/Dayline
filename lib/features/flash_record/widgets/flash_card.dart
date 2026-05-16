import 'package:flutter/material.dart';

import '../../../core/parser/lui_lite_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

class FlashCard extends StatelessWidget {
  const FlashCard({
    required this.rawText,
    required this.parsedInput,
    required this.onTextChanged,
    required this.onTypeChanged,
    required this.onTagsChanged,
    required this.onSave,
    required this.onCancel,
    super.key,
  });

  final String rawText;
  final ParsedInput parsedInput;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<ParsedInputType> onTypeChanged;
  final ValueChanged<List<String>> onTagsChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  static String labelForType(ParsedInputType type) =>
      _TypeMeta.from(type).label;

  static IconData iconForType(ParsedInputType type) =>
      _TypeMeta.from(type).icon;

  static Color colorForType(ParsedInputType type) => _TypeMeta.from(type).color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeMeta = _TypeMeta.from(parsedInput.type);
    final durationMinutes = parsedInput.metadata['durationMinutes'] as int?;
    final amount = parsedInput.metadata['amount'] as num?;

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: typeMeta.color.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(typeMeta.icon, color: typeMeta.color, size: 22),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '编辑卡片',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '语音输入',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _EditableVoiceTextField(text: rawText, onChanged: onTextChanged),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Text(
                  '类型',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _TypeMenu(
                  selectedType: parsedInput.type,
                  onChanged: onTypeChanged,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _EditableTagChips(
              tags: parsedInput.tags,
              onTagsChanged: onTagsChanged,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (durationMinutes != null)
              _InfoRow(label: '时长', value: '$durationMinutes 分钟'),
            if (amount != null)
              _InfoRow(label: '金额', value: '¥${amount.toStringAsFixed(2)}'),
            if (parsedInput.time != null)
              _InfoRow(label: '时间', value: parsedInput.time!),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableVoiceTextField extends StatefulWidget {
  const _EditableVoiceTextField({required this.text, required this.onChanged});

  final String text;
  final ValueChanged<String> onChanged;

  @override
  State<_EditableVoiceTextField> createState() =>
      _EditableVoiceTextFieldState();
}

class _EditableVoiceTextFieldState extends State<_EditableVoiceTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(covariant _EditableVoiceTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text && widget.text != _controller.text) {
      _controller.text = widget.text;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('flash-card-text-field'),
      controller: _controller,
      minLines: 2,
      maxLines: 4,
      textInputAction: TextInputAction.newline,
      decoration: const InputDecoration(
        labelText: '编辑文本',
        border: OutlineInputBorder(),
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _TypeMenu extends StatelessWidget {
  const _TypeMenu({required this.selectedType, required this.onChanged});

  final ParsedInputType selectedType;
  final ValueChanged<ParsedInputType> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedMeta = _TypeMeta.from(selectedType);
    return PopupMenuButton<ParsedInputType>(
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
      child: Chip(
        avatar: Icon(selectedMeta.icon, size: 16, color: selectedMeta.color),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(selectedMeta.label),
            const SizedBox(width: AppSpacing.xxs),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

class _EditableTagChips extends StatefulWidget {
  const _EditableTagChips({required this.tags, required this.onTagsChanged});

  final List<String> tags;
  final ValueChanged<List<String>> onTagsChanged;

  @override
  State<_EditableTagChips> createState() => _EditableTagChipsState();
}

class _EditableTagChipsState extends State<_EditableTagChips> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTags([String? rawValue]) {
    final additions = _parseTagInput(rawValue ?? _controller.text);
    if (additions.isEmpty) return;
    widget.onTagsChanged([...widget.tags, ...additions]);
    _controller.clear();
  }

  void _removeTag(String tag) {
    widget.onTagsChanged(widget.tags.where((value) => value != tag).toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('标签', style: theme.textTheme.labelLarge),
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
                onDeleted: () => _removeTag(tag),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 132, maxWidth: 210),
              child: TextField(
                key: const ValueKey('flash-card-tag-field'),
                controller: _controller,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.tags.isEmpty ? '添加标签' : '继续添加',
                  prefixIcon: const Icon(Icons.tag, size: 18),
                  suffixIcon: IconButton(
                    tooltip: '添加标签',
                    onPressed: _addTags,
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
        .split(RegExp(r'[\s,，、＃#]+'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
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
      Icons.monitor_heart_outlined,
      Color(0xFF9B59B6),
    ),
    ParsedInputType.sleep => const _TypeMeta(
      '睡眠',
      Icons.bedtime_rounded,
      Color(0xFF5C6BC0),
    ),
    ParsedInputType.mood => const _TypeMeta(
      '情绪',
      Icons.emoji_emotions_outlined,
      Color(0xFF9B59B6),
    ),
  };
}
