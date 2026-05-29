import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../database/repositories.dart';
import '../database/repository_providers.dart';
import '../markdown/markdown_directory_service.dart';
import '../markdown/markdown_storage_service.dart';

final documentLibraryServiceProvider = Provider<DocumentLibraryService>((ref) {
  final settings = ref.watch(appSettingsRepositoryProvider);
  final dirService = MarkdownDirectoryService(settings);
  return DocumentLibraryService(
    settingsRepository: settings,
    directoryService: dirService,
    storageService: MarkdownStorageService(dirService),
  );
});

enum LibraryItemKind { markdown, document }

class DocumentLibraryItem {
  const DocumentLibraryItem({
    required this.kind,
    required this.name,
    required this.relativePath,
    required this.location,
    this.mimeType,
    this.sizeBytes,
    this.updatedAt,
  });

  final LibraryItemKind kind;
  final String name;
  final String relativePath;
  final String location;
  final String? mimeType;
  final int? sizeBytes;
  final int? updatedAt;

  bool get isMarkdown => kind == LibraryItemKind.markdown;
}

class DocumentLibrarySnapshot {
  const DocumentLibrarySnapshot({
    required this.rootLabel,
    required this.notes,
    required this.documents,
    required this.favoriteFolders,
  });

  final String rootLabel;
  final List<DocumentLibraryItem> notes;
  final List<DocumentLibraryItem> documents;
  final List<DocumentFavoriteFolder> favoriteFolders;
}

class DocumentFavoriteFolder {
  const DocumentFavoriteFolder({
    required this.id,
    required this.treeUri,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String treeUri;
  final String name;
  final int createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'treeUri': treeUri,
    'name': name,
    'createdAt': createdAt,
  };

  static DocumentFavoriteFolder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final treeUri = raw['treeUri'] as String?;
    if (treeUri == null || treeUri.isEmpty) return null;
    return DocumentFavoriteFolder(
      id: (raw['id'] as String?) ?? _folderId(treeUri),
      treeUri: treeUri,
      name: (raw['name'] as String?)?.trim().isNotEmpty == true
          ? (raw['name'] as String).trim()
          : '收藏文件夹',
      createdAt: raw['createdAt'] is num
          ? (raw['createdAt'] as num).toInt()
          : DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class DocumentLibraryService {
  DocumentLibraryService({
    required AppSettingsRepository settingsRepository,
    required MarkdownDirectoryService directoryService,
    required MarkdownStorageService storageService,
  }) : _settingsRepository = settingsRepository,
       _directoryService = directoryService,
       _storageService = storageService;

  static const _favoriteFoldersKey = 'document_favorite_folders';

  final AppSettingsRepository _settingsRepository;
  final MarkdownDirectoryService _directoryService;
  final MarkdownStorageService _storageService;

  Future<DocumentLibrarySnapshot> load() async {
    await _storageService.ensureCoreDirectories();
    final favoriteFolders = await _loadFavoriteFolders();
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri != null && treeUri.isNotEmpty && Platform.isAndroid) {
      return _loadTree(treeUri, favoriteFolders);
    }
    return _loadLocal(favoriteFolders);
  }

  Future<DocumentLibraryItem?> importDocument() async {
    await _storageService.ensureCoreDirectories();
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri != null && treeUri.isNotEmpty && Platform.isAndroid) {
      final row = await _storageService.importDocumentToTree();
      if (row == null) return null;
      return _itemFromTreeRow(treeUri, row, LibraryItemKind.document);
    }

    throw PlatformException(
      code: 'document_import_unsupported',
      message: 'Document import is currently available on Android.',
    );
  }

  Future<String> readMarkdown(DocumentLibraryItem item) {
    return _storageService.readTextFileLocation(item.location);
  }

  Future<void> openDocument(DocumentLibraryItem item) async {
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri != null && treeUri.isNotEmpty && Platform.isAndroid) {
      await _storageService.openTreeDocument(
        relativePath: item.relativePath,
        mimeType: item.mimeType,
      );
      return;
    }

    throw PlatformException(
      code: 'document_open_unsupported',
      message: 'System document opening is currently available on Android.',
    );
  }

