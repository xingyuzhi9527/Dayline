import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/database/repositories.dart';
import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/markdown_document_parser.dart';
import '../../core/markdown/markdown_storage_service.dart';
import '../projects/project_store.dart';

class MarkdownRestoreFile {
  const MarkdownRestoreFile({
    required this.relativePath,
    required this.location,
    this.updatedAt,
  });

  final String relativePath;
  final String location;
  final int? updatedAt;
}

abstract class MarkdownRestoreSource {
  Future<List<MarkdownRestoreFile>> listMarkdownFiles();

  Future<String> readFile(String location);

  Future<String?> readBackupSnapshot();
}

class StorageMarkdownRestoreSource implements MarkdownRestoreSource {
  StorageMarkdownRestoreSource({
    required MarkdownDirectoryService directoryService,
    MarkdownStorageService? storageService,
  }) : _directoryService = directoryService,
       _storageService =
           storageService ?? MarkdownStorageService(directoryService);

  final MarkdownDirectoryService _directoryService;
  final MarkdownStorageService _storageService;

  @override
  Future<List<MarkdownRestoreFile>> listMarkdownFiles() async {
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri != null && treeUri.isNotEmpty && Platform.isAndroid) {
      final rows = await _storageService.listTreeFiles(
        roots: const ['daily', 'notes', 'projects'],
      );
      return [
        for (final row in rows)
          if (_isMarkdownPath(row['relativePath'] as String? ?? ''))
            MarkdownRestoreFile(
              relativePath: row['relativePath'] as String,
              location: MarkdownStorageLocation.documentTree(
                treeUri: treeUri,
                relativePath: row['relativePath'] as String,
              ).serialize(),
              updatedAt: (row['updatedAt'] as num?)?.toInt(),
            ),
      ];
    }

    final root = await _directoryService.ensureRoot();
    final files = <MarkdownRestoreFile>[];
    for (final dirName in const ['daily', 'notes', 'projects']) {
      final dir = Directory(p.join(root, dirName));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !_isMarkdownPath(entity.path)) continue;
        final stat = await entity.stat();
        final relativePath = p
            .split(p.relative(entity.path, from: root))
            .join('/');
        files.add(
          MarkdownRestoreFile(
            relativePath: relativePath,
            location: MarkdownStorageLocation.local(entity.path).serialize(),
            updatedAt: stat.modified.millisecondsSinceEpoch,
          ),
        );
      }
    }
    return files;
  }

  @override
  Future<String> readFile(String location) {
    return _storageService.readTextFileLocation(location);
  }

  @override
  Future<String?> readBackupSnapshot() async {
    final treeUri = await _directoryService.getTreeRootUri();
    final location = treeUri != null && treeUri.isNotEmpty && Platform.isAndroid
        ? MarkdownStorageLocation.documentTree(
            treeUri: treeUri,
            relativePath: BackupSnapshotService.snapshotRelativePath,
          ).serialize()
        : MarkdownStorageLocation.local(
            p.joinAll([
              await _directoryService.ensureRoot(),
              ...BackupSnapshotService.snapshotRelativePath.split('/'),
            ]),
          ).serialize();
    try {
      return await _storageService.readTextFileLocation(location);
    } catch (_) {
      return null;
    }
  }
}

class BackupSnapshotService {
  BackupSnapshotService({
    required MarkdownDirectoryService directoryService,
    required RecordsRepository recordsRepository,
    required TodosRepository todosRepository,
    required AppSettingsRepository settingsRepository,
    MarkdownStorageService? storageService,
  }) : _directoryService = directoryService,
       _recordsRepository = recordsRepository,
       _todosRepository = todosRepository,
       _settingsRepository = settingsRepository,
       _storageService =
           storageService ?? MarkdownStorageService(directoryService);

  static const snapshotRelativePath = '.liflow/backup_snapshot.json';
  static const schemaVersion = 1;

