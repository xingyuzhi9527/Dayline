import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../database/repositories.dart';
import '../database/repository_providers.dart';
import '../markdown/markdown_directory_service.dart';
import '../markdown/markdown_storage_service.dart';
import '../performance/perf_trace.dart';

final documentLibraryServiceProvider = Provider<DocumentLibraryService>((ref) {
  final settings = ref.watch(appSettingsRepositoryProvider);
  final dirService = MarkdownDirectoryService(settings);
  return DocumentLibraryService(
    settingsRepository: settings,
    recordsRepository: ref.watch(recordsRepositoryProvider),
    libraryItemsRepository: ref.watch(libraryItemsRepositoryProvider),
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
    this.isFavorite = false,
  });

  final LibraryItemKind kind;
  final String name;
  final String relativePath;
  final String location;
  final String? mimeType;
  final int? sizeBytes;
  final int? updatedAt;
  final bool isFavorite;

  bool get isMarkdown => kind == LibraryItemKind.markdown;

  DocumentLibraryItem copyWith({bool? isFavorite}) {
    return DocumentLibraryItem(
      kind: kind,
      name: name,
      relativePath: relativePath,
      location: location,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      updatedAt: updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'name': name,
    'relativePath': relativePath,
    'location': location,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'updatedAt': updatedAt,
    'isFavorite': isFavorite,
  };

  static DocumentLibraryItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'] as String?;
    final relativePath = raw['relativePath'] as String?;
    final location = raw['location'] as String?;
    if (name == null || relativePath == null || location == null) return null;

    final kindValue = raw['kind'] as String?;
    final kind = kindValue == LibraryItemKind.document.name
        ? LibraryItemKind.document
        : LibraryItemKind.markdown;

    int? parseInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    return DocumentLibraryItem(
      kind: kind,
      name: name,
      relativePath: relativePath,
      location: location,
      mimeType: raw['mimeType'] as String?,
      sizeBytes: parseInt(raw['sizeBytes']),
      updatedAt: parseInt(raw['updatedAt']),
      isFavorite: raw['isFavorite'] == true,
    );
  }
}

class DocumentLibrarySnapshot {
  const DocumentLibrarySnapshot({
    required this.rootLabel,
    required this.notes,
    required this.documents,
    required this.favoriteRecords,
    required this.favoriteFolders,
  });

  final String rootLabel;
  final List<DocumentLibraryItem> notes;
  final List<DocumentLibraryItem> documents;
  final List<DocumentFavoriteRecord> favoriteRecords;
  final List<DocumentFavoriteFolder> favoriteFolders;

  Map<String, Object?> toJson() => {
    'rootLabel': rootLabel,
    'notes': notes.map((item) => item.toJson()).toList(growable: false),
    'documents': documents.map((item) => item.toJson()).toList(growable: false),
    'favoriteRecords': favoriteRecords
        .map((item) => item.toJson())
        .toList(growable: false),
    'favoriteFolders': favoriteFolders
        .map((item) => item.toJson())
        .toList(growable: false),
  };

  static DocumentLibrarySnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rootLabel = raw['rootLabel'] as String?;
    if (rootLabel == null || rootLabel.isEmpty) return null;
    return DocumentLibrarySnapshot(
      rootLabel: rootLabel,
      notes: DocumentLibraryService._itemsFromJson(raw['notes']),
      documents: DocumentLibraryService._itemsFromJson(raw['documents']),
      favoriteRecords: DocumentLibraryService._favoriteRecordsFromJson(
        raw['favoriteRecords'],
      ),
      favoriteFolders: DocumentLibraryService._favoriteFoldersFromJson(
        raw['favoriteFolders'],
      ),
    );
  }
}

class DocumentFavoriteRecord {
  const DocumentFavoriteRecord({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    this.location,
    this.relativePath,
    this.fileName,
    this.libraryFavoriteKey,
  });

  final int id;
  final String title;
  final String content;
  final int createdAt;
  final String? location;
  final String? relativePath;
  final String? fileName;
  final String? libraryFavoriteKey;