  Future<void> deleteDocument(DocumentLibraryItem item) async {
    if (item.kind != LibraryItemKind.document ||
        !item.relativePath.startsWith('documents/')) {
      throw StateError('Only imported documents can be deleted here.');
    }

    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri != null && treeUri.isNotEmpty && Platform.isAndroid) {
      await _storageService.deleteTreeDocument(relativePath: item.relativePath);
      return;
    }

    final root = await _directoryService.ensureRoot();
    final file = File(_joinLocal(root, item.relativePath));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<DocumentFavoriteFolder?> addFavoriteFolder() async {
    final pick = await _storageService.pickDirectory();
    if (pick == null || pick.treeUri.isEmpty) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final folder = DocumentFavoriteFolder(
      id: _folderId(pick.treeUri),
      treeUri: pick.treeUri,
      name: pick.name?.trim().isNotEmpty == true ? pick.name!.trim() : '收藏文件夹',
      createdAt: now,
    );
    final current = await _loadFavoriteFolders();
    await _saveFavoriteFolders([
      folder,
      ...current.where((item) => item.id != folder.id),
    ]);
    return folder;
  }

  Future<void> removeFavoriteFolder(DocumentFavoriteFolder folder) async {
    final current = await _loadFavoriteFolders();
    await _saveFavoriteFolders(
      current.where((item) => item.id != folder.id).toList(growable: false),
    );
  }

  Future<List<DocumentLibraryItem>> loadFavoriteFolderFiles(
    DocumentFavoriteFolder folder,
  ) async {
    final rows = await _storageService.listFilesInTree(treeUri: folder.treeUri);
    final items = <DocumentLibraryItem>[];
    for (final row in rows) {
      final relativePath = row['relativePath'] as String? ?? '';
      if (relativePath.isEmpty) continue;
      final name = row['name'] as String? ?? p.posix.basename(relativePath);
      final size = row['sizeBytes'];
      final updatedAt = row['updatedAt'];
      items.add(
        DocumentLibraryItem(
          kind: _isMarkdownPath(relativePath)
              ? LibraryItemKind.markdown
              : LibraryItemKind.document,
          name: name,
          relativePath: relativePath,
          location: MarkdownStorageLocation.documentTree(
            treeUri: folder.treeUri,
            relativePath: relativePath,
          ).serialize(),
          mimeType: row['mimeType'] as String? ?? _mimeTypeForPath(name),
          sizeBytes: size is num ? size.toInt() : null,
          updatedAt: updatedAt is num ? updatedAt.toInt() : null,
        ),
      );
    }
    return _sortItems(items);
  }

  Future<void> openFavoriteFolderDocument({
    required DocumentFavoriteFolder folder,
    required DocumentLibraryItem item,
  }) {
    return _storageService.openDocumentInTree(
      treeUri: folder.treeUri,
      relativePath: item.relativePath,
      mimeType: item.mimeType,
    );
  }

  Future<DocumentLibrarySnapshot> _loadTree(
    String treeUri,
    List<DocumentFavoriteFolder> favoriteFolders,
  ) async {
    final rows = await _storageService.listTreeFiles(
      roots: const ['daily', 'notes', 'projects', 'documents'],
    );
    final notes = <DocumentLibraryItem>[];
    final documents = <DocumentLibraryItem>[];

    for (final row in rows) {
      final relativePath = row['relativePath'] as String? ?? '';
      if (relativePath.isEmpty) continue;
      final isMarkdown =
          relativePath.startsWith('daily/') ||
          relativePath.startsWith('notes/') ||
          relativePath.startsWith('projects/');
      final item = _itemFromTreeRow(
        treeUri,
        row,
        isMarkdown ? LibraryItemKind.markdown : LibraryItemKind.document,
      );
      if (isMarkdown && _isMarkdownPath(relativePath)) {
        notes.add(item);
      } else if (relativePath.startsWith('documents/')) {
        documents.add(item);
      }
    }

    return DocumentLibrarySnapshot(
      rootLabel: 'Liflow',
      notes: _sortItems(notes),
      documents: _sortItems(documents),
      favoriteFolders: favoriteFolders,
    );
  }