  final MarkdownDirectoryService _directoryService;
  final MarkdownStorageService _storageService;
  final RecordsRepository _recordsRepository;
  final TodosRepository _todosRepository;
  final AppSettingsRepository _settingsRepository;

  Future<void> writeSnapshot() async {
    final treeUri = await _directoryService.getTreeRootUri();
    if ((treeUri == null || treeUri.isEmpty) && Platform.isAndroid) return;

    final projectsRow = await _settingsRepository.findByKey(
      projectsSettingsKey,
    );
    final snapshot = {
      'schemaVersion': schemaVersion,
      'writtenAt': DateTime.now().toIso8601String(),
      'records': await _recordsRepository.findAll(),
      'todos': await _todosRepository.findAll(),
      'projects': _decodeProjectList(projectsRow?['value']),
      'settings': await _settingsRepository.findAll(),
    };
    await _storageService.writeRelativeTextFile(
      relativePath: snapshotRelativePath,
      content: const JsonEncoder.withIndent('  ').convert(snapshot),
    );
  }
}

class RestorePreview {
  const RestorePreview({
    required this.dailyNotes,
    required this.longNotes,
    required this.projects,
    this.fromSnapshot = false,
    this.todos = 0,
    this.settings = 0,
  });

  final int dailyNotes;
  final int longNotes;
  final int projects;
  final bool fromSnapshot;
  final int todos;
  final int settings;

  int get total => dailyNotes + longNotes + projects + todos + settings;
  bool get isEmpty => total == 0;
}

class RestoreResult {
  const RestoreResult({
    required this.recordsRestored,
    required this.projectsRestored,
    this.todosRestored = 0,
    this.settingsRestored = 0,
    this.fromSnapshot = false,
  });

  final int recordsRestored;
  final int projectsRestored;
  final int todosRestored;
  final int settingsRestored;
  final bool fromSnapshot;

  int get total =>
      recordsRestored + projectsRestored + todosRestored + settingsRestored;
}

class MarkdownRestoreService {
  MarkdownRestoreService({
    required MarkdownRestoreSource source,
    required RecordsRepository recordsRepository,
    required TodosRepository todosRepository,
    required AppSettingsRepository settingsRepository,
  }) : _source = source,
       _recordsRepository = recordsRepository,
       _todosRepository = todosRepository,
       _settingsRepository = settingsRepository;

  final MarkdownRestoreSource _source;
  final RecordsRepository _recordsRepository;
  final TodosRepository _todosRepository;
  final AppSettingsRepository _settingsRepository;

  Future<RestorePreview> preview() async {
    final snapshot = await _readSnapshot();
    if (snapshot != null) {
      return RestorePreview(
        dailyNotes: _listOfMaps(snapshot['records']).length,
        longNotes: 0,
        projects: _listOfMaps(snapshot['projects']).length,
        todos: _listOfMaps(snapshot['todos']).length,
        settings: _listOfMaps(snapshot['settings'])
            .where(
              (row) => !_shouldSkipSettingRestore(row['key'] as String? ?? ''),
            )
            .length,
        fromSnapshot: true,
      );
    }

    final candidates = await _scanCandidates();
    return RestorePreview(
      dailyNotes: candidates.whereType<_DailyRestoreCandidate>().length,
      longNotes: candidates.whereType<_LongNoteRestoreCandidate>().length,
      projects: candidates.whereType<_ProjectRestoreCandidate>().length,
    );
  }

  Future<RestoreResult> restore() async {
    final snapshot = await _readSnapshot();
    if (snapshot != null) {
      return _restoreSnapshot(snapshot);
    }

    final candidates = await _scanCandidates();
    final existingRecordKeys = await _existingRecordKeys();
    var recordsRestored = 0;

    for (final candidate in candidates.whereType<_RecordRestoreCandidate>()) {
      if (existingRecordKeys.contains(candidate.dedupeKey)) continue;
      await _recordsRepository.create(
        date: candidate.createdAt,
        type: candidate.type,
        content: candidate.content,
        tags: candidate.tags,
        metadata: candidate.metadata,
        createdAt: candidate.createdAt,
      );
      existingRecordKeys.add(candidate.dedupeKey);
      recordsRestored++;
    }

    final projectsRestored = await _restoreProjects(
      candidates.whereType<_ProjectRestoreCandidate>().toList(),
    );

    return RestoreResult(
      recordsRestored: recordsRestored,
      projectsRestored: projectsRestored,
    );
  }

