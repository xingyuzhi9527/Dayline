import 'package:flutter/material.dart';

import '../../core/markdown/markdown_directory_service.dart';
import '../../core/theme/app_colors.dart';

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

class _MarkdownDirectoryDialog extends StatelessWidget {
  const _MarkdownDirectoryDialog({required this.dirService});

  final MarkdownDirectoryService dirService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('设置笔记保存位置'),
      content: Text(
        'Liflow 会把每日复盘和长笔记保存为 Markdown 文件，方便以后形成你的个人数据库。',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.ink,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('暂不设置'),
        ),
        FilledButton(
          onPressed: () async {
            await dirService.useDefaultRoot();
            if (context.mounted) Navigator.of(context).pop(true);
          },
          child: const Text('使用默认目录'),
        ),
      ],
    );
  }
}
