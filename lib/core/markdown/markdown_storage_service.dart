import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'markdown_directory_service.dart';

enum MarkdownStorageKind { localPath, documentTree }

class MarkdownDirectoryPick {
  const MarkdownDirectoryPick({required this.treeUri, this.name});

  final String treeUri;
  final String? name;
}

class MarkdownStorageLocation {
  const MarkdownStorageLocation.local(this.localPath)
    : kind = MarkdownStorageKind.localPath,
      treeUri = null,
      relativePath = null;

  const MarkdownStorageLocation.documentTree({
    required this.treeUri,
    required this.relativePath,
  }) : kind = MarkdownStorageKind.documentTree,
       localPath = null;

  static const _treePrefix = 'tree::';
  static const _separator = '::';

  final MarkdownStorageKind kind;
  final String? localPath;
  final String? treeUri;
  final String? relativePath;

  String serialize() {
    return switch (kind) {
      MarkdownStorageKind.localPath => localPath!,
      MarkdownStorageKind.documentTree =>
        '$_treePrefix${base64Url.encode(utf8.encode(treeUri!))}$_separator$relativePath',
    };
  }

  String get displayPath {
    return switch (kind) {
      MarkdownStorageKind.localPath => localPath!,
      MarkdownStorageKind.documentTree => relativePath!,
    };
  }

  static MarkdownStorageLocation parse(String raw) {
    if (!raw.startsWith(_treePrefix)) {
      return MarkdownStorageLocation.local(raw);
    }

    final payload = raw.substring(_treePrefix.length);
    final separatorIndex = payload.indexOf(_separator);
    if (separatorIndex == -1) {
      throw FormatException('Invalid document-tree location: $raw');
    }

    final encodedTreeUri = payload.substring(0, separatorIndex);
    final relativePath = payload.substring(separatorIndex + _separator.length);
    final treeUri = utf8.decode(base64Url.decode(encodedTreeUri));
    return MarkdownStorageLocation.documentTree(
      treeUri: treeUri,
      relativePath: relativePath,
    );
  }
}

class MarkdownStorageService {
  MarkdownStorageService(this._directoryService);

  static const _channel = MethodChannel('liflow/markdown_storage');

  final MarkdownDirectoryService _directoryService;

  Future<MarkdownDirectoryPick?> pickDirectory() async {
    if (!Platform.isAndroid) return null;
    final row = await _channel.invokeMapMethod<String, Object?>(
      'pickDirectory',
    );
    final treeUri = row?['treeUri'] as String?;
    if (treeUri == null || treeUri.isEmpty) return null;
    return MarkdownDirectoryPick(
      treeUri: treeUri,
      name: row?['name'] as String?,
    );
  }

