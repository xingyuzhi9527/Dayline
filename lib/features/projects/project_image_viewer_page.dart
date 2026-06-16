import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

class ProjectImageViewerItem {
  const ProjectImageViewerItem({required this.path});

  final String path;
}

enum ProjectImageViewerAction { rename, delete }

class ProjectImageViewerResult {
  const ProjectImageViewerResult._(this.action, this.title);

  factory ProjectImageViewerResult.rename(String title) {
    return ProjectImageViewerResult._(ProjectImageViewerAction.rename, title);
  }

  factory ProjectImageViewerResult.delete() {
    return const ProjectImageViewerResult._(
      ProjectImageViewerAction.delete,
      null,
    );
  }

  final ProjectImageViewerAction action;
  final String? title;
}

class ProjectImageViewerPage extends StatefulWidget {
  const ProjectImageViewerPage({
    required this.title,
    required this.images,
    this.requestRename,
    super.key,
  });

  final String title;
  final List<ProjectImageViewerItem> images;
  final Future<String?> Function(BuildContext context, String title)?
  requestRename;

  @override
  State<ProjectImageViewerPage> createState() => _ProjectImageViewerPageState();
}

class _ProjectImageViewerPageState extends State<ProjectImageViewerPage> {
  late final PageController _controller;
  var _index = 0;

  bool get _hasMultiple => widget.images.length > 1;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_hasMultiple)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: Text(
                  '${_index + 1} / ${widget.images.length}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: Colors.white),
                ),
              ),
            ),
          if (widget.requestRename != null)
            IconButton(
              tooltip: '修改名称',
              onPressed: () async {
                final nextTitle = await widget.requestRename!(
                  context,
                  widget.title,
                );
                if (nextTitle == null || nextTitle.trim().isEmpty) return;
                if (!context.mounted) return;
                Navigator.of(
                  context,
                ).pop(ProjectImageViewerResult.rename(nextTitle.trim()));
              },
              icon: const Icon(Icons.edit_rounded),
            ),
          IconButton(
            tooltip: '删除资料',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('删除这份图片资料？'),
                  content: const Text('会从项目最近更新移除，并删除对应图片文件。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) return;
              Navigator.of(context).pop(ProjectImageViewerResult.delete());
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) {
                return Center(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Image.file(
                      File(widget.images[index].path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.image_not_supported_rounded,
                        color: Colors.white70,
                        size: 48,
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_hasMultiple) ...[
              Positioned(
                left: AppSpacing.md,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton.filled(
                    tooltip: '上一张',
                    onPressed: _index == 0 ? null : () => _goTo(_index - 1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                ),
              ),
              Positioned(
                right: AppSpacing.md,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton.filled(
                    tooltip: '下一张',
                    onPressed: _index >= widget.images.length - 1
                        ? null
                        : () => _goTo(_index + 1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _goTo(int index) {
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }
}
