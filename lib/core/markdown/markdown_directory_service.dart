import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/repositories.dart';
import 'markdown_filename.dart';

class MarkdownDirectoryService {
  MarkdownDirectoryService(this._settings);

  final AppSettingsRepository _settings;

  static const _keyRootPath = 'markdown_root_path';
  static const _keyConfigured = 'markdown_root_configured';
  static const _defaultDirName = 'LiflowNotes';

  Future<String> getRootPath() async {
    final row = await _settings.findByKey(_keyRootPath);
    if (row != null) {
      final dir = Directory(row['value'] as String);
      if (await dir.exists()) return dir.path;
    }
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, _defaultDirName);
  }

  Future<void> setRootPath(String path) async {
    final existing = await _settings.findByKey(_keyRootPath);
    if (existing != null) {
      await _settings.update(_keyRootPath, path);
    } else {
      await _settings.create(key: _keyRootPath, value: path);
    }
    await _markConfigured();
  }

  Future<void> useDefaultRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, _defaultDirName);
    await setRootPath(path);
  }

  Future<bool> isConfigured() async {
    final row = await _settings.findByKey(_keyConfigured);
    return row != null && row['value'] == 'true';
  }

  Future<void> _markConfigured() async {
    final existing = await _settings.findByKey(_keyConfigured);
    if (existing != null) {
      await _settings.update(_keyConfigured, 'true');
    } else {
      await _settings.create(key: _keyConfigured, value: 'true');
    }
  }

  Future<String> ensureRoot() async {
    final path = await getRootPath();
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  Future<String> ensureDailyDir(DateTime date) async {
    final root = await ensureRoot();
    final sub = p.join(root, 'daily', MarkdownFilename.monthDir(date));
    final dir = Directory(sub);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return sub;
  }

  Future<String> ensureNotesDir(DateTime date) async {
    final root = await ensureRoot();
    final sub = p.join(root, 'notes', MarkdownFilename.monthDir(date));
    final dir = Directory(sub);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return sub;
  }

  MarkdownNamingMode get namingMode => MarkdownNamingMode.datetimeTitle;
}