  Future<Map<String, Object?>?> _readSnapshot() async {
    final raw = await _source.readBackupSnapshot();
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final snapshot = decoded.cast<String, Object?>();
      if (snapshot['schemaVersion'] != BackupSnapshotService.schemaVersion) {
        return null;
      }
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  Future<RestoreResult> _restoreSnapshot(Map<String, Object?> snapshot) async {
    final existingRecordKeys = await _existingSnapshotRecordKeys();
    var recordsRestored = 0;
    for (final row in _listOfMaps(snapshot['records'])) {
      final key = _snapshotRowKey(row);
      if (existingRecordKeys.contains(key)) continue;
      final metadata = {
        ..._decodeMap(row['metadata']),
        'restoredFromSnapshot': true,
        'snapshotOriginalId': row['id'],
      };
      await _recordsRepository.insert(
        {...row, 'id': null, 'metadata': jsonEncode(metadata)}..remove('id'),
      );
      existingRecordKeys.add(key);
      recordsRestored++;
    }

    final existingTodoKeys = await _existingSnapshotTodoKeys();
    var todosRestored = 0;
    for (final row in _listOfMaps(snapshot['todos'])) {
      final key = _snapshotRowKey(row);
      if (existingTodoKeys.contains(key)) continue;
      await _todosRepository.insert({...row}..remove('id'));
      existingTodoKeys.add(key);
      todosRestored++;
    }

    final projectsRestored = await _restoreProjects([
      for (final project in _listOfMaps(snapshot['projects']))
        _ProjectRestoreCandidate(project: project, sortKey: 0),
    ]);
    final settingsRestored = await _restoreSettings(
      _listOfMaps(snapshot['settings']),
    );

    return RestoreResult(
      recordsRestored: recordsRestored,
      projectsRestored: projectsRestored,
      todosRestored: todosRestored,
      settingsRestored: settingsRestored,
      fromSnapshot: true,
    );
  }

  Future<Set<String>> _existingSnapshotRecordKeys() async {
    final rows = await _recordsRepository.findAll();
    return {for (final row in rows) _snapshotRowKey(row)};
  }

  Future<Set<String>> _existingSnapshotTodoKeys() async {
    final rows = await _todosRepository.findAll();
    return {for (final row in rows) _snapshotRowKey(row)};
  }

  String _snapshotRowKey(Map<String, Object?> row) {
    return [
      row['date'],
      row['type'],
      row['content'],
      row['title'],
      row['created_at'],
    ].where((value) => value != null).join('|');
  }

  Future<int> _restoreSettings(List<Map<String, Object?>> settings) async {
    var restored = 0;
    for (final row in settings) {
      final key = row['key'] as String?;
      final value = row['value'] as String?;
      if (key == null || value == null || _shouldSkipSettingRestore(key)) {
        continue;
      }
      final existing = await _settingsRepository.findByKey(key);
      if (existing == null) {
        await _settingsRepository.create(key: key, value: value);
        restored++;
      } else if (existing['value'] != value) {
        await _settingsRepository.update(key, value);
        restored++;
      }
    }
    return restored;
  }

  Future<List<_RestoreCandidate>> _scanCandidates() async {
    final files = await _source.listMarkdownFiles();
    final candidates = <_RestoreCandidate>[];

    for (final file in files) {
      try {
        final raw = await _source.readFile(file.location);
        final candidate = _candidateFromFile(file, raw);
        if (candidate != null) candidates.add(candidate);
      } catch (_) {
        // A restore pass should skip unreadable files instead of failing all.
      }
    }

    candidates.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return candidates;
  }

  _RestoreCandidate? _candidateFromFile(MarkdownRestoreFile file, String raw) {
    final path = file.relativePath.replaceAll('\\', '/');
    if (!_isMarkdownPath(path)) return null;

    final frontMatter = _parseFrontMatter(raw);
    final type = frontMatter['type']?.toLowerCase();
    if (type == 'project' || path.endsWith('/project.md')) {
      return _projectCandidate(file, raw, frontMatter);
    }

    if (path.startsWith('daily/')) {
      return _dailyCandidate(file, raw, frontMatter);
    }

    if (path.startsWith('notes/') ||
        (path.startsWith('projects/') && path.contains('/notes/')) ||
        type == 'note') {
      return _longNoteCandidate(file, raw, frontMatter);
    }

    return null;
  }

  _DailyRestoreCandidate _dailyCandidate(
    MarkdownRestoreFile file,
    String raw,
    Map<String, String> frontMatter,
  ) {
    final document = parseMarkdownDocument(raw, fallbackTitle: '恢复日记');
    final createdAt =
        _dateFromFrontMatter(frontMatter) ??
        _dateFromPath(file.relativePath) ??
        _dateFromMillis(file.updatedAt);
    final title = _firstNonEmpty([
      frontMatter['title'],
      document.title,
      _dateLabel(createdAt),
    ]);
    return _DailyRestoreCandidate(
      createdAt: createdAt,
      content: '恢复日记：$title',
      metadata: _baseMetadata(file, 'daily'),
    );
  }

  _LongNoteRestoreCandidate _longNoteCandidate(
    MarkdownRestoreFile file,
    String raw,
    Map<String, String> frontMatter,
  ) {
    final document = parseMarkdownDocument(raw, fallbackTitle: '恢复长笔记');
    final createdAt =
        _dateFromFrontMatter(frontMatter) ??
        _dateFromPath(file.relativePath) ??
        _dateFromMillis(file.updatedAt);
    final title = _firstNonEmpty([
      frontMatter['title'],
      document.title,
      p.basenameWithoutExtension(file.relativePath),
    ]);
    final projectId = frontMatter['project_id'];
    final projectName = frontMatter['project_name'];
    return _LongNoteRestoreCandidate(
      createdAt: createdAt,
      content: title,
      tags: [if (projectName != null && projectName.trim().isNotEmpty) '项目'],
      metadata: {
        ..._baseMetadata(file, 'long_note'),
        'path': file.location,
        'title': title,
        'displayPath': file.relativePath,
        'wordCount': _wordCount(document.body),
        if (projectId != null && projectId.trim().isNotEmpty)
          'projectId': projectId.trim(),
        if (projectName != null && projectName.trim().isNotEmpty)
          'projectName': projectName.trim(),
        if (projectId != null && projectId.trim().isNotEmpty)
          'projectEntryType': 'long_note',
      },
    );
  }

  _ProjectRestoreCandidate _projectCandidate(
    MarkdownRestoreFile file,
    String raw,
    Map<String, String> frontMatter,
  ) {
    final document = parseMarkdownDocument(raw, fallbackTitle: '恢复项目');
    final updatedAt =
        _dateFromFrontMatter(
          frontMatter,
          keys: const ['updated_at', 'created_at'],
        ) ??
        _dateFromMillis(file.updatedAt);
    final title = _firstNonEmpty([
      frontMatter['title'],
      document.title,
      p.basename(p.dirname(file.relativePath)),
    ]);
    final id = _firstNonEmpty([
      frontMatter['project_id'],
      'restored-${_stablePathId(file.relativePath)}',
    ]);
    return _ProjectRestoreCandidate(
      project: {
        'id': id,
        'name': title,
        'status': _firstNonEmpty([frontMatter['status'], '进行中']),
        'goal': _extractSection(raw, const ['目标', '鐩爣']) ?? '从原文件夹恢复',
        'lastUpdate': _dateLabel(updatedAt),
        'archiveLocation': file.location,
        'todos': _extractTodos(raw),
        'updates': [
          {
            'id': '${updatedAt.microsecondsSinceEpoch}-restore-update',
            'time': _dateLabel(updatedAt),
            'createdAt': updatedAt.millisecondsSinceEpoch,
            'source': '恢复',
            'text': '从原文件夹恢复项目',
            'colorValue': 0xFF2F6F73,
          },
        ],
      },
      sortKey: updatedAt.millisecondsSinceEpoch,
    );
  }

  Future<Set<String>> _existingRecordKeys() async {
    final rows = await _recordsRepository.findAll();
    final keys = <String>{};
    for (final row in rows) {
      final metadata = _decodeMap(row['metadata']);
      final restoredPath = metadata['restoredSourcePath'] as String?;
      if (restoredPath != null && restoredPath.isNotEmpty) {
        keys.add(restoredPath);
      }
      final path = metadata['path'] as String?;
      if (path != null && path.isNotEmpty) {
        keys.add(path);
      }
    }
    return keys;
  }

  Future<int> _restoreProjects(
    List<_ProjectRestoreCandidate> candidates,
  ) async {
    if (candidates.isEmpty) return 0;

    final existingRow = await _settingsRepository.findByKey(
      projectsSettingsKey,
    );
    final existingProjects = _decodeProjectList(existingRow?['value']);
    final knownIds = {
      for (final project in existingProjects) project['id'] as String?,
    };
    final knownArchiveLocations = {
      for (final project in existingProjects)
        project['archiveLocation'] as String?,
    };

    var restored = 0;
    final nextProjects = [...existingProjects];
    for (final candidate in candidates) {
      final project = candidate.project;
      if (knownIds.contains(project['id']) ||
          knownArchiveLocations.contains(project['archiveLocation'])) {
        continue;
      }
      nextProjects.add(project);
      knownIds.add(project['id'] as String?);
      knownArchiveLocations.add(project['archiveLocation'] as String?);
      restored++;
    }

    if (restored == 0) return 0;
    final value = jsonEncode(nextProjects);
    if (existingRow == null) {
      await _settingsRepository.create(key: projectsSettingsKey, value: value);
    } else {
      await _settingsRepository.update(projectsSettingsKey, value);
    }
    return restored;
  }
}

abstract class _RestoreCandidate {
  const _RestoreCandidate({required this.sortKey});

