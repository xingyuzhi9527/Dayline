import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'markdown_directory_service.dart';

enum MarkdownStorageKind { localPath, documentTree }

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

  Future<String?> pickDirectory() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('pickDirectory');
  }

  Future<bool> hasTreeAccess(String treeUri) async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('hasTreeAccess', {
          'treeUri': treeUri,
        }) ??
        false;
  }

  Future<String> writeRelativeTextFile({
    required String relativePath,
    required String content,
  }) async {
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri != null && treeUri.isNotEmpty) {
      await _channel.invokeMethod<void>('writeTextFile', {
        'treeUri': treeUri,
        'relativePath': relativePath,
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
        await _channel.invokeMethod<void>('writeTextFile', {
          'treeUri': parsed.treeUri,
          'relativePath': parsed.relativePath,
          'content': content,
        });
    }
  }

  Future<String> readTextFileLocation(String location) async {
    final parsed = MarkdownStorageLocation.parse(location);
    return switch (parsed.kind) {
      MarkdownStorageKind.localPath => File(parsed.localPath!).readAsString(),
      MarkdownStorageKind.documentTree =>
        _channel
            .invokeMethod<String>('readTextFile', {
              'treeUri': parsed.treeUri,
              'relativePath': parsed.relativePath,
            })
            .then((value) => value ?? ''),
    };
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
}
