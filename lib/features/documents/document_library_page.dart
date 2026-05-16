import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/documents/document_library_service.dart';
import '../../core/markdown/markdown_document_parser.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../long_note/widgets/markdown_reader.dart';

class DocumentLibraryPage extends ConsumerStatefulWidget {
  const DocumentLibraryPage({super.key});

  @override
  ConsumerState<DocumentLibraryPage> createState() =>
      _DocumentLibraryPageState();
}

class _DocumentLibraryPageState extends ConsumerState<DocumentLibraryPage> {
  late Future<DocumentLibrarySnapshot> _snapshotFuture;
  var _showDocuments = false;
  var _importing = false;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _load();
  }

  Future<DocumentLibrarySnapshot> _load() {
    return ref.read(documentLibraryServiceProvider).load();
  }

  void _refresh() {
    setState(() {
      _snapshotFuture = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('资料库', style: theme.textTheme.titleMedium),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '导入文档',
            onPressed: _importing ? null : _importDocument,
            icon: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<DocumentLibrarySnapshot>(
          future: _snapshotFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _LibraryMessage(
                icon: Icons.error_outline_rounded,
                title: '资料库加载失败',
                message: '${snapshot.error}',
                actionLabel: '重试',
                onAction: _refresh,
              );
            }

            final data = snapshot.data!;
            final items = _showDocuments ? data.documents : data.notes;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              data.rootLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '刷新',
                            visualDensity: VisualDensity.compact,
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment<bool>(
                            value: false,
                            icon: const Icon(Icons.notes_rounded),
                            label: Text('笔记 ${data.notes.length}'),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            icon: const Icon(Icons.folder_rounded),
                            label: Text('文档 ${data.documents.length}'),
                          ),
                        ],
                        selected: {_showDocuments},
                        onSelectionChanged: (value) {
                          setState(() => _showDocuments = value.single);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: items.isEmpty
                      ? _emptyState(_showDocuments)
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xs,
                          ),
                          itemCount: items.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1, indent: 72),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _LibraryItemTile(
                              item: item,
                              onTap: () => _openItem(item),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: _showDocuments
          ? FloatingActionButton.extended(
              onPressed: _importing ? null : _importDocument,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('导入'),
            )
          : null,
    );
  }

  Widget _emptyState(bool documents) {
    return _LibraryMessage(
      icon: documents ? Icons.folder_open_rounded : Icons.notes_rounded,
      title: documents ? '还没有导入文档' : '还没有 Markdown 笔记',
      message: documents
          ? '导入后的 PDF、Word 和其他文件会复制到 Liflow/documents。'
          : '生成日记或保存长笔记后，它们会出现在这里。',
      actionLabel: documents ? '导入文档' : null,
      onAction: documents ? _importDocument : null,
    );
  }

  Future<void> _importDocument() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final item = await ref
          .read(documentLibraryServiceProvider)
          .importDocument();
      if (!mounted) return;
      if (item != null) {
        setState(() {
          _showDocuments = true;
          _snapshotFuture = _load();
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('已导入 ${item.name}'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 1),
            ),
          );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('导入失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openItem(DocumentLibraryItem item) async {
    try {
      if (item.isMarkdown) {
        final raw = await ref
            .read(documentLibraryServiceProvider)
            .readMarkdown(item);
        if (!mounted) return;
        final parsed = parseMarkdownDocument(raw, fallbackTitle: item.name);
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => _MarkdownLibraryReaderPage(
              title: parsed.title.isEmpty ? item.name : parsed.title,
              body: parsed.body.isEmpty ? raw : parsed.body,
            ),
          ),
        );
        return;
      }

      await ref.read(documentLibraryServiceProvider).openDocument(item);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('打开失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }
}

class _LibraryItemTile extends StatelessWidget {
  const _LibraryItemTile({required this.item, required this.onTap});

  final DocumentLibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = item.isMarkdown ? AppColors.primary : AppColors.secondary;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      leading: CircleAvatar(
        backgroundColor: color.withAlpha(22),
        child: Icon(_iconForItem(item), color: color, size: 20),
      ),
      title: Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        _subtitleForItem(item),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
      ),
      trailing: Icon(
        item.isMarkdown
            ? Icons.chevron_right_rounded
            : Icons.open_in_new_rounded,
        color: AppColors.muted,
      ),
      onTap: onTap,
    );
  }

  IconData _iconForItem(DocumentLibraryItem item) {
    if (item.isMarkdown) return Icons.article_outlined;
    final lower = item.name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return Icons.description_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  String _subtitleForItem(DocumentLibraryItem item) {
    final parts = <String>[item.relativePath];
    if (item.sizeBytes != null && item.sizeBytes! > 0) {
      parts.add(_formatSize(item.sizeBytes!));
    }
    if (item.updatedAt != null && item.updatedAt! > 0) {
      parts.add(_formatDate(item.updatedAt!));
    }
    return parts.join(' · ');
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  String _formatDate(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$month-$day';
  }
}

class _LibraryMessage extends StatelessWidget {
  const _LibraryMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: AppColors.muted.withAlpha(90)),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MarkdownLibraryReaderPage extends StatelessWidget {
  const _MarkdownLibraryReaderPage({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: MarkdownReader(text: body),
    );
  }
}