  final int sortKey;
}

abstract class _RecordRestoreCandidate extends _RestoreCandidate {
  const _RecordRestoreCandidate({
    required this.type,
    required this.content,
    required this.createdAt,
    required this.metadata,
    this.tags = const [],
  }) : super(sortKey: 0);

  final String type;
  final String content;
  final DateTime createdAt;
  final Map<String, Object?> metadata;
  final List<String> tags;

  String get dedupeKey =>
      metadata['restoredSourcePath'] as String? ??
      metadata['path'] as String? ??
      '$type:$content:${createdAt.toIso8601String()}';
}

class _DailyRestoreCandidate extends _RecordRestoreCandidate {
  const _DailyRestoreCandidate({
    required super.createdAt,
    required super.content,
    required super.metadata,
  }) : super(type: 'memo');
}

class _LongNoteRestoreCandidate extends _RecordRestoreCandidate {
  const _LongNoteRestoreCandidate({
    required super.createdAt,
    required super.content,
    required super.metadata,
    super.tags,
  }) : super(type: 'long_note');
}

class _ProjectRestoreCandidate extends _RestoreCandidate {
  const _ProjectRestoreCandidate({
    required this.project,
    required super.sortKey,
  });

  final Map<String, Object?> project;
}

Map<String, Object?> _baseMetadata(MarkdownRestoreFile file, String kind) {
  return {
    'restoredFromMarkdown': true,
    'restoreKind': kind,
    'restoredSourcePath': file.relativePath,
    'restoredLocation': file.location,
  };
}

Map<String, String> _parseFrontMatter(String raw) {
  final trimmed = raw.trimLeft();
  if (!trimmed.startsWith('---\n')) return const {};
  final end = trimmed.indexOf('\n---\n', 4);
  if (end < 0) return const {};
  final block = trimmed.substring(4, end);
  final values = <String, String>{};
  for (final line in block.split('\n')) {
    final index = line.indexOf(':');
    if (index <= 0) continue;
    final key = line.substring(0, index).trim();
    final rawValue = line.substring(index + 1).trim();
    if (key.isEmpty || rawValue.isEmpty) continue;
    values[key] = _cleanFrontMatterValue(rawValue);
  }
  return values;
}

String _cleanFrontMatterValue(String value) {
  final trimmed = value.trim();
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    try {
      return jsonDecode(trimmed) as String;
    } catch (_) {
      return trimmed.substring(1, trimmed.length - 1);
    }
  }
  return trimmed;
}

