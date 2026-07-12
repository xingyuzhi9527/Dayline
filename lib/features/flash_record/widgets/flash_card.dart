import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/parser/expense_line_item.dart';
import '../../../core/parser/lui_lite_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../projects/project_store.dart';

class FlashCard extends StatelessWidget {
  const FlashCard({
    required this.rawText,
    required this.parsedInput,
    required this.onTextChanged,
    required this.onTypeChanged,
    required this.onTagsChanged,
    required this.onExpenseItemsChanged,
    required this.projects,
    required this.selectedProjectId,
    required this.onProjectChanged,
    required this.expenseReceiptImagePath,
    required this.onAddReceiptImage,
    required this.onRemoveReceiptImage,
    required this.onSave,
    required this.onCancel,
    super.key,
  });

  final String rawText;
  final ParsedInput parsedInput;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<ParsedInputType> onTypeChanged;
  final ValueChanged<List<String>> onTagsChanged;
  final ValueChanged<List<ExpenseLineItem>> onExpenseItemsChanged;
  final List<ProjectOption> projects;
  final String? selectedProjectId;
  final ValueChanged<String?> onProjectChanged;
  final String? expenseReceiptImagePath;
  final VoidCallback onAddReceiptImage;
  final VoidCallback onRemoveReceiptImage;
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
    final colorScheme = theme.colorScheme;
    final typeMeta = _TypeMeta.from(
      parsedInput.type,
      primary: colorScheme.primary,
    );
    final durationMinutes = parsedInput.metadata['durationMinutes'] as int?;
    final amount = parsedInput.metadata['amount'] as num?;
    final isExpense = parsedInput.type == ParsedInputType.expense;
    final expenseItems = expenseLineItemsFromMetadata(parsedInput.metadata);
    final maxCardHeight =
        (MediaQuery.sizeOf(context).height - AppSpacing.xl * 2)
            .clamp(320.0, 620.0)
            .toDouble();

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxCardHeight),
        child: SingleChildScrollView(
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
                      color: colorScheme.onSurfaceVariant,
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
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _TypeMenu(
                    selectedType: parsedInput.type,
                    onChanged: onTypeChanged,
                  ),
                  const Spacer(),
                  _ProjectMenu(
                    projects: projects,
                    selectedProjectId: selectedProjectId,
                    onChanged: onProjectChanged,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _EditableTagChips(
                tags: parsedInput.tags,
                onTagsChanged: onTagsChanged,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (isExpense) ...[
                _ExpenseSplitEditor(
                  items: expenseItems,
                  fallbackName: parsedInput.content,
                  onChanged: onExpenseItemsChanged,
                ),
                const SizedBox(height: AppSpacing.sm),
                _ReceiptImagePicker(
                  imagePath: expenseReceiptImagePath,
                  onAdd: onAddReceiptImage,
                  onRemove: onRemoveReceiptImage,
                ),
              ] else ...[
                if (durationMinutes != null)
                  _InfoRow(label: '时长', value: '$durationMinutes 分钟'),
                if (amount != null)
                  _InfoRow(label: '金额', value: '¥${amount.toStringAsFixed(2)}'),
                if (parsedInput.time != null)
                  _InfoRow(label: '时间', value: parsedInput.time!),
              ],
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
    final primary = Theme.of(context).colorScheme.primary;
    final selectedMeta = _TypeMeta.from(selectedType, primary: primary);
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
                  Icon(_TypeMeta.from(type, primary: primary).icon, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Text(_TypeMeta.from(type, primary: primary).label),
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

class _ProjectMenu extends StatelessWidget {
  const _ProjectMenu({
    required this.projects,
    required this.selectedProjectId,
    required this.onChanged,
  });

  final List<ProjectOption> projects;
  final String? selectedProjectId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    ProjectOption? selectedProject;
    for (final project in projects) {
      if (project.id == selectedProjectId) {
        selectedProject = project;
        break;
      }
    }
    final enabled = projects.isNotEmpty;
    final label = selectedProject?.name ?? '项目';
    final tint = selectedProject == null
        ? colorScheme.onSurfaceVariant
        : colorScheme.primary;

    return PopupMenuButton<String?>(
      enabled: enabled,
      initialValue: selectedProjectId,
      tooltip: enabled ? '归属项目' : '暂无项目',
      onSelected: onChanged,
      itemBuilder: (context) {
        return [
          const PopupMenuItem<String?>(
            value: null,
            child: Row(
              children: [
                Icon(Icons.radio_button_unchecked_rounded, size: 18),
                SizedBox(width: AppSpacing.xs),
                Text('无项目'),
              ],
            ),
          ),
          for (final project in projects)
            PopupMenuItem<String?>(
              value: project.id,
              child: Row(
                children: [
                  Icon(
                    project.id == selectedProjectId
                        ? Icons.check_circle_rounded
                        : Icons.flag_outlined,
                    size: 18,
                    color: project.id == selectedProjectId
                        ? colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
      child: Chip(
        avatar: Icon(Icons.flag_outlined, size: 16, color: tint),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
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

class _ExpenseSplitEditor extends StatefulWidget {
  const _ExpenseSplitEditor({
    required this.items,
    required this.fallbackName,
    required this.onChanged,
  });

  final List<ExpenseLineItem> items;
  final String fallbackName;
  final ValueChanged<List<ExpenseLineItem>> onChanged;

  @override
  State<_ExpenseSplitEditor> createState() => _ExpenseSplitEditorState();
}

class _ExpenseSplitEditorState extends State<_ExpenseSplitEditor> {
  final _rows = <_ExpenseRowControllers>[];
  var _lastSignature = '';

  @override
  void initState() {
    super.initState();
    _resetRows(widget.items);
  }

  @override
  void didUpdateWidget(covariant _ExpenseSplitEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _signature(widget.items);
    if (signature != _lastSignature) {
      _resetRows(widget.items);
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _resetRows(List<ExpenseLineItem> items) {
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll(
        (items.isEmpty
                ? [ExpenseLineItem(name: widget.fallbackName, amount: 0)]
                : items)
            .map(_ExpenseRowControllers.fromItem),
      );
    _lastSignature = _signature(_readRows());
  }

  void _addRow() {
    setState(() {
      _rows.add(_ExpenseRowControllers.empty());
    });
    _emit();
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows.removeAt(index).dispose();
    });
    _emit();
  }

  void _emit() {
    final items = _readRows();
    _lastSignature = _signature(items);
    widget.onChanged(items);
  }

  List<ExpenseLineItem> _readRows() {
    return _rows
        .map((row) {
          final rawAmount = row.amount.text.trim().replaceAll(',', '.');
          return ExpenseLineItem(
            name: row.name.text.trim(),
            amount: double.tryParse(rawAmount) ?? 0,
          );
        })
        .toList(growable: false);
  }

  String _signature(List<ExpenseLineItem> items) {
    return items
        .map((item) => '${item.name}\u0001${item.amount.toStringAsFixed(2)}')
        .join('\u0002');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = expenseLineItemsTotal(_readRows());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('消费明细', style: theme.textTheme.labelLarge),
            const Spacer(),
            Text(
              '合计 ¥${total.toStringAsFixed(2)}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.expense,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var index = 0; index < _rows.length; index += 1) ...[
          _ExpenseSplitRow(
            index: index,
            row: _rows[index],
            canRemove: _rows.length > 1,
            onChanged: _emit,
            onRemove: () => _removeRow(index),
          ),
          if (index < _rows.length - 1) const SizedBox(height: AppSpacing.xs),
        ],
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('添加一笔'),
          ),
        ),
      ],
    );
  }
}

class _ExpenseSplitRow extends StatelessWidget {
  const _ExpenseSplitRow({
    required this.index,
    required this.row,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _ExpenseRowControllers row;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: ValueKey('flash-card-expense-name-$index'),
            controller: row.name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '名称',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: 116,
          child: TextField(
            key: ValueKey('flash-card-expense-amount-$index'),
            controller: row.amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '金额',
              prefixText: '¥',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        SizedBox(
          width: 40,
          child: IconButton(
            tooltip: '删除这一笔',
            visualDensity: VisualDensity.compact,
            onPressed: canRemove ? onRemove : null,
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
          ),
        ),
      ],
    );
  }
}

class _ReceiptImagePicker extends StatelessWidget {
  const _ReceiptImagePicker({
    required this.imagePath,
    required this.onAdd,
    required this.onRemove,
  });

  final String? imagePath;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final path = imagePath?.trim();
    if (path == null || path.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.receipt_long_rounded, size: 18),
          label: const Text('上传凭证图片'),
        ),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: Image.file(
              File(path),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 48,
                  height: 48,
                  color: colorScheme.surfaceContainer,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, size: 20),
                );
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              p.basename(path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          IconButton(
            tooltip: '更换凭证',
            visualDensity: VisualDensity.compact,
            onPressed: onAdd,
            icon: const Icon(Icons.swap_horiz_rounded, size: 20),
          ),
          IconButton(
            tooltip: '移除凭证',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _ExpenseRowControllers {
  _ExpenseRowControllers({required this.name, required this.amount});

  factory _ExpenseRowControllers.fromItem(ExpenseLineItem item) {
    return _ExpenseRowControllers(
      name: TextEditingController(text: item.name),
      amount: TextEditingController(
        text: item.amount == 0 ? '' : _formatAmount(item.amount),
      ),
    );
  }

  factory _ExpenseRowControllers.empty() {
    return _ExpenseRowControllers(
      name: TextEditingController(),
      amount: TextEditingController(),
    );
  }

  final TextEditingController name;
  final TextEditingController amount;

  void dispose() {
    name.dispose();
    amount.dispose();
  }

  static String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
    return amount.toStringAsFixed(2);
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
                color: theme.colorScheme.onSurfaceVariant,
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

  static _TypeMeta from(ParsedInputType type, {Color? primary}) =>
      switch (type) {
        ParsedInputType.memo => _TypeMeta(
          '备忘',
          Icons.edit_note_rounded,
          primary ?? AppColors.primary,
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
