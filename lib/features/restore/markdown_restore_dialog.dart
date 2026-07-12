import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'markdown_restore_service.dart';

Future<bool> showMarkdownRestoreDialog({
  required BuildContext context,
  required MarkdownRestoreService restoreService,
  RestorePreview? preview,
}) async {
  final resolvedPreview = preview ?? await restoreService.preview();
  if (!context.mounted || resolvedPreview.isEmpty) return false;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _MarkdownRestoreDialog(
      restoreService: restoreService,
      preview: resolvedPreview,
    ),
  );
  return result ?? false;
}

class _MarkdownRestoreDialog extends StatefulWidget {
  const _MarkdownRestoreDialog({
    required this.restoreService,
    required this.preview,
  });

  final MarkdownRestoreService restoreService;
  final RestorePreview preview;

  @override
  State<_MarkdownRestoreDialog> createState() => _MarkdownRestoreDialogState();
}

class _MarkdownRestoreDialogState extends State<_MarkdownRestoreDialog> {
  var _restoring = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sourceLabel = widget.preview.fromSnapshot ? '结构化备份快照' : 'Markdown 资料';
    final description = widget.preview.fromSnapshot
        ? '这个文件夹里有 Liflow 的完整备份快照，可以优先恢复记录、待办、项目、设置及其他结构化数据。恢复前不会改动原文件夹。'
        : '这个文件夹里有 Liflow 以前写下的 Markdown，可以先恢复到本机数据库。恢复前不会改动原文件。';

    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.primary.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.restore_rounded, color: colors.primary, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '发现$sourceLabel',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _PreviewRow(label: '记录', value: widget.preview.dailyNotes),
            if (!widget.preview.fromSnapshot)
              _PreviewRow(label: '长笔记', value: widget.preview.longNotes),
            _PreviewRow(label: '待办', value: widget.preview.todos),
            _PreviewRow(label: '项目档案', value: widget.preview.projects),
            if (widget.preview.projectFiles > 0)
              _PreviewRow(label: '项目文件', value: widget.preview.projectFiles),
            if (widget.preview.fromSnapshot)
              _PreviewRow(label: '设置', value: widget.preview.settings),
            if (widget.preview.structuredData > 0)
              _PreviewRow(
                label: '其他结构化数据',
                value: widget.preview.structuredData,
              ),
            if (widget.preview.mediaAttachmentsUnavailable > 0 ||
                widget.preview.projectFilesUnavailable > 0)
              Text(
                '有部分文件无法自动恢复，可稍后从原资料夹重新导入。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _restoring ? null : () => Navigator.of(context).pop(false),
          child: const Text('先不恢复'),
        ),
        FilledButton.icon(
          onPressed: _restoring ? null : _restore,
          icon: _restoring
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.restore_rounded, size: 18),
          label: const Text('恢复资料'),
        ),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    );
  }

  Future<void> _restore() async {
    setState(() {
      _restoring = true;
      _errorText = null;
    });
    try {
      final result = await widget.restoreService.restore();
      if (!mounted) return;
      final sourceLabel = result.fromSnapshot ? '快照' : 'Markdown';
      final structuredText = result.structuredDataRestored > 0
          ? '，其他结构化数据 ${result.structuredDataRestored} 条'
          : '';
      final unavailable =
          result.mediaAttachmentsUnavailable + result.projectFilesUnavailable;
      final unavailableText = unavailable > 0 ? '，$unavailable 个文件需手动补回' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已从$sourceLabel恢复 ${result.recordsRestored} 条记录、'
            '${result.todosRestored} 个待办、${result.projectsRestored} 个项目'
            '$structuredText$unavailableText',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = '恢复失败：$e';
        _restoring = false;
      });
    }
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            '$value',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