  bool get isMarkdown => location != null && location!.isNotEmpty;
  bool get isLibraryNoteFavorite => libraryFavoriteKey != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'createdAt': createdAt,
    'location': location,
    'relativePath': relativePath,
    'fileName': fileName,
    'libraryFavoriteKey': libraryFavoriteKey,
  };

  static DocumentFavoriteRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'] as String?;
    final content = raw['content'] as String?;
    if (title == null || content == null) return null;

    int? parseInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    return DocumentFavoriteRecord(
      id: parseInt(raw['id']) ?? 0,
      title: title,
      content: content,
      createdAt: parseInt(raw['createdAt']) ?? 0,
      location: raw['location'] as String?,
      relativePath: raw['relativePath'] as String?,
      fileName: raw['fileName'] as String?,
      libraryFavoriteKey: raw['libraryFavoriteKey'] as String?,
    );
  }
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
    required RecordsRepository recordsRepository,
    LibraryItemsRepository? libraryItemsRepository,
    required MarkdownDirectoryService directoryService,
    required MarkdownStorageService storageService,
  }) : _settingsRepository = settingsRepository,
       _recordsRepository = recordsRepository,
       _libraryItemsRepository = libraryItemsRepository,
       _directoryService = directoryService,
       _storageService = storageService;

  static const _favoriteFoldersKey = 'document_favorite_folders';
  static const _favoriteNotesKey = 'document_favorite_notes';
  static const _snapshotCacheKey = 'document_library_snapshot_v1';

  final AppSettingsRepository _settingsRepository;
  final RecordsRepository _recordsRepository;
  final LibraryItemsRepository? _libraryItemsRepository;
  final MarkdownDirectoryService _directoryService;
  final MarkdownStorageService _storageService;
  DocumentLibrarySnapshot? _cachedSnapshot;
  bool _snapshotCacheDirty = false;

  DocumentLibrarySnapshot? get cachedSnapshot => _cachedSnapshot;

  Future<DocumentLibrarySnapshot> load({bool forceRefresh = false}) {
    return PerfTrace.measure(
      'document_library.load force=$forceRefresh',
      () => _load(forceRefresh: forceRefresh),
    );
  }

  Future<DocumentLibrarySnapshot> _load({bool forceRefresh = false}) async {
    if (!forceRefresh && !_snapshotCacheDirty) {
      final cached = _cachedSnapshot;
      if (cached != null) return cached;
    }

    final favoriteFolders = await _loadFavoriteFolders();
    final favoriteNotes = await _loadFavoriteNotes();
    final recordRows = await _recordsRepository.findDocumentLibraryCandidates();
    final longNoteItems = _longNoteItemsFromRows(recordRows);
    final favoriteRecords = _mergeFavoriteRecords(
      _dailyFavoriteRecordsFromRows(recordRows),
      favoriteNotes,
    );

    if (!forceRefresh) {
      final indexed = await _loadIndexedSnapshot(
        favoriteFolders,
        favoriteNotes,
        longNoteItems,
        favoriteRecords,
      );
      if (indexed != null) {
        _cachedSnapshot = indexed;
        _snapshotCacheDirty = false;
        return indexed;
      }

      if (!_snapshotCacheDirty) {
        final persisted = await _loadPersistedSnapshot();
        if (persisted != null) {
          _cachedSnapshot = persisted;
          return persisted;
        }
      }
    }

    await _storageService.ensureCoreDirectories();
    final treeUri = await _directoryService.getTreeRootUri();
    late final DocumentLibrarySnapshot snapshot;
    if (treeUri != null && treeUri.isNotEmpty && Platform.isAndroid) {
      snapshot = await _loadTree(
        treeUri,
        favoriteFolders,
        favoriteNotes,
        longNoteItems,
        favoriteRecords,
      );
    } else {
      snapshot = await _loadLocal(
        favoriteFolders,
        favoriteNotes,
        longNoteItems,
        favoriteRecords,
      );
    }
    _cachedSnapshot = snapshot;
    _snapshotCacheDirty = false;
    await _saveIndexedSnapshot(snapshot);
    await _savePersistedSnapshot(snapshot);
    return snapshot;
  }

  Future<DocumentLibraryItem?> importDocument() async {
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri != null && treeUri.isNotEmpty && Platform.isAndroid) {
      final row = await _storageService.importDocumentToTree();
      if (row == null) return null;
      final item = _itemFromTreeRow(treeUri, row, LibraryItemKind.document);
      await _upsertIndexedItem(item);
      _invalidateCache();
      return item;
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
      await _deleteIndexedItem(item);
      _invalidateCache();
      return;
    }

    final root = await _directoryService.ensureRoot();
    final file = File(_joinLocal(root, item.relativePath));
    if (await file.exists()) {
      await file.delete();
    }
    await _deleteIndexedItem(item);
    _invalidateCache();
  }

  Future<void> setFavoriteNote({
    required DocumentLibraryItem item,
    required bool favorite,
  }) async {
    if (!item.isMarkdown) {
      throw StateError('Only Markdown notes can be favorited here.');
    }

    final current = await _loadFavoriteNotes();
    final key = _noteItemKey(item);
    if (!favorite) {
      await _saveFavoriteNotes(
        current.where((record) => record.libraryFavoriteKey != key).toList(),
      );
      await _upsertIndexedItem(item.copyWith(isFavorite: false));
      _invalidateCache();
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final record = DocumentFavoriteRecord(
      id: 0,
      title: _favoriteTitleForItem(item),
      content: '',
      createdAt: now,
      location: item.location,
      relativePath: item.relativePath,
      fileName: item.name,
      libraryFavoriteKey: key,
    );
    await _saveFavoriteNotes([
      record,
      ...current.where((item) => item.libraryFavoriteKey != key),
    ]);
    await _upsertIndexedItem(item.copyWith(isFavorite: true));
    _invalidateCache();
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
    _invalidateCache();
    return folder;
  }

  Future<void> removeFavoriteFolder(DocumentFavoriteFolder folder) async {
    final current = await _loadFavoriteFolders();
    await _saveFavoriteFolders(
      current.where((item) => item.id != folder.id).toList(growable: false),
    );
    _invalidateCache();
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
    List<DocumentFavoriteRecord> favoriteNotes,
    List<DocumentLibraryItem> longNoteItems,
    List<DocumentFavoriteRecord> favoriteRecords,
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
      notes: _markFavoriteNotes(_mergeNoteItems(notes, longNoteItems), [
        ...favoriteRecords,
        ...favoriteNotes,
      ]),
      documents: _sortItems(documents),
      favoriteRecords: favoriteRecords,
      favoriteFolders: favoriteFolders,
    );
  }

  Future<DocumentLibrarySnapshot> _loadLocal(
    List<DocumentFavoriteFolder> favoriteFolders,
    List<DocumentFavoriteRecord> favoriteNotes,
    List<DocumentLibraryItem> longNoteItems,
    List<DocumentFavoriteRecord> favoriteRecords,
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
      notes: _markFavoriteNotes(_mergeNoteItems(notes, longNoteItems), [
        ...favoriteRecords,
        ...favoriteNotes,
      ]),
      documents: _sortItems(documents),
      favoriteRecords: favoriteRecords,
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

  List<DocumentLibraryItem> _longNoteItemsFromRows(List<DatabaseRow> rows) {
    final items = <DocumentLibraryItem>[];
    for (final row in rows) {
      if (row['type'] != 'long_note' || row['is_deleted'] == 1) continue;
      final metadata = _decodeMetadata(row['metadata']);
      final location = _string(metadata['path']);
      if (location == null || location.isEmpty) continue;
      final relativePath =
          _string(metadata['relativePath']) ??
          _displayPathForLocation(location);
      final title = _string(metadata['title']) ?? _string(row['content']);
      final fileName =
          _string(metadata['fileName']) ??
          _basename(relativePath) ??
          title ??
          '长笔记.md';
      final updatedAt =
          _intValue(row['updated_at']) ?? _intValue(row['created_at']);
      items.add(
        DocumentLibraryItem(
          kind: LibraryItemKind.markdown,
          name: fileName,
          relativePath: relativePath ?? location,
          location: location,
          mimeType: 'text/markdown',
          updatedAt: updatedAt,
        ),
      );
    }
    return _sortItems(items);
  }

  List<DocumentFavoriteRecord> _dailyFavoriteRecordsFromRows(
    List<DatabaseRow> rows,
  ) {
    final favorites = <DocumentFavoriteRecord>[];
    for (final row in rows) {
      if (row['is_deleted'] == 1) continue;
      final metadata = _decodeMetadata(row['metadata']);
      final tags = _decodeTags(row['tags']);
      if (!_isDailyFavoriteRecord(metadata, tags)) continue;

      final content = _string(row['content']) ?? '';
      final title = _string(metadata['title']) ?? content;
      final location = _string(metadata['path']);
      final relativePath = location == null
          ? _string(metadata['relativePath'])
          : (_string(metadata['relativePath']) ??
                _displayPathForLocation(location));
      favorites.add(
        DocumentFavoriteRecord(
          id: _intValue(row['id']) ?? 0,
          title: title.trim().isEmpty ? '收藏记录' : title.trim(),
          content: content,
          createdAt: _intValue(row['created_at']) ?? 0,
          location: location,
          relativePath: relativePath,
          fileName: _string(metadata['fileName']),
        ),
      );
    }
    return favorites..sort((a, b) {
      final timeCompare = b.createdAt.compareTo(a.createdAt);
      if (timeCompare != 0) return timeCompare;
      return b.id.compareTo(a.id);
    });
  }

  List<DocumentLibraryItem> _mergeNoteItems(
    List<DocumentLibraryItem> scanned,
    List<DocumentLibraryItem> fromRecords,
  ) {
    final byKey = <String, DocumentLibraryItem>{};
    for (final item in [...scanned, ...fromRecords]) {
      byKey[_noteItemKey(item)] = item;
    }
    return _sortItems(byKey.values.toList(growable: false));
  }

  List<DocumentLibraryItem> _markFavoriteNotes(
    List<DocumentLibraryItem> notes,
    List<DocumentFavoriteRecord> favorites,
  ) {
    final favoriteKeys = favorites
        .where((record) => record.isMarkdown)
        .map(_favoriteRecordKey)
        .whereType<String>()
        .toSet();
    return [
      for (final item in notes)
        item.copyWith(isFavorite: favoriteKeys.contains(_noteItemKey(item))),
    ];
  }

  List<DocumentFavoriteRecord> _mergeFavoriteRecords(
    List<DocumentFavoriteRecord> records,
    List<DocumentFavoriteRecord> favoriteNotes,
  ) {
    final byKey = <String, DocumentFavoriteRecord>{};
    for (final record in [...favoriteNotes, ...records]) {
      byKey[_favoriteRecordKey(record) ?? 'record:${record.id}'] = record;
    }
    return byKey.values.toList(growable: false)..sort((a, b) {
      final timeCompare = b.createdAt.compareTo(a.createdAt);
      if (timeCompare != 0) return timeCompare;
      return b.id.compareTo(a.id);
    });
  }

  String _noteItemKey(DocumentLibraryItem item) {
    final location = item.location.trim();
    if (location.isNotEmpty) return 'location:$location';
    return 'relative:${item.relativePath}';
  }

  String? _favoriteRecordKey(DocumentFavoriteRecord record) {
    final explicit = record.libraryFavoriteKey;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final location = record.location?.trim();
    if (location != null && location.isNotEmpty) return 'location:$location';
    final relativePath = record.relativePath?.trim();
    if (relativePath != null && relativePath.isNotEmpty) {
      return 'relative:$relativePath';
    }
    return null;
  }

  String _favoriteTitleForItem(DocumentLibraryItem item) {
    final name = item.name.trim();
    final lower = name.toLowerCase();
    if (lower.endsWith('.md')) return name.substring(0, name.length - 3);
    if (lower.endsWith('.markdown')) {
      return name.substring(0, name.length - 9);
    }
    return name.isEmpty ? '收藏笔记' : name;
  }

  bool _isDailyFavoriteRecord(
    Map<String, Object?> metadata,
    List<String> tags,
  ) {
    if (_isProjectRecord(metadata)) return false;
    if (_truthy(metadata['favorite']) ||
        _truthy(metadata['isFavorite']) ||
        _truthy(metadata['is_favorite'])) {
      return true;
    }
    return tags.any((tag) {
      final normalized = tag.trim().toLowerCase();
      return normalized == '收藏' || normalized == 'favorite';
    });
  }

  bool _isProjectRecord(Map<String, Object?> metadata) {
    return _string(metadata['projectId']) != null ||
        _string(metadata['projectEntryType']) != null;
  }

  bool _truthy(Object? value) {
    if (value == true) return true;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  Map<String, Object?> _decodeMetadata(Object? raw) {
    if (raw is Map<String, Object?>) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return decoded.cast<String, Object?>();
      } catch (_) {}
    }
    return const {};
  }

  List<String> _decodeTags(Object? raw) {
    if (raw is List<String>) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        return decoded.whereType<String>().toList(growable: false);
      } catch (_) {}
    }
    return const [];
  }

  String? _displayPathForLocation(String location) {
    try {
      return MarkdownStorageService.displayPathForLocation(location);
    } catch (_) {
      return location;
    }
  }

  String? _basename(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    return p.posix.basename(path.replaceAll('\\', '/'));
  }

  String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
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

  void _invalidateCache() {
    _cachedSnapshot = null;
    _snapshotCacheDirty = true;
    unawaited(_deletePersistedSnapshot());
  }

  Future<DocumentLibrarySnapshot?> _loadIndexedSnapshot(
    List<DocumentFavoriteFolder> favoriteFolders,
    List<DocumentFavoriteRecord> favoriteNotes,
    List<DocumentLibraryItem> longNoteItems,
    List<DocumentFavoriteRecord> favoriteRecords,
  ) async {
    final indexRepository = _libraryItemsRepository;
    if (indexRepository == null) return null;

    final rows = await indexRepository.findAll();
    if (rows.isEmpty) return null;

    final notes = <DocumentLibraryItem>[];
    final documents = <DocumentLibraryItem>[];
    for (final row in rows) {
      final item = _itemFromIndexRow(row);
      if (item == null) continue;
      if (item.isMarkdown) {
        notes.add(item);
      } else {
        documents.add(item);
      }
    }
    if (notes.isEmpty && documents.isEmpty) return null;

    return DocumentLibrarySnapshot(
      rootLabel: await _currentRootLabel(),
      notes: _markFavoriteNotes(_mergeNoteItems(notes, longNoteItems), [
        ...favoriteRecords,
        ...favoriteNotes,
      ]),
      documents: _sortItems(documents),
      favoriteRecords: favoriteRecords,
      favoriteFolders: favoriteFolders,
    );
  }

  Future<void> _saveIndexedSnapshot(DocumentLibrarySnapshot snapshot) async {
    final indexRepository = _libraryItemsRepository;
    if (indexRepository == null) return;

    final indexedAt = DateTime.now().millisecondsSinceEpoch;
    final rows = <DatabaseRow>[];
    final seen = <String>{};
    for (final item in [...snapshot.notes, ...snapshot.documents]) {
      final row = _indexRowForItem(item, indexedAt: indexedAt);
      final itemKey = row['item_key'] as String;
      if (seen.add(itemKey)) rows.add(row);
    }
    await indexRepository.replaceAll(rows);
  }

  Future<void> _upsertIndexedItem(DocumentLibraryItem item) async {
    final indexRepository = _libraryItemsRepository;
    if (indexRepository == null) return;

    await indexRepository.upsert(
      _indexRowForItem(item, indexedAt: DateTime.now().millisecondsSinceEpoch),
    );
  }

  Future<void> _deleteIndexedItem(DocumentLibraryItem item) async {
    final indexRepository = _libraryItemsRepository;
    if (indexRepository == null) return;

    await indexRepository.deleteByKey(_indexKeyForItem(item));
  }

  DocumentLibraryItem? _itemFromIndexRow(DatabaseRow row) {
    final name = _string(row['name']);
    final relativePath = _string(row['relative_path']);
    final location = _string(row['location']);
    if (name == null || relativePath == null || location == null) return null;

    final kind = row['kind'] == LibraryItemKind.document.name
        ? LibraryItemKind.document
        : LibraryItemKind.markdown;
    return DocumentLibraryItem(
      kind: kind,
      name: name,
      relativePath: relativePath,
      location: location,
      mimeType: _string(row['mime_type']),
      sizeBytes: _intValue(row['size_bytes']),
      updatedAt: _intValue(row['updated_at']),
      isFavorite: _intValue(row['is_favorite']) == 1,
    );
  }

  DatabaseRow _indexRowForItem(
    DocumentLibraryItem item, {
    required int indexedAt,
  }) {
    return {
      'item_key': _indexKeyForItem(item),
      'kind': item.kind.name,
      'name': item.name,
      'relative_path': item.relativePath,
      'location': item.location,
      'mime_type': item.mimeType,
      'size_bytes': item.sizeBytes,
      'updated_at': item.updatedAt,
      'source_type': item.location.startsWith('content://') ? 'tree' : 'local',
      'is_favorite': item.isFavorite ? 1 : 0,
      'indexed_at': indexedAt,
    };
  }

  String _indexKeyForItem(DocumentLibraryItem item) {
    final location = item.location.trim();
    if (location.isNotEmpty) return '${item.kind.name}:location:$location';
    return '${item.kind.name}:relative:${item.relativePath}';
  }

  Future<String> _currentRootLabel() async {
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri != null && treeUri.isNotEmpty && Platform.isAndroid) {
      return 'Liflow';
    }
    return _directoryService.ensureRoot();
  }

  Future<DocumentLibrarySnapshot?> _loadPersistedSnapshot() async {
    final row = await _settingsRepository.findByKey(_snapshotCacheKey);
    final raw = row?['value'] as String?;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return DocumentLibrarySnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePersistedSnapshot(DocumentLibrarySnapshot snapshot) async {
    final value = jsonEncode(snapshot.toJson());
    final existing = await _settingsRepository.findByKey(_snapshotCacheKey);
    if (existing != null) {
      await _settingsRepository.update(_snapshotCacheKey, value);
    } else {
      await _settingsRepository.create(key: _snapshotCacheKey, value: value);
    }
  }

  Future<void> _deletePersistedSnapshot() async {
    try {
      await _settingsRepository.delete(_snapshotCacheKey);
    } catch (_) {
      // The cache is only an optimization.
    }
  }

  static List<DocumentLibraryItem> _itemsFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map(DocumentLibraryItem.fromJson)
        .whereType<DocumentLibraryItem>()
        .toList(growable: false);
  }

  static List<DocumentFavoriteRecord> _favoriteRecordsFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map(DocumentFavoriteRecord.fromJson)
        .whereType<DocumentFavoriteRecord>()
        .toList(growable: false);
  }

  static List<DocumentFavoriteFolder> _favoriteFoldersFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map(DocumentFavoriteFolder.fromJson)
        .whereType<DocumentFavoriteFolder>()
        .toList(growable: false);
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

  Future<List<DocumentFavoriteRecord>> _loadFavoriteNotes() async {
    final row = await _settingsRepository.findByKey(_favoriteNotesKey);
    final raw = row?['value'] as String?;
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final records = <DocumentFavoriteRecord>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final key = _string(item['key']);
        final location = _string(item['location']);
        if (key == null || location == null) continue;
        records.add(
          DocumentFavoriteRecord(
            id: 0,
            title: _string(item['title']) ?? '收藏笔记',
            content: '',
            createdAt: _intValue(item['createdAt']) ?? 0,
            location: location,
            relativePath: _string(item['relativePath']),
            fileName: _string(item['fileName']),
            libraryFavoriteKey: key,
          ),
        );
      }
      return records..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

  Future<void> _saveFavoriteNotes(List<DocumentFavoriteRecord> records) async {
    final value = jsonEncode([
      for (final record in records)
        {
          'key': record.libraryFavoriteKey,
          'title': record.title,
          'location': record.location,
          'relativePath': record.relativePath,
          'fileName': record.fileName,
          'createdAt': record.createdAt,
        },
    ]);
    final existing = await _settingsRepository.findByKey(_favoriteNotesKey);
    if (existing != null) {
      await _settingsRepository.update(_favoriteNotesKey, value);
    } else {
      await _settingsRepository.create(key: _favoriteNotesKey, value: value);
    }
  }
}

String _folderId(String treeUri) => base64Url.encode(utf8.encode(treeUri));
