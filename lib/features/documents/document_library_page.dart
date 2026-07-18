import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/local_database.dart';
import '../../core/database/repository_providers.dart';
import '../../core/documents/document_library_service.dart';
import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/markdown_document_parser.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../long_note/widgets/markdown_reader.dart';
import '../restore/markdown_restore_dialog.dart';
import '../restore/markdown_restore_service.dart';

enum _LibraryView { notes, documents, favorites, folders }

const _visibleNoteCount = 7;

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
  var _restoring = false;

  @override
  void initState() {
    super.initState();
    final service = ref.read(documentLibraryServiceProvider);
    final cachedSnapshot = service.cachedSnapshot;
    if (cachedSnapshot == null) {
      _snapshotFuture = _load();
      unawaited(
        _snapshotFuture.then((_) {
          if (mounted) unawaited(_refreshInBackground());
        }),
      );
    } else {
      _snapshotFuture = Future.value(cachedSnapshot);
      unawaited(Future<void>.microtask(_refreshInBackground));
    }
  }

  Future<DocumentLibrarySnapshot> _load({bool forceRefresh = false}) {
    return ref
        .read(documentLibraryServiceProvider)
        .load(forceRefresh: forceRefresh);
  }

  void _refresh() {
    setState(() {
      _snapshotFuture = _load(forceRefresh: true);
    });
  }

  Future<void> _refreshInBackground() async {
    try {
      final snapshot = await _load(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _snapshotFuture = Future.value(snapshot);
      });
    } catch (_) {
      // Keep the cached library visible; manual refresh can surface errors.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('资料库', style: theme.textTheme.titleMedium),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '恢复资料',
            onPressed: _restoring ? null : _restoreFromCurrentFolder,
            icon: _restoring
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restore_rounded),
          ),
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
                                color: colors.onSurfaceVariant,
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
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<_LibraryView>(
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
                              value: _LibraryView.favorites,
                              icon: const Icon(Icons.bookmark_rounded),
                              label: Text('收藏夹 ${data.favoriteRecords.length}'),
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
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: switch (_view) {
                    _LibraryView.notes => _notesList(data.notes),
                    _LibraryView.documents =>
                      data.documents.isEmpty
                          ? _emptyState(_view)
                          : _itemList(data.documents),
                    _LibraryView.favorites => _favoriteRecordList(
                      data.favoriteRecords,
                    ),
                    _LibraryView.folders => _folderList(data.favoriteFolders),
                  },
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

  Widget _notesList(List<DocumentLibraryItem> notes) {
    if (notes.isEmpty) return _emptyState(_LibraryView.notes);
    final recent = notes.take(_visibleNoteCount).toList(growable: false);
    final archived = notes.skip(_visibleNoteCount).toList(growable: false);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      itemCount: recent.length + (archived.isEmpty ? 0 : 1),
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        if (index == recent.length) {
          return _NoteArchiveTile(
            count: archived.length,
            onTap: () => _openArchivedNotes(archived),
          );
        }
        final item = recent[index];
        return _LibraryItemTile(
          item: item,
          onTap: () => _openItem(item),
          onToggleFavorite: () => _toggleFavoriteNote(item),
        );
      },
    );
  }

  Widget _itemList(List<DocumentLibraryItem> items) {
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
          onToggleFavorite: item.isMarkdown
              ? () => _toggleFavoriteNote(item)
              : null,
          onDelete: item.isMarkdown ? null : () => _confirmDeleteDocument(item),
        );
      },
    );
  }

  Widget _favoriteRecordList(List<DocumentFavoriteRecord> records) {
    if (records.isEmpty) return _emptyState(_LibraryView.favorites);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      itemCount: records.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final record = records[index];
        return _FavoriteRecordTile(
          record: record,
          onTap: () => _openFavoriteRecord(record),
        );
      },
    );
  }

  Future<void> _openArchivedNotes(List<DocumentLibraryItem> notes) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _MarkdownItemListPage(
          title: '笔记收纳夹',
          items: notes,
          onFavoriteChanged: _refresh,
        ),
      ),
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
    final favorites = view == _LibraryView.favorites;
    final folders = view == _LibraryView.folders;
    return _LibraryMessage(
      icon: folders
          ? Icons.folder_special_rounded
          : favorites
          ? Icons.bookmark_border_rounded
          : documents
          ? Icons.folder_open_rounded
          : Icons.notes_rounded,
      title: folders
          ? '还没有收藏文件夹'
          : favorites
          ? '还没有日常收藏'
          : documents
          ? '还没有导入文档'
          : '还没有 Markdown 笔记',
      message: folders
          ? '收藏常用资料文件夹后，可以直接从这里进入并打开里面的文件。'
          : favorites
          ? '日常记录标记为收藏后会出现在这里，项目里的收藏不会混进来。'
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
          _snapshotFuture = _load(forceRefresh: true);
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
          _snapshotFuture = _load(forceRefresh: true);
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

  Future<void> _restoreFromCurrentFolder() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      final settings = ref.read(appSettingsRepositoryProvider);
      final directoryService = MarkdownDirectoryService(settings);
      final restoreService = MarkdownRestoreService(
        source: StorageMarkdownRestoreSource(
          directoryService: directoryService,
        ),
        database: ref.read(localDatabaseProvider),
        recordsRepository: ref.read(recordsRepositoryProvider),
        settingsRepository: settings,
      );
      final preview = await restoreService.preview();
      if (!mounted) return;
      if (preview.isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('当前资料夹没有可恢复的备份'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 1),
            ),
          );
        return;
      }
      final restored = await showMarkdownRestoreDialog(
        context: context,
        restoreService: restoreService,
        preview: preview,
      );
      if (!mounted) return;
      if (restored) {
        ref
            .read(dataVersionProvider.notifier)
            .increment(domains: DataDomain.values.toSet());
        setState(() {
          _snapshotFuture = _load(forceRefresh: true);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('恢复失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _restoring = false);
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
              item: item,
              title: parsed.title.isEmpty ? item.name : parsed.title,
              body: parsed.body.isEmpty ? raw : parsed.body,
              onFavoriteChanged: _refresh,
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

  Future<void> _openFavoriteRecord(DocumentFavoriteRecord record) async {
    if (record.isMarkdown) {
      final relativePath =
          record.relativePath ?? record.fileName ?? record.title;
      await _openItem(
        DocumentLibraryItem(
          kind: LibraryItemKind.markdown,
          name: record.fileName ?? record.title,
          relativePath: relativePath,
          location: record.location!,
          mimeType: 'text/markdown',
          updatedAt: record.createdAt,
          isFavorite: record.isLibraryNoteFavorite,
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _FavoriteRecordSheet(record: record),
    );
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
        _snapshotFuture = _load(forceRefresh: true);
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

  Future<void> _toggleFavoriteNote(DocumentLibraryItem item) async {
    try {
      final nextFavorite = !item.isFavorite;
      await ref
          .read(documentLibraryServiceProvider)
          .setFavoriteNote(item: item, favorite: nextFavorite);
      if (!mounted) return;
      setState(() {
        _snapshotFuture = _load(forceRefresh: true);
        if (nextFavorite) _view = _LibraryView.favorites;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(nextFavorite ? '已收藏 ${item.name}' : '已取消收藏'),
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
            content: Text('收藏失败：$e'),
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
      _snapshotFuture = _load(forceRefresh: true);
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

class _NoteArchiveTile extends StatelessWidget {
  const _NoteArchiveTile({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      leading: CircleAvatar(
        backgroundColor: colors.onSurfaceVariant.withAlpha(20),
        child: Icon(
          Icons.inventory_2_outlined,
          color: colors.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(
        '收纳夹',
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '$count 条较早笔记',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: colors.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

class _FavoriteRecordTile extends StatelessWidget {
  const _FavoriteRecordTile({required this.record, required this.onTap});

  final DocumentFavoriteRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      leading: CircleAvatar(
        backgroundColor: AppColors.focus.withAlpha(22),
        child: Icon(
          record.isMarkdown ? Icons.article_outlined : Icons.bookmark_rounded,
          color: AppColors.focus,
          size: 20,
        ),
      ),
      title: Text(
        record.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        _favoriteRecordSubtitle(record),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: colors.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

class _FavoriteRecordSheet extends StatelessWidget {
  const _FavoriteRecordSheet({required this.record});

  final DocumentFavoriteRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _formatRecordDate(record.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              record.content.isEmpty ? record.title : record.content,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkdownItemListPage extends ConsumerWidget {
  const _MarkdownItemListPage({
    required this.title,
    required this.items,
    required this.onFavoriteChanged,
  });

  final String title;
  final List<DocumentLibraryItem> items;
  final VoidCallback onFavoriteChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          itemCount: items.length,
          separatorBuilder: (context, index) =>
              const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) {
            final item = items[index];
            return _LibraryItemTile(
              item: item,
              onTap: () => _openMarkdownItem(context, ref, item),
              onToggleFavorite: () => _toggleFavoriteNote(context, ref, item),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openMarkdownItem(
    BuildContext context,
    WidgetRef ref,
    DocumentLibraryItem item,
  ) async {
    try {
      final raw = await ref
          .read(documentLibraryServiceProvider)
          .readMarkdown(item);
      if (!context.mounted) return;
      final parsed = parseMarkdownDocument(raw, fallbackTitle: item.name);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _MarkdownLibraryReaderPage(
            item: item,
            title: parsed.title.isEmpty ? item.name : parsed.title,
            body: parsed.body.isEmpty ? raw : parsed.body,
            onFavoriteChanged: onFavoriteChanged,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
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

  Future<void> _toggleFavoriteNote(
    BuildContext context,
    WidgetRef ref,
    DocumentLibraryItem item,
  ) async {
    try {
      final nextFavorite = !item.isFavorite;
      await ref
          .read(documentLibraryServiceProvider)
          .setFavoriteNote(item: item, favorite: nextFavorite);
      onFavoriteChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(nextFavorite ? '已收藏 ${item.name}' : '已取消收藏'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('收藏失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }
}

String _favoriteRecordSubtitle(DocumentFavoriteRecord record) {
  final parts = <String>[_formatRecordDate(record.createdAt)];
  final path = record.relativePath;
  if (path != null && path.isNotEmpty) parts.add(path);
  return parts.join(' · ');
}

String _formatRecordDate(int millis) {
  if (millis <= 0) return '未知时间';
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
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
    final colors = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      leading: CircleAvatar(
        backgroundColor: colors.primary.withAlpha(22),
        child: Icon(
          Icons.folder_special_rounded,
          color: colors.primary,
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
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
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
          Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
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
    this.onToggleFavorite,
    this.onDelete,
  });

  final DocumentLibraryItem item;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = item.isMarkdown ? colors.primary : AppColors.secondary;

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
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      trailing: item.isMarkdown
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: item.isFavorite ? '取消收藏' : '收藏笔记',
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    item.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 20,
                    color: item.isFavorite ? AppColors.focus : null,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '删除',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
                Icon(Icons.open_in_new_rounded, color: colors.onSurfaceVariant),
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
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: colors.onSurfaceVariant.withAlpha(90)),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
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

class _MarkdownLibraryReaderPage extends ConsumerStatefulWidget {
  const _MarkdownLibraryReaderPage({
    required this.item,
    required this.title,
    required this.body,
    required this.onFavoriteChanged,
  });

  final DocumentLibraryItem item;
  final String title;
  final String body;
  final VoidCallback onFavoriteChanged;

  @override
  ConsumerState<_MarkdownLibraryReaderPage> createState() =>
      _MarkdownLibraryReaderPageState();
}

class _MarkdownLibraryReaderPageState
    extends ConsumerState<_MarkdownLibraryReaderPage> {
  late var _isFavorite = widget.item.isFavorite;
  var _savingFavorite = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _isFavorite ? '取消收藏' : '收藏笔记',
            onPressed: _savingFavorite ? null : _toggleFavorite,
            icon: _savingFavorite
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _isFavorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: _isFavorite ? AppColors.focus : null,
                  ),
          ),
        ],
      ),
      body: MarkdownReader(text: widget.body),
    );
  }

  Future<void> _toggleFavorite() async {
    setState(() => _savingFavorite = true);
    try {
      final nextFavorite = !_isFavorite;
      await ref
          .read(documentLibraryServiceProvider)
          .setFavoriteNote(
            item: widget.item.copyWith(isFavorite: _isFavorite),
            favorite: nextFavorite,
          );
      if (!mounted) return;
      setState(() => _isFavorite = nextFavorite);
      widget.onFavoriteChanged();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(nextFavorite ? '已收藏 ${widget.item.name}' : '已取消收藏'),
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
            content: Text('收藏失败：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }
}