  Future<DocumentLibrarySnapshot> _loadLocal(
    List<DocumentFavoriteFolder> favoriteFolders,
  ) async {
    final root = await _directoryService.ensureRoot();
    final notes = <DocumentLibraryItem>[];
    final documents = <DocumentLibraryItem>[];

    for (final dirName in const ['daily', 'notes', 'projects']) {
      final dir = Directory(p.join(root, dirName));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !_isMarkdownPath(entity.path)) continue;
        final stat = await entity.stat();
        final relativePath = _relativePath(root, entity.path);
        notes.add(
          DocumentLibraryItem(
            kind: LibraryItemKind.markdown,
            name: p.basename(entity.path),
            relativePath: relativePath,
            location: MarkdownStorageLocation.local(entity.path).serialize(),
            mimeType: 'text/markdown',
            sizeBytes: stat.size,
            updatedAt: stat.modified.millisecondsSinceEpoch,
          ),
        );
      }
    }

    final documentsDir = Directory(p.join(root, 'documents'));
    if (await documentsDir.exists()) {
      await for (final entity in documentsDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        documents.add(
          DocumentLibraryItem(
            kind: LibraryItemKind.document,
            name: p.basename(entity.path),
            relativePath: _relativePath(root, entity.path),
            location: entity.path,
            mimeType: _mimeTypeForPath(entity.path),
            sizeBytes: stat.size,
            updatedAt: stat.modified.millisecondsSinceEpoch,
          ),
        );
      }
    }

    return DocumentLibrarySnapshot(
      rootLabel: root,
      notes: _sortItems(notes),
      documents: _sortItems(documents),
      favoriteFolders: favoriteFolders,
    );
  }

  DocumentLibraryItem _itemFromTreeRow(
    String treeUri,
    Map<String, Object?> row,
    LibraryItemKind kind,
  ) {
    final relativePath = row['relativePath'] as String? ?? '';
    final name = row['name'] as String? ?? p.posix.basename(relativePath);
    final size = row['sizeBytes'];
    final updatedAt = row['updatedAt'];
    return DocumentLibraryItem(
      kind: kind,
      name: name,
      relativePath: relativePath,
      location: MarkdownStorageLocation.documentTree(
        treeUri: treeUri,
        relativePath: relativePath,
      ).serialize(),
      mimeType: row['mimeType'] as String?,
      sizeBytes: size is num ? size.toInt() : null,
      updatedAt: updatedAt is num ? updatedAt.toInt() : null,
    );
  }

  List<DocumentLibraryItem> _sortItems(List<DocumentLibraryItem> items) {
    return [...items]..sort((a, b) {
      final timeCompare = (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0);
      if (timeCompare != 0) return timeCompare;
      return a.name.compareTo(b.name);
    });
  }

  bool _isMarkdownPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  String _relativePath(String root, String filePath) {
    final relative = p.relative(filePath, from: root);
    return p.split(relative).join('/');
  }

  String _joinLocal(String root, String relativePath) {
    final normalized = p.posix.normalize(relativePath).replaceAll('\\', '/');
    if (p.posix.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw ArgumentError('Unsafe document path: $relativePath');
    }
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList();
    return p.joinAll([root, ...segments]);
  }

  String? _mimeTypeForPath(String path) {
    final ext = p.extension(path).toLowerCase();
    return switch (ext) {
      '.pdf' => 'application/pdf',
      '.doc' => 'application/msword',
      '.docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.txt' => 'text/plain',
      '.md' => 'text/markdown',
      _ => null,
    };
  }

  Future<List<DocumentFavoriteFolder>> _loadFavoriteFolders() async {
    final row = await _settingsRepository.findByKey(_favoriteFoldersKey);
    final raw = row?['value'] as String?;
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final folders = decoded
          .map(DocumentFavoriteFolder.fromJson)
          .whereType<DocumentFavoriteFolder>()
          .toList(growable: false);
      return [...folders]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveFavoriteFolders(
    List<DocumentFavoriteFolder> folders,
  ) async {
    final value = jsonEncode(
      folders.map((folder) => folder.toJson()).toList(growable: false),
    );
    final existing = await _settingsRepository.findByKey(_favoriteFoldersKey);
    if (existing != null) {
      await _settingsRepository.update(_favoriteFoldersKey, value);
    } else {
      await _settingsRepository.create(key: _favoriteFoldersKey, value: value);
    }
  }
}

String _folderId(String treeUri) => base64Url.encode(utf8.encode(treeUri));