DateTime? _dateFromFrontMatter(
  Map<String, String> frontMatter, {
  List<String> keys = const ['created_at', 'updated_at'],
}) {
  for (final key in keys) {
    final value = frontMatter[key];
    if (value == null || value.isEmpty) continue;
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  return null;
}

DateTime? _dateFromPath(String path) {
  final match = RegExp(r'(20\d{2})[-_]?(\d{2})[-_]?(\d{2})').firstMatch(path);
  if (match == null) return null;
  return DateTime.tryParse(
    '${match.group(1)}-${match.group(2)}-${match.group(3)}',
  );
}

DateTime _dateFromMillis(int? millis) {
  if (millis == null || millis <= 0) return DateTime.now();
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

String _dateLabel(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

int _wordCount(String value) {
  final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.isEmpty) return 0;
  return compact.split(' ').where((word) => word.isNotEmpty).length;
}

String? _extractSection(String raw, List<String> headings) {
  final lines = raw.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    final matches = headings.any((heading) => line == '## $heading');
    if (!matches) continue;
    final buffer = <String>[];
    for (var j = i + 1; j < lines.length; j++) {
      final next = lines[j].trimRight();
      if (next.startsWith('## ')) break;
      if (next.trim().isEmpty && buffer.isEmpty) continue;
      buffer.add(next);
    }
    final value = buffer.join('\n').trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

List<Map<String, Object?>> _extractTodos(String raw) {
  final todos = <Map<String, Object?>>[];
  final pattern = RegExp(r'^-\s*\[([ xX])\]\s+(.+)$');
  for (final line in raw.split('\n')) {
    final match = pattern.firstMatch(line.trim());
    if (match == null) continue;
    final title = match.group(2)?.trim();
    if (title == null || title.isEmpty) continue;
    todos.add({
      'id': '${DateTime.now().microsecondsSinceEpoch}-${todos.length}-todo',
      'title': title,
      'done': match.group(1)?.toLowerCase() == 'x',
    });
  }
  return todos;
}

List<Map<String, Object?>> _decodeProjectList(Object? raw) {
  if (raw is! String || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    return _listOfMaps(decoded);
  } catch (_) {
    return [];
  }
}

List<Map<String, Object?>> _listOfMaps(Object? raw) {
  if (raw is! List) return [];
  return [
    for (final item in raw)
      if (item is Map) item.cast<String, Object?>(),
  ];
}

Map<String, Object?> _decodeMap(Object? raw) {
  if (raw is! String || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return decoded.cast<String, Object?>();
  } catch (_) {}
  return const {};
}

String _stablePathId(String path) {
  var hash = 0x811c9dc5;
  for (final codeUnit in path.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

bool _isMarkdownPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.md') || lower.endsWith('.markdown');
}

bool _shouldSkipSettingRestore(String key) {
  return key == projectsSettingsKey ||
      key == 'markdown_root_path' ||
      key == 'markdown_root_tree_uri' ||
      key == 'markdown_root_tree_subdir' ||
      key == 'markdown_root_configured';
}
