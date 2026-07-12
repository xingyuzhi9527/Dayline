import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import '../../core/media/photo_moment_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

class PhotoMomentEditorPage extends ConsumerStatefulWidget {
  PhotoMomentEditorPage.create({required this.sourceImagePath, super.key})
    : recordId = null,
      sourceImagePaths = <String>[sourceImagePath],
      imagePath = sourceImagePath,
      imagePaths = <String>[sourceImagePath],
      cleanupSingleSource = true,
      initialNote = '',
      initialTags = const [],
      capturedAt = null;

  PhotoMomentEditorPage.createMultiple({
    required this.sourceImagePaths,
    super.key,
  }) : recordId = null,
       sourceImagePath = '',
       imagePath = sourceImagePaths.first,
       imagePaths = sourceImagePaths,
       cleanupSingleSource = false,
       initialNote = '',
       initialTags = const [],
       capturedAt = null;

  PhotoMomentEditorPage.edit({
    required this.recordId,
    required this.imagePath,
    required this.initialNote,
    required this.initialTags,
    List<String>? imagePaths,
    this.capturedAt,
    super.key,
  }) : sourceImagePath = '',
       sourceImagePaths = const [],
       cleanupSingleSource = false,
       imagePaths = imagePaths ?? <String>[imagePath];

  final int? recordId;
  final String sourceImagePath;
  final List<String> sourceImagePaths;
  final String imagePath;
  final List<String> imagePaths;
  final bool cleanupSingleSource;
  final String initialNote;
  final List<String> initialTags;
  final int? capturedAt;

  bool get isEditing => recordId != null;

  @override
  ConsumerState<PhotoMomentEditorPage> createState() =>
      _PhotoMomentEditorPageState();
}

class _PhotoMomentEditorPageState extends ConsumerState<PhotoMomentEditorPage> {
  late final TextEditingController _noteController;
  late final TextEditingController _tagsController;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.initialNote);
    _tagsController = TextEditingController(
      text: widget.initialTags.map((tag) => '#$tag').join(' '),
    );
  }

  @override
  void dispose() {
    _noteController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '图片片刻' : '拍照片刻'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(widget.isEditing ? '保存' : '完成'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.lg,
                ),
                children: [
                  _buildImagePreview(context),
                  const SizedBox(height: AppSpacing.md),
                  if (widget.capturedAt != null)
                    Text(
                      _formatCapturedAt(widget.capturedAt!),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (widget.capturedAt != null)
                    const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _noteController,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '一句说明',
                      hintText: '比如：今天的晚饭还不错',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _tagsController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: '标签',
                      hintText: '#生活 #饮食',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '图片会复制到 Liflow 根目录下的 attachments/photos 文件夹，不依赖系统相册原路径。',
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
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _buildBottomActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(BuildContext context) {
    if (widget.imagePaths.length > 1) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1,
        ),
        itemCount: widget.imagePaths.length,
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(widget.imagePaths[index]),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: const Text(
                        '鍥剧墖鍔犺浇澶辫触',
                        style: TextStyle(color: Colors.white70),
                      ),
                    );
                  },
                ),
                Positioned(
                  right: AppSpacing.xs,
                  top: AppSpacing.xs,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(150),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: 2,
                      ),
                      child: Text(
                        '${index + 1}/${widget.imagePaths.length}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withAlpha(32),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Image.file(
            File(widget.imagePath),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Text('图片加载失败', style: TextStyle(color: Colors.white70)),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).maybePop(),
                child: const Text('取消'),
              ),
            ),
            if (widget.isEditing) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('删除'),
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(widget.isEditing ? '保存' : '保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      final service = ref.read(photoMomentServiceProvider);
      final note = _noteController.text.trim();
      final tags = _parseTagInput(_tagsController.text);

      if (widget.isEditing) {
        await service.updatePhotoMoment(
          recordId: widget.recordId!,
          note: note,
          tags: tags,
        );
      } else {
        final sourcePaths = widget.sourceImagePaths;
        if (sourcePaths.length > 1 || !widget.cleanupSingleSource) {
          await service.createFromImageSelection(
            sourceImagePaths: sourcePaths,
            note: note,
            tags: tags,
          );
        } else {
          await service.createFromCameraCapture(
            sourceImagePath: widget.sourceImagePath.isNotEmpty
                ? widget.sourceImagePath
                : sourcePaths.single,
            note: note,
            tags: tags,
          );
        }
      }

      ref
          .read(dataVersionProvider.notifier)
          .increment(
            domains: widget.isEditing
                ? const {DataDomain.records}
                : const {DataDomain.records, DataDomain.media},
          );
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

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条图片片刻？'),
        content: const Text('删除后会进入回收站，图片文件会继续保留，直到彻底删除。'),
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

    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      await ref
          .read(photoMomentServiceProvider)
          .softDeletePhotoMoment(widget.recordId!);
      ref
          .read(dataVersionProvider.notifier)
          .increment(domains: const {DataDomain.records, DataDomain.media});
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = '删除失败：$e';
      });
    }
  }

  List<String> _parseTagInput(String raw) {
    return raw
        .split(RegExp(r'[\s,，、]+'))
        .map((tag) => tag.replaceFirst(RegExp(r'^[#＃]+'), '').trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  String _formatCapturedAt(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }
}