  Future<bool> hasTreeAccess(String treeUri) async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('hasTreeAccess', {
          'treeUri': treeUri,
        }) ??
        false;
  }

  Future<void> ensureTreeRootSubdir() async {
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri == null || treeUri.isEmpty || !Platform.isAndroid) return;
    final current = await _directoryService.getTreeRootSubdir();
    if (current.isNotEmpty) return;

    final row = await _channel.invokeMapMethod<String, Object?>(
      'describeTree',
      {'treeUri': treeUri},
    );
    final name = (row?['name'] as String?)?.trim();
    final subdir = _shouldUsePickedFolderAsLiflow(name)
        ? ''
        : MarkdownDirectoryService.defaultDirName;
    await _directoryService.setTreeRootSubdir(subdir);
  }

  Future<void> ensureCoreDirectories() async {
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri != null && treeUri.isNotEmpty) {
      await ensureTreeRootSubdir();
      await _channel.invokeMethod<void>('ensureDirectories', {
        'treeUri': treeUri,
        'paths': await _treePaths(const ['daily', 'notes', 'documents']),
      });
      return;
    }

    await _directoryService.ensureCoreDirectories();
  }

  Future<List<Map<String, Object?>>> listTreeFiles({
    required List<String> roots,
  }) async {
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri == null || treeUri.isEmpty || !Platform.isAndroid) {
      return const [];
    }

    await ensureTreeRootSubdir();
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'listFiles',
      {'treeUri': treeUri, 'roots': await _treePaths(roots)},
    );
    return (rows ?? const [])
        .map((row) => row.cast<String, Object?>())
        .map(_stripTreePrefixFromRow)
        .toList();
  }

  Future<Map<String, Object?>?> importDocumentToTree() async {
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri == null || treeUri.isEmpty || !Platform.isAndroid) {
      return null;
    }

    await ensureTreeRootSubdir();
    final row = await _channel.invokeMapMethod<String, Object?>(
      'importDocument',
      {'treeUri': treeUri, 'documentsPath': await _treePath('documents')},
    );
    return row == null ? null : _stripTreePrefixFromRow(row);
  }

  Future<void> openTreeDocument({
    required String relativePath,
    String? mimeType,
  }) async {
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri == null || treeUri.isEmpty || !Platform.isAndroid) {
      throw StateError('Document tree storage is not available.');
    }

    await ensureTreeRootSubdir();
    await _channel.invokeMethod<void>('openDocument', {
      'treeUri': treeUri,
      'relativePath': await _treePath(relativePath),
      'mimeType': mimeType,
    });
  }

  Future<void> deleteTreeDocument({required String relativePath}) async {
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri == null || treeUri.isEmpty || !Platform.isAndroid) {
      throw StateError('Document tree storage is not available.');
    }

    await ensureTreeRootSubdir();
    await _channel.invokeMethod<void>('deleteDocument', {
      'treeUri': treeUri,
      'relativePath': await _treePath(relativePath),
    });
  }

  Future<void> writeRelativeBinaryFile({
    required String relativePath,
    required String sourcePath,
    required String mimeType,
  }) async {
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri != null && treeUri.isNotEmpty && Platform.isAndroid) {
      await ensureTreeRootSubdir();
      await _channel.invokeMethod<void>('writeBinaryFile', {
        'treeUri': treeUri,
        'relativePath': await _treePath(relativePath),
        'sourcePath': sourcePath,
        'mimeType': mimeType,
      });
      return;
    }

    final root = await _directoryService.ensureRoot();
    final file = File(_joinLocal(root, relativePath));
    await file.parent.create(recursive: true);
    await File(sourcePath).copy(file.path);
  }

  Future<String> writeRelativeTextFile({
    required String relativePath,
    required String content,
  }) async {
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri != null && treeUri.isNotEmpty) {
      await ensureTreeRootSubdir();
      await _channel.invokeMethod<void>('writeTextFile', {
        'treeUri': treeUri,
        'relativePath': await _treePath(relativePath),
        'content': content,
      });
      return MarkdownStorageLocation.documentTree(
        treeUri: treeUri,
        relativePath: relativePath,
      ).serialize();
    }

    final root = await _directoryService.ensureRoot();
    final file = File(_joinLocal(root, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return MarkdownStorageLocation.local(file.path).serialize();
  }

  Future<void> writeTextFileLocation(String location, String content) async {
    final parsed = MarkdownStorageLocation.parse(location);
    switch (parsed.kind) {
      case MarkdownStorageKind.localPath:
        final file = File(parsed.localPath!);
        await file.parent.create(recursive: true);
        await file.writeAsString(content);
      case MarkdownStorageKind.documentTree:
        await ensureTreeRootSubdir();
        await _channel.invokeMethod<void>('writeTextFile', {
          'treeUri': parsed.treeUri,
          'relativePath': await _treePath(parsed.relativePath!),
          'content': content,
        });
    }
  }

  Future<String> readTextFileLocation(String location) async {
    final parsed = MarkdownStorageLocation.parse(location);
    switch (parsed.kind) {
      case MarkdownStorageKind.localPath:
        return File(parsed.localPath!).readAsString();
      case MarkdownStorageKind.documentTree:
        await ensureTreeRootSubdir();
        return await _channel
            .invokeMethod<String>('readTextFile', {
              'treeUri': parsed.treeUri,
              'relativePath': await _treePath(parsed.relativePath!),
            })
            .then((value) => value ?? '');
    }
  }

  static String displayPathForLocation(String location) {
    return MarkdownStorageLocation.parse(location).displayPath;
  }

  String _joinLocal(String root, String relativePath) {
    final segments = p.posix
        .normalize(relativePath)
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    return p.joinAll([root, ...segments]);
  }

  Future<List<String>> _treePaths(List<String> relativePaths) async {
    final prefix = await _directoryService.getTreeRootSubdir();
    return relativePaths.map((path) => _joinTreePath(prefix, path)).toList();
  }

  Future<String> _treePath(String relativePath) async {
    final prefix = await _directoryService.getTreeRootSubdir();
    return _joinTreePath(prefix, relativePath);
  }

  Map<String, Object?> _stripTreePrefixFromRow(Map<String, Object?> row) {
    final rawRelativePath = row['relativePath'] as String?;
    if (rawRelativePath == null || rawRelativePath.isEmpty) return row;

    final normalizedPrefix = _lastKnownTreePrefix;
    if (normalizedPrefix == null || normalizedPrefix.isEmpty) return row;
    final prefix = '$normalizedPrefix/';
    if (!rawRelativePath.startsWith(prefix)) return row;
    return {...row, 'relativePath': rawRelativePath.substring(prefix.length)};
  }

  String? _lastKnownTreePrefix;

  String _joinTreePath(String prefix, String relativePath) {
    final normalizedPath = p.posix
        .normalize(relativePath)
        .replaceAll('\\', '/');
    final cleanedPath = normalizedPath == '.'
        ? ''
        : normalizedPath.replaceFirst(RegExp(r'^/+'), '');
    final cleanedPrefix = prefix
        .trim()
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    _lastKnownTreePrefix = cleanedPrefix;
    if (cleanedPrefix.isEmpty) return cleanedPath;
    if (cleanedPath.isEmpty) return cleanedPrefix;
    if (cleanedPath == cleanedPrefix ||
        cleanedPath.startsWith('$cleanedPrefix/')) {
      return cleanedPath;
    }
    return p.posix.join(cleanedPrefix, cleanedPath);
  }

  bool _shouldUsePickedFolderAsLiflow(String? name) {
    return name != null &&
        name.trim().toLowerCase() ==
            MarkdownDirectoryService.defaultDirName.toLowerCase();
  }
}
