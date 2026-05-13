import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import '../../core/markdown/markdown_filename.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'long_note_notifier.dart';
import 'widgets/markdown_toolbar.dart';

class LongNoteEditorPage extends ConsumerStatefulWidget {
  const LongNoteEditorPage({
    this.initialTitle,
    this.initialBody,
    this.existingPath,
    this.recordId,
    super.key,
  });

  final String? initialTitle;
  final String? initialBody;
  final String? existingPath;
  final int? recordId;

  @override
  ConsumerState<LongNoteEditorPage> createState() =>
      _LongNoteEditorPageState();
}

class _LongNoteEditorPageState extends ConsumerState<LongNoteEditorPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.existingPath != null;
    if (widget.initialTitle != null) {
      _titleController.text = widget.initialTitle!;
    }
    if (widget.initialBody != null) {
      _bodyController.text = widget.initialBody!;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final notifier = ref.read(longNoteProvider.notifier);
    notifier.updateTitle(_titleController.text);
    notifier.updateBody(_bodyController.text);

    if (_isEditMode && widget.existingPath != null) {
      // Overwrite existing file
      try {
        final file = File(widget.existingPath!);
        final now = DateTime.now();
        final title = _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : '${now.year}-${_pad(now.month)}-${_pad(now.day)} ${_pad(now.hour)}:${_pad(now.minute)}';
        // Update front matter timestamp
        final content = _buildContent(title, now);
        await file.writeAsString(content);
        // Update record index
        if (widget.recordId != null) {
          await ref.read(recordsRepositoryProvider).updateDetails(
                widget.recordId!,
                content: title,
                metadata: {
                  'path': widget.existingPath!,
                  'title': title,
                },
              );
          ref.read(dataVersionProvider.notifier).increment();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('已保存'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 1),
            ),
          );
        Navigator.of(context).pop(true);
        return;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('保存失败：$e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }
    }

    final saved = await notifier.save();
    if (!mounted) return;

    if (saved) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('已保存：${_filenamePreview()}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(longNoteProvider).errorMessage;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('保存失败：${error ?? '未知错误'}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<bool> _onWillPop() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty && body.isEmpty) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃这篇笔记？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  bool get _canSave {
    final state = ref.read(longNoteProvider);
    return (_titleController.text.trim().isNotEmpty ||
            _bodyController.text.trim().isNotEmpty) &&
        !state.isSaving;
  }

  String _filenamePreview() {
    final title = _titleController.text.trim();
    final now = DateTime.now();
    return MarkdownFilename.generate(
      now,
      title: title.isNotEmpty ? title : null,
      mode: MarkdownNamingMode.datetimeTitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(longNoteProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          leading: TextButton(
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('取消'),
          ),
          title: const Text('长笔记'),
          centerTitle: true,
          actions: [
            if (state.isSaving)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              TextButton(
                onPressed: _canSave ? _save : null,
                child: const Text('保存'),
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: TextField(
                controller: _titleController,
                onChanged: (_) => setState(() {}),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                decoration: const InputDecoration(
                  hintText: '笔记标题',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            MarkdownToolbar(controller: _bodyController),
            const Divider(height: 1),
            Expanded(
              child: TextField(
                controller: _bodyController,
                onChanged: (_) => setState(() {}),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.7,
                      fontFamily: 'monospace',
                      fontSize: 15,
                    ),
                decoration: const InputDecoration(
                  hintText: 'Markdown 正文…',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(AppSpacing.md),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.border),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '${_bodyController.text.length} 字',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.muted,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    _filenamePreview(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.muted,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildContent(String title, DateTime now) {
    final iso = now.toIso8601String();
    final body = _bodyController.text;
    return '---\n'
        'type: note\n'
        'source: liflow\n'
        'created_at: $iso\n'
        'updated_at: $iso\n'
        'title: $title\n'
        'tags: []\n'
        '---\n'
        '\n'
        '# $title\n'
        '\n'
        '$body\n';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
