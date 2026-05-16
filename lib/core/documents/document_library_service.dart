import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../database/repository_providers.dart';
import '../markdown/markdown_directory_service.dart';
import '../markdown/markdown_storage_service.dart';

final documentLibraryServiceProvider = Provider<DocumentLibraryService>((ref) {
  final settings = ref.watch(appSettingsRepositoryProvider);
  final dirService = MarkdownDirectoryService(settings);
  return DocumentLibraryService(
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
  });

  final String rootLabel;
  final List<DocumentLibraryItem> notes;
  final List<DocumentLibraryItem> documents;
}

class DocumentLibraryService {
  DocumentLibraryService({
    required MarkdownDirectoryService directoryService,
    required MarkdownStorageService storageService,
  }) : _directoryService = directoryService,
       _storageService = storageService;

  final MarkdownDirectoryService _directoryService;
  final MarkdownStorageService _storageService;

  Future<DocumentLibrarySnapshot> load() async {
    await _storageService.ensureCoreDirectories();
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri != null && treeUri.isNotEmpty && Platform.isAndroid) {
      return _loadTree(treeUri);
    }
    return _loadLocal();
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

  Future<DocumentLibrarySnapshot> _loadTree(String treeUri) async {
    final rows = await _storageService.listTreeFiles(
      roots: const ['daily', 'notes', 'documents'],
    );
    final notes = <DocumentLibraryItem>[];
    final documents = <DocumentLibraryItem>[];

    for (final row in rows) {
      final relativePath = row['relativePath'] as String? ?? '';
      if (relativePath.isEmpty) continue;
      final isMarkdown =
          relativePath.startsWith('daily/') ||
          relativePath.startsWith('notes/');
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
    );
  }

  Future<DocumentLibrarySnapshot> _loadLocal() async {
    final root = await _directoryService.ensureRoot();
    final notes = <DocumentLibraryItem>[];
    final documents = <DocumentLibraryItem>[];

    for (final dirName in const ['daily', 'notes']) {
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
}
