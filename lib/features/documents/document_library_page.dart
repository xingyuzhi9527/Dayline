import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/documents/document_library_service.dart';
import '../../core/markdown/markdown_document_parser.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../long_note/widgets/markdown_reader.dart';

enum _LibraryView { notes, documents, folders }

class DocumentLibraryPage extends ConsumerStatefulWidget {
  const DocumentLibraryPage({super.key});

  @override
  ConsumerState<DocumentLibraryPage> createState() =>
      _DocumentLibraryPageState();
}

class _DocumentLibraryPageState extends ConsumerState<DocumentLibraryPage> {
  late Future<DocumentLibrarySnapshot> _snapshotFuture;
  var _view = _LibraryView.notes;
  var _importing = false;
  var _addingFolder = false;

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
            tooltip: '收藏文件夹',
            onPressed: _addingFolder ? null : _addFavoriteFolder,
            icon: _addingFolder
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.create_new_folder_rounded),
          ),
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
            final items = _view == _LibraryView.documents
                ? data.documents
                : data.notes;
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
                      SegmentedButton<_LibraryView>(
                        segments: [
                          ButtonSegment<_LibraryView>(
                            value: _LibraryView.notes,
                            icon: const Icon(Icons.notes_rounded),
                            label: Text('笔记 ${data.notes.length}'),
                          ),
                          ButtonSegment<_LibraryView>(
                            value: _LibraryView.documents,
                            icon: const Icon(Icons.folder_rounded),
                            label: Text('文档 ${data.documents.length}'),
                          ),
                          ButtonSegment<_LibraryView>(
                            value: _LibraryView.folders,
                            icon: const Icon(Icons.folder_special_rounded),
                            label: Text('文件夹 ${data.favoriteFolders.length}'),
                          ),
                        ],
                        selected: {_view},
                        onSelectionChanged: (value) {
                          setState(() => _view = value.single);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _view == _LibraryView.folders
                      ? _folderList(data.favoriteFolders)
                      : items.isEmpty
                      ? _emptyState(_view)
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
                              onDelete: item.isMarkdown
                                  ? null
                                  : () => _confirmDeleteDocument(item),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: _view == _LibraryView.documents
          ? FloatingActionButton.extended(
              onPressed: _importing ? null : _importDocument,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('导入'),
            )
          : _view == _LibraryView.folders
          ? FloatingActionButton.extended(
              onPressed: _addingFolder ? null : _addFavoriteFolder,
              icon: const Icon(Icons.create_new_folder_rounded),
              label: const Text('收藏'),
            )
          : null,
    );
  }

  Widget _folderList(List<DocumentFavoriteFolder> folders) {
    if (folders.isEmpty) return _emptyState(_LibraryView.folders);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      itemCount: folders.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final folder = folders[index];
        return _FavoriteFolderTile(
          folder: folder,
          onTap: () => _openFavoriteFolder(folder),
          onRemove: () => _confirmRemoveFavoriteFolder(folder),
        );
      },
    );
  }

  Widget _emptyState(_LibraryView view) {
    final documents = view == _LibraryView.documents;
    final folders = view == _LibraryView.folders;
    return _LibraryMessage(
      icon: folders
          ? Icons.folder_special_rounded
          : documents
          ? Icons.folder_open_rounded
          : Icons.notes_rounded,
      title: folders
          ? '还没有收藏文件夹'
          : documents
          ? '还没有导入文档'
          : '还没有 Markdown 笔记',
      message: folders
          ? '收藏常用资料文件夹后，可以直接从这里进入并打开里面的文件。'
          : documents
          ? '导入后的 PDF、Word 和其他文件会复制到 Liflow/documents。'
          : '生成日记或保存长笔记后，它们会出现在这里。',
      actionLabel: folders
          ? '收藏文件夹'
          : documents
          ? '导入文档'
          : null,
      onAction: folders
          ? _addFavoriteFolder
          : documents
          ? _importDocument
          : null,
    );
  }

  Future<void> _addFavoriteFolder() async {
    if (_addingFolder) return;
    setState(() => _addingFolder = true);
    try {
      final folder = await ref
          .read(documentLibraryServiceProvider)
          .addFavoriteFolder();
      if (!mounted) return;
      if (folder != null) {
        setState(() {
          _view = _LibraryView.folders;
          _snapshotFuture = _load();
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('已收藏 ${folder.name}'),
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
            content: Text('收藏文件夹失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _addingFolder = false);
    }
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
          _view = _LibraryView.documents;
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

  Future<void> _confirmDeleteDocument(DocumentLibraryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除资料库文档？'),
        content: Text('会删除 Liflow/documents 里的副本，不会删除原始文件。\n\n${item.name}'),
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
    if (confirmed != true) return;

    try {
      await ref.read(documentLibraryServiceProvider).deleteDocument(item);
      if (!mounted) return;
      setState(() {
        _view = _LibraryView.documents;
        _snapshotFuture = _load();
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('已删除 ${item.name}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('删除失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _confirmRemoveFavoriteFolder(
    DocumentFavoriteFolder folder,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除收藏文件夹？'),
        content: Text('只会从资料库移除这个入口，不会删除文件夹里的文件。\n\n${folder.name}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(documentLibraryServiceProvider).removeFavoriteFolder(folder);
    if (!mounted) return;
    setState(() {
      _view = _LibraryView.folders;
      _snapshotFuture = _load();
    });
  }

  Future<void> _openFavoriteFolder(DocumentFavoriteFolder folder) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _FavoriteFolderBrowserPage(folder: folder),
      ),
    );
  }
}

class _FavoriteFolderTile extends StatelessWidget {
  const _FavoriteFolderTile({
    required this.folder,
    required this.onTap,
    required this.onRemove,
  });

  final DocumentFavoriteFolder folder;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withAlpha(22),
        child: const Icon(
          Icons.folder_special_rounded,
          color: AppColors.primary,
          size: 20,
        ),
      ),
      title: Text(
        folder.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '文件夹收藏',
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '移除收藏',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.bookmark_remove_outlined, size: 20),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _FavoriteFolderBrowserPage extends ConsumerStatefulWidget {
  const _FavoriteFolderBrowserPage({required this.folder});

  final DocumentFavoriteFolder folder;

  @override
  ConsumerState<_FavoriteFolderBrowserPage> createState() =>
      _FavoriteFolderBrowserPageState();
}

class _FavoriteFolderBrowserPageState
    extends ConsumerState<_FavoriteFolderBrowserPage> {
  late Future<List<DocumentLibraryItem>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _load();
  }

  Future<List<DocumentLibraryItem>> _load() {
    return ref
        .read(documentLibraryServiceProvider)
        .loadFavoriteFolderFiles(widget.folder);
  }

  void _refresh() {
    setState(() => _itemsFuture = _load());
  }

  Future<void> _openItem(DocumentLibraryItem item) async {
    try {
      await ref
          .read(documentLibraryServiceProvider)
          .openFavoriteFolderDocument(folder: widget.folder, item: item);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.folder.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<DocumentLibraryItem>>(
          future: _itemsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _LibraryMessage(
                icon: Icons.error_outline_rounded,
                title: '文件夹加载失败',
                message: '${snapshot.error}',
                actionLabel: '重试',
                onAction: _refresh,
              );
            }
            final items = snapshot.data ?? const <DocumentLibraryItem>[];
            if (items.isEmpty) {
              return _LibraryMessage(
                icon: Icons.folder_open_rounded,
                title: '这个文件夹里还没有文件',
                message: '刷新后仍为空时，可以检查系统文件夹授权是否仍然有效。',
                actionLabel: '刷新',
                onAction: _refresh,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
            );
          },
        ),
      ),
    );
  }
}

class _LibraryItemTile extends StatelessWidget {
  const _LibraryItemTile({
    required this.item,
    required this.onTap,
    this.onDelete,
  });

  final DocumentLibraryItem item;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

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
      trailing: item.isMarkdown
          ? const Icon(Icons.chevron_right_rounded, color: AppColors.muted)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '删除',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
                const Icon(Icons.open_in_new_rounded, color: AppColors.muted),
              ],
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
