import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/markdown_storage_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

Future<bool> showMarkdownDirectoryDialog(
  BuildContext context,
  MarkdownDirectoryService dirService,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _MarkdownDirectoryDialog(dirService: dirService),
  );
  return result ?? false;
}

class _MarkdownDirectoryDialog extends StatefulWidget {
  const _MarkdownDirectoryDialog({required this.dirService});

  final MarkdownDirectoryService dirService;

  @override
  State<_MarkdownDirectoryDialog> createState() =>
      _MarkdownDirectoryDialogState();
}

class _MarkdownDirectoryDialogState extends State<_MarkdownDirectoryDialog> {
  var _picking = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storageService = MarkdownStorageService(widget.dirService);

    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.folder_special_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '设置 Liflow 笔记库',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
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
              'Liflow 会把日常记录和长笔记保存成 Markdown。默认结构是：\n'
              'Liflow/daily/年月/日期.md\n'
              'Liflow/notes/年月/时间_标题.md',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.ink,
                height: 1.55,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.secondaryContainer.withAlpha(60),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      Platform.isAndroid
                          ? '请在系统选择器里选中已有 Liflow 文件夹，或新建一个 Liflow 文件夹。选中后，应用会获得这个文件夹的读写授权。'
                          : '也可以先使用默认 Liflow 文件夹，之后在复盘页里重新设置存储位置。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.ink,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('稍后设置'),
        ),
        if (Platform.isAndroid)
          FilledButton.icon(
            onPressed: _picking ? null : () => _pickDirectory(storageService),
            icon: _picking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text('选择或新建 Liflow'),
          )
        else
          FilledButton.icon(
            onPressed: () async {
              await widget.dirService.useDefaultRoot();
              if (context.mounted) Navigator.of(context).pop(true);
            },
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('使用默认 Liflow'),
          ),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    );
  }

  Future<void> _pickDirectory(MarkdownStorageService storageService) async {
    setState(() => _picking = true);
    try {
      final treeUri = await storageService.pickDirectory();
      if (!mounted || treeUri == null || treeUri.isEmpty) return;
      await widget.dirService.setTreeRootUri(treeUri);
      if (context.mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }
}
