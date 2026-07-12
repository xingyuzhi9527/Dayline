import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import '../../core/database/local_database.dart';
import '../../core/database/repositories.dart';
import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/markdown_document_parser.dart';
import '../../core/markdown/markdown_storage_service.dart';
import '../../core/parser/expense_line_item.dart';
import '../../core/parser/lui_lite_parser.dart';
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

abstract class BackupFileRestoreSource {
  Future<bool> supportsBackupFileRestore() async => false;

  Future<RestoredBackupFile?> restoreBackupFile({
    required String backupRelativePath,
    required String targetRelativePath,
    required int expectedSize,
    required String expectedSha256,
    required String mimeType,
  }) async => null;
}

class RestoredBackupFile {
  const RestoredBackupFile({required this.localPath, required this.created});

  final String localPath;
  final bool created;
}

class StorageMarkdownRestoreSource
    implements MarkdownRestoreSource, BackupFileRestoreSource {
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

  @override
  Future<bool> supportsBackupFileRestore() async {
    final treeUri = await _directoryService.getTreeRootUri();
    return treeUri == null || treeUri.isEmpty || !Platform.isAndroid;
  }

  @override
  Future<RestoredBackupFile?> restoreBackupFile({
    required String backupRelativePath,
    required String targetRelativePath,
    required int expectedSize,
    required String expectedSha256,
    required String mimeType,
  }) async {
    if (!await supportsBackupFileRestore()) return null;

    final safeBackupPath = _safeRelativePath(backupRelativePath);
    final safeTargetPath = _safeRelativePath(targetRelativePath);
    if (safeBackupPath == null || safeTargetPath == null) return null;

    try {
      final root = await _directoryService.ensureRoot();
      final source = File(_joinRelativePath(root, safeBackupPath));
      if (!await _matchesBackupFile(
        source,
        expectedSize: expectedSize,
        expectedSha256: expectedSha256,
      )) {
        return null;
      }

      final target = File(_joinRelativePath(root, safeTargetPath));
      final targetAlreadyValid = await _matchesBackupFile(
        target,
        expectedSize: expectedSize,
        expectedSha256: expectedSha256,
      );
      if (targetAlreadyValid) {
        return RestoredBackupFile(localPath: target.path, created: false);
      }

      final targetExisted = await target.exists();
      await _storageService.writeRelativeBinaryFile(
        relativePath: safeTargetPath,
        sourcePath: source.path,
        mimeType: mimeType,
      );
      if (!await _matchesBackupFile(
        target,
        expectedSize: expectedSize,
        expectedSha256: expectedSha256,
      )) {
        return null;
      }
      return RestoredBackupFile(
        localPath: target.path,
        created: !targetExisted,
      );
    } catch (_) {
      return null;
    }
  }
}

class BackupSnapshotService {
  BackupSnapshotService({
    required MarkdownDirectoryService directoryService,
    required LocalDatabase database,
    MarkdownStorageService? storageService,
  }) : _directoryService = directoryService,
       _database = database,
       _storageService =
           storageService ?? MarkdownStorageService(directoryService);

  static const snapshotRelativePath = '.liflow/backup_snapshot.json';
  static const mediaBackupRoot = '.liflow/media';
  static const projectFilesBackupRoot = '.liflow/project_files';
  static const schemaVersion = 4;
  static const supportedSchemaVersions = {1, 2, 3, schemaVersion};

  final MarkdownDirectoryService _directoryService;
  final MarkdownStorageService _storageService;
  final LocalDatabase _database;

  Future<void> writeSnapshot() async {
    final treeUri = await _directoryService.getTreeRootUri();
    if ((treeUri == null || treeUri.isEmpty) && Platform.isAndroid) return;

    final database = await _database.database;
    final snapshot = await database.transaction((txn) async {
      final settings = await txn.query('app_settings', orderBy: 'key ASC');
      Map<String, Object?>? projectsRow;
      for (final row in settings) {
        if (row['key'] == projectsSettingsKey) {
          projectsRow = row;
          break;
        }
      }

      return <String, Object?>{
        'schemaVersion': schemaVersion,
        'writtenAt': DateTime.now().toIso8601String(),
        'records': await txn.query('records', orderBy: 'id ASC'),
        'todos': await txn.query('todos', orderBy: 'id ASC'),
        'trackers': await txn.query('trackers', orderBy: 'id ASC'),
        'tracker_logs': await txn.query('tracker_logs', orderBy: 'id ASC'),
        'focus_sessions': await txn.query('focus_sessions', orderBy: 'id ASC'),
        'expenses': await txn.query('expenses', orderBy: 'id ASC'),
        'body_logs': await txn.query('body_logs', orderBy: 'id ASC'),
        'daily_reviews': await txn.query('daily_reviews', orderBy: 'id ASC'),
        'media_attachments': await txn.query(
          'media_attachments',
          orderBy: 'id ASC',
        ),
        'projects': _decodeProjectList(projectsRow?['value']),
        'settings': settings,
      };
    });
    final documentTreeStorage =
        treeUri != null && treeUri.isNotEmpty && Platform.isAndroid;
    snapshot['media_attachments'] = await _exportMediaAttachments(
      _listOfMaps(snapshot['media_attachments']),
    );
    snapshot['project_files'] = await _exportProjectFiles(
      _listOfMaps(snapshot['projects']),
    );
    snapshot['mediaBackup'] = {
      'formatVersion': 1,
      'storageKind': documentTreeStorage ? 'documentTree' : 'localPath',
      'restoreSupport': documentTreeStorage ? 'exportOnly' : 'full',
    };
    await _storageService.writeRelativeTextFile(
      relativePath: snapshotRelativePath,
      content: const JsonEncoder.withIndent('  ').convert(snapshot),
      mimeType: 'application/json',
    );
  }

  Future<List<Map<String, Object?>>> _exportMediaAttachments(
    List<Map<String, Object?>> rows,
  ) async {
    final exported = <Map<String, Object?>>[];
    for (final row in rows) {
      final attachmentId =
          _snapshotIntValue(row['id'])?.toString() ?? 'unknown';
      final files = <String, Object?>{
        'local_path': await _exportMediaFile(
          attachmentId: attachmentId,
          role: 'media',
          rawPath: row['local_path'] as String?,
        ),
      };
      final thumbnailPath = row['thumbnail_path'] as String?;
      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        files['thumbnail_path'] = await _exportMediaFile(
          attachmentId: attachmentId,
          role: 'thumbnail',
          rawPath: thumbnailPath,
        );
      }
      exported.add({...row, 'backup_files': files});
    }
    return exported;
  }

  Future<Map<String, Object?>> _exportMediaFile({
    required String attachmentId,
    required String role,
    required String? rawPath,
  }) async {
    if (rawPath == null || rawPath.isEmpty) {
      return const {'status': 'missingSource'};
    }
    if (rawPath.startsWith('content://')) {
      return const {'status': 'unsupportedSource'};
    }

    final source = File(rawPath);
    if (!await source.exists()) return const {'status': 'missingSource'};

    final size = await source.length();
    final digest = await _sha256File(source);
    final extension = _safeExtension(rawPath);
    final relativePath = p.posix.join(
      mediaBackupRoot,
      attachmentId,
      '${role}_${digest.substring(0, 16)}$extension',
    );
    final mimeType = _mediaMimeType(rawPath);
    try {
      await _storageService.writeRelativeBinaryFile(
        relativePath: relativePath,
        sourcePath: source.path,
        mimeType: mimeType,
      );
      return {
        'status': 'exported',
        'relativePath': relativePath,
        'size': size,
        'sha256': digest,
        'mimeType': mimeType,
      };
    } catch (_) {
      return {
        'status': 'copyFailed',
        'size': size,
        'sha256': digest,
        'mimeType': mimeType,
      };
    }
  }

  Future<List<Map<String, Object?>>> _exportProjectFiles(
    List<Map<String, Object?>> projects,
  ) async {
    if (projects.isEmpty) return const [];

    final root = await _directoryService.ensureRoot();
    final descriptors = <Map<String, Object?>>[];
    final seen = <String>{};

    for (final project in projects) {
      for (final relativePath in _projectReferencedRelativePaths(project)) {
        final safePath = _safeRelativePath(relativePath);
        if (safePath == null || !seen.add(safePath)) continue;

        final source = File(_joinRelativePath(root, safePath));
        final descriptor = await _exportProjectFile(
          targetRelativePath: safePath,
          source: source,
        );
        descriptors.add(descriptor);
      }
    }

    return descriptors;
  }

  Future<Map<String, Object?>> _exportProjectFile({
    required String targetRelativePath,
    required File source,
  }) async {
    if (!await source.exists()) {
      return {
        'status': 'missingSource',
        'targetRelativePath': targetRelativePath,
      };
    }

    final size = await source.length();
    final digest = await _sha256File(source);
    final extension = _safeExtension(targetRelativePath);
    final relativePath = p.posix.join(
      projectFilesBackupRoot,
      digest.substring(0, 2),
      '${digest.substring(0, 16)}$extension',
    );
    final mimeType = _mediaMimeType(targetRelativePath);

    try {
      await _storageService.writeRelativeBinaryFile(
        relativePath: relativePath,
        sourcePath: source.path,
        mimeType: mimeType,
      );
      return {
        'status': 'exported',
        'targetRelativePath': targetRelativePath,
        'relativePath': relativePath,
        'size': size,
        'sha256': digest,
        'mimeType': mimeType,
      };
    } catch (_) {
      return {
        'status': 'copyFailed',
        'targetRelativePath': targetRelativePath,
        'size': size,
        'sha256': digest,
        'mimeType': mimeType,
      };
    }
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
    this.trackers = 0,
    this.trackerLogs = 0,
    this.focusSessions = 0,
    this.expenses = 0,
    this.bodyLogs = 0,
    this.dailyReviews = 0,
    this.mediaAttachments = 0,
    this.mediaAttachmentsUnavailable = 0,
    this.projectFiles = 0,
    this.projectFilesUnavailable = 0,
  });

  final int dailyNotes;
  final int longNotes;
  final int projects;
  final bool fromSnapshot;
  final int todos;
  final int settings;
  final int trackers;
  final int trackerLogs;
  final int focusSessions;
  final int expenses;
  final int bodyLogs;
  final int dailyReviews;
  final int mediaAttachments;
  final int mediaAttachmentsUnavailable;
  final int projectFiles;
  final int projectFilesUnavailable;

  int get structuredData =>
      trackers +
      trackerLogs +
      focusSessions +
      expenses +
      bodyLogs +
      dailyReviews +
      mediaAttachments +
      projectFiles;

  int get total =>
      dailyNotes + longNotes + projects + todos + settings + structuredData;
  bool get isEmpty => total == 0;
}

class RestoreResult {
  const RestoreResult({
    required this.recordsRestored,
    required this.projectsRestored,
    this.todosRestored = 0,
    this.settingsRestored = 0,
    this.trackersRestored = 0,
    this.trackerLogsRestored = 0,
    this.focusSessionsRestored = 0,
    this.expensesRestored = 0,
    this.bodyLogsRestored = 0,
    this.dailyReviewsRestored = 0,
    this.mediaAttachmentsRestored = 0,
    this.mediaAttachmentsUnavailable = 0,
    this.projectFilesRestored = 0,
    this.projectFilesUnavailable = 0,
    this.fromSnapshot = false,
  });

  final int recordsRestored;
  final int projectsRestored;
  final int todosRestored;
  final int settingsRestored;
  final int trackersRestored;
  final int trackerLogsRestored;
  final int focusSessionsRestored;
  final int expensesRestored;
  final int bodyLogsRestored;
  final int dailyReviewsRestored;
  final int mediaAttachmentsRestored;
  final int mediaAttachmentsUnavailable;
  final int projectFilesRestored;
  final int projectFilesUnavailable;
  final bool fromSnapshot;

  int get structuredDataRestored =>
      trackersRestored +
      trackerLogsRestored +
      focusSessionsRestored +
      expensesRestored +
      bodyLogsRestored +
      dailyReviewsRestored +
      mediaAttachmentsRestored +
      projectFilesRestored;

  int get total =>
      recordsRestored +
      projectsRestored +
      todosRestored +
      settingsRestored +
      structuredDataRestored;
}

class MarkdownRestoreService {
  MarkdownRestoreService({
    required MarkdownRestoreSource source,
    required LocalDatabase database,
    required RecordsRepository recordsRepository,
    required AppSettingsRepository settingsRepository,
  }) : _source = source,
       _database = database,
       _recordsRepository = recordsRepository,
       _settingsRepository = settingsRepository;

  final MarkdownRestoreSource _source;
  final LocalDatabase _database;
  final RecordsRepository _recordsRepository;
  final AppSettingsRepository _settingsRepository;

  Future<RestorePreview> preview() async {
    final snapshot = await _readSnapshot();
    if (snapshot != null) {
      final mediaRows = _listOfMaps(snapshot['media_attachments']);
      final projectFiles = _listOfMaps(snapshot['project_files']);
      final snapshotTodos = _listOfMaps(snapshot['todos']);
      final snapshotExpenses = _listOfMaps(snapshot['expenses']);
      final fallbackCandidates =
          snapshotTodos.isEmpty || snapshotExpenses.isEmpty
          ? await _scanCandidates()
          : const <_RestoreCandidate>[];
      return RestorePreview(
        dailyNotes: _listOfMaps(snapshot['records']).length,
        longNotes: 0,
        projects: _listOfMaps(snapshot['projects']).length,
        todos:
            snapshotTodos.length +
            (snapshotTodos.isEmpty
                ? _markdownTodoCandidateCount(fallbackCandidates)
                : 0),
        settings: _listOfMaps(snapshot['settings'])
            .where(
              (row) => !_shouldSkipSettingRestore(row['key'] as String? ?? ''),
            )
            .length,
        trackers: _listOfMaps(snapshot['trackers']).length,
        trackerLogs: _listOfMaps(snapshot['tracker_logs']).length,
        focusSessions: _listOfMaps(snapshot['focus_sessions']).length,
        expenses:
            snapshotExpenses.length +
            (snapshotExpenses.isEmpty
                ? _markdownExpenseCandidateCount(fallbackCandidates)
                : 0),
        bodyLogs: _listOfMaps(snapshot['body_logs']).length,
        dailyReviews: _listOfMaps(snapshot['daily_reviews']).length,
        mediaAttachments: mediaRows.length,
        mediaAttachmentsUnavailable: await _unavailableMediaCount(
          snapshot,
          mediaRows,
        ),
        projectFiles: projectFiles.length,
        projectFilesUnavailable: await _unavailableProjectFileCount(
          projectFiles,
        ),
        fromSnapshot: true,
      );
    }

    final candidates = await _scanCandidates();
    return RestorePreview(
      dailyNotes: candidates.whereType<_DailyRestoreCandidate>().length,
      longNotes: candidates.whereType<_LongNoteRestoreCandidate>().length,
      projects: candidates.whereType<_ProjectRestoreCandidate>().length,
      todos: candidates.whereType<_DailyRestoreCandidate>().fold<int>(
        0,
        (sum, candidate) => sum + candidate.todos.length,
      ),
      expenses:
          candidates.whereType<_DailyRestoreCandidate>().fold<int>(
            0,
            (sum, candidate) => sum + candidate.expenses.length,
          ) +
          candidates
              .whereType<_MonthlyExpenseReportRestoreCandidate>()
              .fold<int>(
                0,
                (sum, candidate) => sum + candidate.expenses.length,
              ),
    );
  }

  Future<RestoreResult> restore() async {
    final snapshot = await _readSnapshot();
    if (snapshot != null) {
      final snapshotResult = await _restoreSnapshot(snapshot);
      final restoreTodosFromMarkdown = _listOfMaps(snapshot['todos']).isEmpty;
      final restoreExpensesFromMarkdown = _listOfMaps(
        snapshot['expenses'],
      ).isEmpty;
      if (!restoreTodosFromMarkdown && !restoreExpensesFromMarkdown) {
        return snapshotResult;
      }

      final candidates = await _scanCandidates();
      final structuredRestored = await _restoreMarkdownStructuredData(
        candidates.whereType<_DailyRestoreCandidate>().toList(),
        candidates.whereType<_MonthlyExpenseReportRestoreCandidate>().toList(),
        restoreTodos: restoreTodosFromMarkdown,
        restoreExpenses: restoreExpensesFromMarkdown,
      );
      return _withMarkdownStructuredFallback(
        snapshotResult,
        structuredRestored,
      );
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
    final structuredRestored = await _restoreMarkdownStructuredData(
      candidates.whereType<_DailyRestoreCandidate>().toList(),
      candidates.whereType<_MonthlyExpenseReportRestoreCandidate>().toList(),
    );

    return RestoreResult(
      recordsRestored: recordsRestored,
      projectsRestored: projectsRestored,
      todosRestored: structuredRestored.todos,
      expensesRestored: structuredRestored.expenses,
    );
  }

  Future<Map<String, Object?>?> _readSnapshot() async {
    final raw = await _source.readBackupSnapshot();
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final snapshot = decoded.cast<String, Object?>();
      final schemaVersion = (snapshot['schemaVersion'] as num?)?.toInt();
      if (!BackupSnapshotService.supportedSchemaVersions.contains(
        schemaVersion,
      )) {
        return null;
      }
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  Future<RestoreResult> _restoreSnapshot(Map<String, Object?> snapshot) async {
    final preparedMedia = await _prepareMediaAttachments(snapshot);
    final preparedProjectFiles = await _prepareProjectFiles(snapshot);
    final database = await _database.database;
    try {
      return await database.transaction((txn) async {
        // Save-operation journals describe the pre-restore database and must
        // never suppress writes against the restored snapshot.
        await txn.delete('write_operations');
        final records = await _restoreSnapshotParentRows(
          txn,
          table: 'records',
          rows: _listOfMaps(snapshot['records']),
          dataColumns: const [
            'date',
            'type',
            'content',
            'time',
            'tags',
            'metadata',
            'is_deleted',
            'created_at',
            'updated_at',
          ],
          identityColumns: const [
            'date',
            'type',
            'content',
            'time',
            'created_at',
          ],
          transform: (row, values) {
            final metadata = {
              ..._decodeMap(row['metadata']),
              'restoredFromSnapshot': true,
              if (row['id'] != null) 'snapshotOriginalId': row['id'],
            };
            return {...values, 'metadata': jsonEncode(metadata)};
          },
        );
        final trackers = await _restoreSnapshotParentRows(
          txn,
          table: 'trackers',
          rows: _listOfMaps(snapshot['trackers']),
          dataColumns: const [
            'name',
            'unit',
            'target_value',
            'color',
            'icon',
            'is_archived',
            'created_at',
            'updated_at',
          ],
          identityColumns: const [
            'name',
            'unit',
            'target_value',
            'color',
            'icon',
            'created_at',
          ],
        );
        final todos = await _restoreSnapshotParentRows(
          txn,
          table: 'todos',
          rows: _listOfMaps(snapshot['todos']),
          dataColumns: const [
            'date',
            'title',
            'note',
            'due_time',
            'priority',
            'is_completed',
            'completed_at',
            'created_at',
            'updated_at',
          ],
          identityColumns: const [
            'date',
            'title',
            'note',
            'due_time',
            'priority',
            'created_at',
          ],
        );
        final focusSessions = await _restoreSnapshotParentRows(
          txn,
          table: 'focus_sessions',
          rows: _listOfMaps(snapshot['focus_sessions']),
          dataColumns: const [
            'date',
            'started_at',
            'ended_at',
            'duration_minutes',
            'note',
            'created_at',
            'updated_at',
          ],
          identityColumns: const [
            'date',
            'started_at',
            'ended_at',
            'duration_minutes',
            'note',
            'created_at',
          ],
        );
        final expenses = await _restoreSnapshotParentRows(
          txn,
          table: 'expenses',
          rows: _listOfMaps(snapshot['expenses']),
          dataColumns: const [
            'date',
            'amount',
            'category',
            'note',
            'currency',
            'created_at',
            'updated_at',
          ],
          identityColumns: const [
            'date',
            'amount',
            'category',
            'note',
            'currency',
            'created_at',
          ],
        );
        final bodyLogs = await _restoreSnapshotParentRows(
          txn,
          table: 'body_logs',
          rows: _listOfMaps(snapshot['body_logs']),
          dataColumns: const [
            'date',
            'metric',
            'value',
            'unit',
            'note',
            'created_at',
            'updated_at',
          ],
          identityColumns: const [
            'date',
            'metric',
            'value',
            'unit',
            'note',
            'created_at',
          ],
        );
        final dailyReviews = await _restoreSnapshotParentRows(
          txn,
          table: 'daily_reviews',
          rows: _listOfMaps(snapshot['daily_reviews']),
          dataColumns: const [
            'date',
            'kept',
            'adjust',
            'next_action',
            'created_at',
            'updated_at',
          ],
          identityColumns: const ['date'],
        );
        final trackerLogsRestored = await _restoreSnapshotChildRows(
          txn,
          table: 'tracker_logs',
          rows: _listOfMaps(snapshot['tracker_logs']),
          foreignKeyColumn: 'tracker_id',
          parentIdMap: trackers.idMap,
          dataColumns: const [
            'tracker_id',
            'date',
            'value',
            'note',
            'created_at',
            'updated_at',
          ],
          identityColumns: const [
            'tracker_id',
            'date',
            'value',
            'note',
            'created_at',
          ],
        );
        final mediaAttachmentsRestored = await _restoreSnapshotMediaRows(
          txn,
          rows: preparedMedia.rows,
          parentIdMap: records.idMap,
        );
        final projectsRestored = await _restoreSnapshotProjects(
          txn,
          _listOfMaps(snapshot['projects']),
        );
        final settingsRestored = await _restoreSnapshotSettings(
          txn,
          _listOfMaps(snapshot['settings']),
        );

        return RestoreResult(
          recordsRestored: records.restored,
          projectsRestored: projectsRestored,
          todosRestored: todos.restored,
          settingsRestored: settingsRestored,
          trackersRestored: trackers.restored,
          trackerLogsRestored: trackerLogsRestored,
          focusSessionsRestored: focusSessions.restored,
          expensesRestored: expenses.restored,
          bodyLogsRestored: bodyLogs.restored,
          dailyReviewsRestored: dailyReviews.restored,
          mediaAttachmentsRestored: mediaAttachmentsRestored,
          mediaAttachmentsUnavailable: preparedMedia.unavailable,
          projectFilesRestored: preparedProjectFiles.restored,
          projectFilesUnavailable: preparedProjectFiles.unavailable,
          fromSnapshot: true,
        );
      });
    } catch (error, stackTrace) {
      await _deleteCreatedMediaFiles(preparedMedia.createdPaths);
      await _deleteCreatedMediaFiles(preparedProjectFiles.createdPaths);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<_PreparedProjectFiles> _prepareProjectFiles(
    Map<String, Object?> snapshot,
  ) async {
    final rows = _listOfMaps(snapshot['project_files']);
    if (rows.isEmpty) return _PreparedProjectFiles();

    final backupSource = _source is BackupFileRestoreSource
        ? _source as BackupFileRestoreSource
        : null;
    final canRestoreFiles =
        backupSource != null && await backupSource.supportsBackupFileRestore();
    if (!canRestoreFiles) {
      return _PreparedProjectFiles(unavailable: rows.length);
    }

    final createdPaths = <String>{};
    var restored = 0;
    var unavailable = 0;

    for (final row in rows) {
      if (row['status'] != 'exported') {
        unavailable++;
        continue;
      }
      final backupRelativePath = row['relativePath'] as String?;
      final targetRelativePath = row['targetRelativePath'] as String?;
      final expectedSize = _snapshotInt(row['size']);
      final expectedSha256 = row['sha256'] as String?;
      if (backupRelativePath == null ||
          targetRelativePath == null ||
          expectedSize == null ||
          expectedSize < 0 ||
          expectedSha256 == null ||
          expectedSha256.length != 64) {
        unavailable++;
        continue;
      }

      final restoredFile = await backupSource.restoreBackupFile(
        backupRelativePath: backupRelativePath,
        targetRelativePath: targetRelativePath,
        expectedSize: expectedSize,
        expectedSha256: expectedSha256,
        mimeType:
            row['mimeType'] as String? ?? _mediaMimeType(targetRelativePath),
      );
      if (restoredFile == null) {
        unavailable++;
        continue;
      }
      if (restoredFile.created) {
        createdPaths.add(restoredFile.localPath);
        restored++;
      }
    }

    return _PreparedProjectFiles(
      restored: restored,
      unavailable: unavailable,
      createdPaths: createdPaths,
    );
  }

  Future<_PreparedMediaAttachments> _prepareMediaAttachments(
    Map<String, Object?> snapshot,
  ) async {
    final rows = _listOfMaps(snapshot['media_attachments']);
    final schemaVersion = _snapshotInt(snapshot['schemaVersion']) ?? 1;
    if (schemaVersion < 3 || rows.isEmpty) {
      return _PreparedMediaAttachments(rows: rows);
    }

    final backupSource = _source is BackupFileRestoreSource
        ? _source as BackupFileRestoreSource
        : null;
    final canRestoreFiles =
        backupSource != null && await backupSource.supportsBackupFileRestore();
    final preparedRows = <Map<String, Object?>>[];
    final createdPaths = <String>{};
    var unavailable = 0;

    for (final row in rows) {
      final backupFiles = _decodeMap(row['backup_files']);
      final mediaFile = _decodeMap(backupFiles['local_path']);
      if (!canRestoreFiles || mediaFile['status'] != 'exported') {
        unavailable++;
        continue;
      }

      final restored = await _restoreMediaFile(
        row: row,
        descriptor: mediaFile,
        role: 'media',
      );
      if (restored == null) {
        unavailable++;
        continue;
      }
      if (restored.created) createdPaths.add(restored.localPath);

      final prepared = {...row, 'local_path': restored.localPath};
      final thumbnailFile = _decodeMap(backupFiles['thumbnail_path']);
      if (thumbnailFile['status'] == 'exported') {
        final restoredThumbnail = await _restoreMediaFile(
          row: row,
          descriptor: thumbnailFile,
          role: 'thumbnail',
        );
        if (restoredThumbnail != null) {
          prepared['thumbnail_path'] = restoredThumbnail.localPath;
          if (restoredThumbnail.created) {
            createdPaths.add(restoredThumbnail.localPath);
          }
        } else {
          prepared['thumbnail_path'] = null;
        }
      } else {
        prepared['thumbnail_path'] = null;
      }
      preparedRows.add(prepared);
    }

    return _PreparedMediaAttachments(
      rows: preparedRows,
      unavailable: unavailable,
      createdPaths: createdPaths,
    );
  }

  Future<RestoredBackupFile?> _restoreMediaFile({
    required Map<String, Object?> row,
    required Map<String, Object?> descriptor,
    required String role,
  }) async {
    final relativePath = descriptor['relativePath'] as String?;
    final expectedSize = _snapshotInt(descriptor['size']);
    final expectedSha256 = descriptor['sha256'] as String?;
    if (relativePath == null ||
        expectedSize == null ||
        expectedSize < 0 ||
        expectedSha256 == null ||
        expectedSha256.length != 64) {
      return null;
    }

    final oldId = _snapshotInt(row['id']) ?? 0;
    final targetRelativePath = _mediaRestoreTargetPath(
      row: row,
      role: role,
      digest: expectedSha256,
      extension: _safeExtension(relativePath),
      oldId: oldId,
    );
    final backupSource = _source;
    if (backupSource is! BackupFileRestoreSource) return null;
    return (backupSource as BackupFileRestoreSource).restoreBackupFile(
      backupRelativePath: relativePath,
      targetRelativePath: targetRelativePath,
      expectedSize: expectedSize,
      expectedSha256: expectedSha256,
      mimeType: descriptor['mimeType'] as String? ?? 'application/octet-stream',
    );
  }

  String _mediaRestoreTargetPath({
    required Map<String, Object?> row,
    required String role,
    required String digest,
    required String extension,
    required int oldId,
  }) {
    final createdAt = _snapshotInt(row['created_at']) ?? 0;
    final date = DateTime.fromMillisecondsSinceEpoch(createdAt);
    final month =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}';
    final sourceType = row['source_type'] as String?;
    final mediaType = row['media_type'] as String?;
    final folder = mediaType == 'audio'
        ? 'audio'
        : sourceType == 'expense_receipt'
        ? 'receipts'
        : 'photos';
    final digestPrefix = digest.substring(0, 16);
    return p.posix.join(
      'documents',
      folder,
      month,
      'restored_${oldId}_${role}_$digestPrefix$extension',
    );
  }

  Future<int> _unavailableMediaCount(
    Map<String, Object?> snapshot,
    List<Map<String, Object?>> rows,
  ) async {
    final schemaVersion = _snapshotInt(snapshot['schemaVersion']) ?? 1;
    if (schemaVersion < 3 || rows.isEmpty) return 0;
    final backupSource = _source;
    if (backupSource is! BackupFileRestoreSource) return rows.length;
    if (!await (backupSource as BackupFileRestoreSource)
        .supportsBackupFileRestore()) {
      return rows.length;
    }
    return rows.where((row) {
      final files = _decodeMap(row['backup_files']);
      return _decodeMap(files['local_path'])['status'] != 'exported';
    }).length;
  }

  Future<int> _unavailableProjectFileCount(
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return 0;
    final backupSource = _source;
    if (backupSource is! BackupFileRestoreSource) return rows.length;
    if (!await (backupSource as BackupFileRestoreSource)
        .supportsBackupFileRestore()) {
      return rows.length;
    }
    return rows.where((row) => row['status'] != 'exported').length;
  }

  Future<void> _deleteCreatedMediaFiles(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<int> _restoreSnapshotMediaRows(
    sqflite.Transaction txn, {
    required List<Map<String, Object?>> rows,
    required Map<int, int> parentIdMap,
  }) async {
    const dataColumns = [
      'record_id',
      'media_type',
      'source_type',
      'local_path',
      'thumbnail_path',
      'width',
      'height',
      'duration_ms',
      'sort_order',
      'created_at',
      'updated_at',
    ];
    const identityColumns = [
      'record_id',
      'media_type',
      'source_type',
      'sort_order',
      'created_at',
    ];
    final existingRows = await txn.query('media_attachments');
    final existingByKey = <String, Map<String, Object?>>{
      for (final row in existingRows)
        _snapshotIdentity(row, identityColumns): row,
    };
    var restored = 0;

    for (final row in rows) {
      final oldParentId = _snapshotInt(row['record_id']);
      if (oldParentId == null) {
        throw const FormatException('media_attachments 缺少 record_id');
      }
      final newParentId = parentIdMap[oldParentId];
      if (newParentId == null) {
        throw FormatException(
          'media_attachments 引用了不存在的 record_id=$oldParentId',
        );
      }
      final values = _snapshotValues(row, dataColumns);
      values['record_id'] = newParentId;
      final key = _snapshotIdentity(values, identityColumns);
      final existing = existingByKey[key];
      if (existing != null) {
        final updates = <String, Object?>{};
        for (final column in const [
          'local_path',
          'thumbnail_path',
          'width',
          'height',
          'duration_ms',
          'updated_at',
        ]) {
          if (values[column] != existing[column]) {
            updates[column] = values[column];
          }
        }
        if (updates.isNotEmpty) {
          await txn.update(
            'media_attachments',
            updates,
            where: 'id = ?',
            whereArgs: [existing['id']],
          );
        }
        continue;
      }
      final newId = await txn.insert('media_attachments', values);
      existingByKey[key] = {...values, 'id': newId};
      restored++;
    }
    return restored;
  }

  Future<({int restored, Map<int, int> idMap})> _restoreSnapshotParentRows(
    sqflite.Transaction txn, {
    required String table,
    required List<Map<String, Object?>> rows,
    required List<String> dataColumns,
    required List<String> identityColumns,
    Map<String, Object?> Function(
      Map<String, Object?> row,
      Map<String, Object?> values,
    )?
    transform,
  }) async {
    final existingRows = await txn.query(table);
    final existingByKey = <String, Map<String, Object?>>{
      for (final row in existingRows)
        _snapshotIdentity(row, identityColumns): row,
    };
    final idMap = <int, int>{};
    var restored = 0;

    for (final row in rows) {
      final oldId = _snapshotInt(row['id']);
      var values = _snapshotValues(row, dataColumns);
      if (transform != null) values = transform(row, values);
      final key = _snapshotIdentity(values, identityColumns);
      final existing = existingByKey[key];
      if (existing != null) {
        final existingId = _snapshotInt(existing['id']);
        if (oldId != null && existingId != null) idMap[oldId] = existingId;
        continue;
      }

      final newId = await txn.insert(table, values);
      if (oldId != null) idMap[oldId] = newId;
      existingByKey[key] = {...values, 'id': newId};
      restored++;
    }

    return (restored: restored, idMap: idMap);
  }

  Future<int> _restoreSnapshotChildRows(
    sqflite.Transaction txn, {
    required String table,
    required List<Map<String, Object?>> rows,
    required String foreignKeyColumn,
    required Map<int, int> parentIdMap,
    required List<String> dataColumns,
    required List<String> identityColumns,
  }) async {
    final existingRows = await txn.query(table);
    final existingKeys = {
      for (final row in existingRows) _snapshotIdentity(row, identityColumns),
    };
    var restored = 0;

    for (final row in rows) {
      final oldParentId = _snapshotInt(row[foreignKeyColumn]);
      if (oldParentId == null) {
        throw FormatException('$table 缺少 $foreignKeyColumn');
      }
      final newParentId = parentIdMap[oldParentId];
      if (newParentId == null) {
        throw FormatException('$table 引用了不存在的 $foreignKeyColumn=$oldParentId');
      }

      final values = _snapshotValues(row, dataColumns);
      values[foreignKeyColumn] = newParentId;
      final key = _snapshotIdentity(values, identityColumns);
      if (existingKeys.contains(key)) continue;
      await txn.insert(table, values);
      existingKeys.add(key);
      restored++;
    }

    return restored;
  }

  Future<int> _restoreSnapshotProjects(
    sqflite.Transaction txn,
    List<Map<String, Object?>> projects,
  ) async {
    if (projects.isEmpty) return 0;
    final rows = await txn.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [projectsSettingsKey],
      limit: 1,
    );
    final existingProjects = _decodeProjectList(
      rows.isEmpty ? null : rows.single['value'],
    );
    final knownIds = {
      for (final project in existingProjects) project['id'] as String?,
    };
    final knownArchiveLocations = {
      for (final project in existingProjects)
        project['archiveLocation'] as String?,
    };
    final nextProjects = [...existingProjects];
    var restored = 0;
    for (final project in projects) {
      if (knownIds.contains(project['id']) ||
          knownArchiveLocations.contains(project['archiveLocation'])) {
        continue;
      }
      nextProjects.add({...project});
      knownIds.add(project['id'] as String?);
      knownArchiveLocations.add(project['archiveLocation'] as String?);
      restored++;
    }
    if (restored == 0) return 0;

    final values = {
      'value': jsonEncode(nextProjects),
      'updated_at': timestamp(DateTime.now()),
    };
    if (rows.isEmpty) {
      await txn.insert('app_settings', {'key': projectsSettingsKey, ...values});
    } else {
      await txn.update(
        'app_settings',
        values,
        where: 'key = ?',
        whereArgs: [projectsSettingsKey],
      );
    }
    return restored;
  }

  Future<int> _restoreSnapshotSettings(
    sqflite.Transaction txn,
    List<Map<String, Object?>> settings,
  ) async {
    var restored = 0;
    for (final row in settings) {
      final key = row['key'] as String?;
      final value = row['value'] as String?;
      if (key == null || value == null || _shouldSkipSettingRestore(key)) {
        continue;
      }
      final existing = await txn.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      final updatedAt =
          _snapshotInt(row['updated_at']) ?? timestamp(DateTime.now());
      if (existing.isEmpty) {
        await txn.insert('app_settings', {
          'key': key,
          'value': value,
          'updated_at': updatedAt,
        });
        restored++;
      } else if (existing.single['value'] != value) {
        await txn.update(
          'app_settings',
          {'value': value, 'updated_at': updatedAt},
          where: 'key = ?',
          whereArgs: [key],
        );
        restored++;
      }
    }
    return restored;
  }

  Map<String, Object?> _snapshotValues(
    Map<String, Object?> row,
    List<String> columns,
  ) {
    return {
      for (final column in columns)
        if (row.containsKey(column)) column: row[column],
    };
  }

  String _snapshotIdentity(Map<String, Object?> row, List<String> columns) {
    return jsonEncode([for (final column in columns) row[column]]);
  }

  int? _snapshotInt(Object? value) => switch (value) {
    int() => value,
    num() => value.toInt(),
    _ => null,
  };

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
    if (type == 'monthly_expense_report' || path.contains('/months/')) {
      return _monthlyExpenseReportCandidate(file, raw, frontMatter);
    }

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

  _MonthlyExpenseReportRestoreCandidate _monthlyExpenseReportCandidate(
    MarkdownRestoreFile file,
    String raw,
    Map<String, String> frontMatter,
  ) {
    final month =
        _monthFromFrontMatter(frontMatter) ??
        _monthFromPath(file.relativePath) ??
        DateTime(
          _dateFromMillis(file.updatedAt).year,
          _dateFromMillis(file.updatedAt).month,
        );
    return _MonthlyExpenseReportRestoreCandidate(
      sortKey: timestamp(month),
      expenses: _extractMonthlyExpenseReport(raw, month),
    );
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
      todos: _extractDailyTodos(raw, createdAt),
      expenses: _extractDailyExpenses(raw, createdAt),
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
    final projectDir = p.posix.dirname(file.relativePath);
    final fileUpdates = _extractProjectFileUpdates(
      raw,
      projectDir: projectDir,
      updatedAt: updatedAt,
    );
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
          ...fileUpdates,
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

  Future<({int todos, int expenses})> _restoreMarkdownStructuredData(
    List<_DailyRestoreCandidate> candidates,
    List<_MonthlyExpenseReportRestoreCandidate> monthlyReports, {
    bool restoreTodos = true,
    bool restoreExpenses = true,
  }) async {
    if (candidates.isEmpty && monthlyReports.isEmpty) {
      return (todos: 0, expenses: 0);
    }

    final db = await _database.database;
    return db.transaction((txn) async {
      final existingTodoKeys = {
        for (final row in await txn.query('todos'))
          _snapshotIdentity(row, const [
            'date',
            'title',
            'note',
            'due_time',
            'priority',
            'created_at',
          ]),
      };
      final existingExpenseKeys = {
        for (final row in await txn.query('expenses'))
          _snapshotIdentity(row, const [
            'date',
            'amount',
            'category',
            'note',
            'currency',
            'created_at',
          ]),
      };
      var todosRestored = 0;
      var expensesRestored = 0;

      for (final candidate in candidates) {
        if (restoreTodos) {
          for (final todo in candidate.todos) {
            final values = _markdownTodoValues(candidate, todo);
            final key = _snapshotIdentity(values, const [
              'date',
              'title',
              'note',
              'due_time',
              'priority',
              'created_at',
            ]);
            if (existingTodoKeys.contains(key)) continue;
            await txn.insert('todos', values);
            existingTodoKeys.add(key);
            todosRestored++;
          }
        }

        if (restoreExpenses) {
          for (final expense in candidate.expenses) {
            final values = _markdownExpenseValues(expense);
            final key = _snapshotIdentity(values, const [
              'date',
              'amount',
              'category',
              'note',
              'currency',
              'created_at',
            ]);
            if (existingExpenseKeys.contains(key)) continue;
            await txn.insert('expenses', values);
            existingExpenseKeys.add(key);
            expensesRestored++;
          }
        }
      }

      if (restoreExpenses) {
        for (final report in monthlyReports) {
          for (final expense in report.expenses) {
            final values = _markdownExpenseValues(expense);
            final key = _snapshotIdentity(values, const [
              'date',
              'amount',
              'category',
              'note',
              'currency',
              'created_at',
            ]);
            if (existingExpenseKeys.contains(key)) continue;
            await txn.insert('expenses', values);
            existingExpenseKeys.add(key);
            expensesRestored++;
          }
        }
      }

      return (todos: todosRestored, expenses: expensesRestored);
    });
  }
}

int _markdownTodoCandidateCount(List<_RestoreCandidate> candidates) {
  return candidates.whereType<_DailyRestoreCandidate>().fold<int>(
    0,
    (sum, candidate) => sum + candidate.todos.length,
  );
}

int _markdownExpenseCandidateCount(List<_RestoreCandidate> candidates) {
  return candidates.whereType<_DailyRestoreCandidate>().fold<int>(
        0,
        (sum, candidate) => sum + candidate.expenses.length,
      ) +
      candidates.whereType<_MonthlyExpenseReportRestoreCandidate>().fold<int>(
        0,
        (sum, candidate) => sum + candidate.expenses.length,
      );
}

RestoreResult _withMarkdownStructuredFallback(
  RestoreResult base,
  ({int todos, int expenses}) restored,
) {
  return RestoreResult(
    recordsRestored: base.recordsRestored,
    projectsRestored: base.projectsRestored,
    todosRestored: base.todosRestored + restored.todos,
    settingsRestored: base.settingsRestored,
    trackersRestored: base.trackersRestored,
    trackerLogsRestored: base.trackerLogsRestored,
    focusSessionsRestored: base.focusSessionsRestored,
    expensesRestored: base.expensesRestored + restored.expenses,
    bodyLogsRestored: base.bodyLogsRestored,
    dailyReviewsRestored: base.dailyReviewsRestored,
    mediaAttachmentsRestored: base.mediaAttachmentsRestored,
    mediaAttachmentsUnavailable: base.mediaAttachmentsUnavailable,
    projectFilesRestored: base.projectFilesRestored,
    projectFilesUnavailable: base.projectFilesUnavailable,
    fromSnapshot: base.fromSnapshot,
  );
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
    this.todos = const [],
    this.expenses = const [],
  }) : super(type: 'memo');

  final List<_MarkdownTodoRestoreCandidate> todos;
  final List<_MarkdownExpenseRestoreCandidate> expenses;
}

class _MonthlyExpenseReportRestoreCandidate extends _RestoreCandidate {
  const _MonthlyExpenseReportRestoreCandidate({
    required super.sortKey,
    this.expenses = const [],
  });

  final List<_MarkdownExpenseRestoreCandidate> expenses;
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

class _MarkdownTodoRestoreCandidate {
  const _MarkdownTodoRestoreCandidate({
    required this.title,
    required this.isCompleted,
    required this.createdAt,
    this.note,
    this.dueTime,
    this.priority = 0,
  });

  final String title;
  final bool isCompleted;
  final DateTime createdAt;
  final String? note;
  final String? dueTime;
  final int priority;
}

class _MarkdownExpenseRestoreCandidate {
  const _MarkdownExpenseRestoreCandidate({
    required this.amount,
    required this.category,
    required this.createdAt,
    this.note,
  });

  final double amount;
  final String category;
  final DateTime createdAt;
  final String? note;
}

Map<String, Object?> _baseMetadata(MarkdownRestoreFile file, String kind) {
  return {
    'restoredFromMarkdown': true,
    'restoreKind': kind,
    'restoredSourcePath': file.relativePath,
    'restoredLocation': file.location,
  };
}

Map<String, Object?> _markdownTodoValues(
  _DailyRestoreCandidate daily,
  _MarkdownTodoRestoreCandidate todo,
) {
  final createdAt = timestamp(todo.createdAt);
  return {
    'date': dateKey(daily.createdAt),
    'title': todo.title,
    'note': todo.note,
    'due_time': todo.dueTime,
    'priority': todo.priority,
    'is_completed': todo.isCompleted ? 1 : 0,
    'completed_at': todo.isCompleted ? createdAt : null,
    'created_at': createdAt,
    'updated_at': createdAt,
  };
}

Map<String, Object?> _markdownExpenseValues(
  _MarkdownExpenseRestoreCandidate expense,
) {
  final createdAt = timestamp(expense.createdAt);
  return {
    'date': dateKey(expense.createdAt),
    'amount': expense.amount,
    'category': expense.category,
    'note': expense.note,
    'currency': 'CNY',
    'created_at': createdAt,
    'updated_at': createdAt,
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

List<_MarkdownTodoRestoreCandidate> _extractDailyTodos(
  String raw,
  DateTime fallbackDate,
) {
  final candidates = <_MarkdownTodoRestoreCandidate>[];
  final lines = _sectionBulletLines(raw, const {'待办', '待办流转', '已完成', '未完成'});
  final pattern = RegExp(r'^-\s*\[([ xX])\]\s+(.+)$');

  for (final line in lines) {
    final match = pattern.firstMatch(line.trim());
    if (match == null) continue;
    final parsed = _parseTodoText(match.group(2)?.trim() ?? '');
    if (parsed.title.isEmpty) continue;
    candidates.add(
      _MarkdownTodoRestoreCandidate(
        title: parsed.title,
        isCompleted: match.group(1)?.toLowerCase() == 'x',
        createdAt: _timeOnDate(parsed.dueTime, fallbackDate, candidates.length),
        note: parsed.note,
        dueTime: parsed.dueTime,
        priority: parsed.priority,
      ),
    );
  }

  return candidates;
}

List<_MarkdownExpenseRestoreCandidate> _extractDailyExpenses(
  String raw,
  DateTime fallbackDate,
) {
  final candidates = <_MarkdownExpenseRestoreCandidate>[];
  final lines = _sectionBulletLines(raw, const {'消费', '支出', '消费明细'});

  for (final line in lines) {
    final text = line.replaceFirst(RegExp(r'^-\s*'), '').trim();
    final parsed = _parseExpenseLine(text, fallbackDate, candidates.length);
    if (parsed != null) candidates.add(parsed);
  }

  return candidates;
}

List<_MarkdownExpenseRestoreCandidate> _extractMonthlyExpenseReport(
  String raw,
  DateTime month,
) {
  final candidates = <_MarkdownExpenseRestoreCandidate>[];
  var active = false;
  DateTime? currentDate;

  for (final rawLine in raw.split('\n')) {
    final line = rawLine.trim();
    final heading = RegExp(r'^(#{2,4})\s+(.+)$').firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      final title = heading.group(2)!.trim();
      if (level == 2) {
        active = const {'每日明细', '消费明细', '明细'}.contains(title);
        currentDate = null;
        continue;
      }
      if (active && level >= 3) {
        currentDate = _dateFromMonthHeading(title, month);
      }
      continue;
    }

    if (!active || currentDate == null || !line.startsWith('- ')) continue;
    final text = line.replaceFirst(RegExp(r'^-\s*'), '').trim();
    final parsed = _parseExpenseLine(text, currentDate, candidates.length);
    if (parsed != null) candidates.add(parsed);
  }

  return candidates;
}

List<String> _sectionBulletLines(String raw, Set<String> wantedHeadings) {
  final result = <String>[];
  var active = false;

  for (final rawLine in raw.split('\n')) {
    final line = rawLine.trimRight();
    final heading = RegExp(r'^(#{2,4})\s+(.+)$').firstMatch(line.trim());
    if (heading != null) {
      final title = heading.group(2)!.trim();
      active = wantedHeadings.contains(title);
      continue;
    }
    if (active && line.trimLeft().startsWith('- ')) {
      result.add(line.trimLeft());
    }
  }

  return result;
}

DateTime? _monthFromFrontMatter(Map<String, String> frontMatter) {
  final value = frontMatter['month'];
  if (value == null || value.isEmpty) return null;
  final match = RegExp(r'^(20\d{2})[-_/](\d{1,2})$').firstMatch(value.trim());
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  if (year == null || month == null || month < 1 || month > 12) return null;
  return DateTime(year, month);
}

DateTime? _monthFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final match = RegExp(
    r'(20\d{2})[-_](\d{2})(?:\.md)?$',
  ).firstMatch(normalized);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  if (year == null || month == null || month < 1 || month > 12) return null;
  return DateTime(year, month);
}

DateTime? _dateFromMonthHeading(String heading, DateTime month) {
  final normalized = heading.trim();
  final full = RegExp(
    r'^(20\d{2})[-_/](\d{1,2})[-_/](\d{1,2})$',
  ).firstMatch(normalized);
  if (full != null) {
    final year = int.tryParse(full.group(1)!);
    final parsedMonth = int.tryParse(full.group(2)!);
    final day = int.tryParse(full.group(3)!);
    if (year != null && parsedMonth != null && day != null) {
      return _validDate(year, parsedMonth, day);
    }
  }

  final short = RegExp(r'^(\d{1,2})[-_/](\d{1,2})$').firstMatch(normalized);
  if (short != null) {
    final parsedMonth = int.tryParse(short.group(1)!);
    final day = int.tryParse(short.group(2)!);
    if (parsedMonth != null && day != null) {
      return _validDate(month.year, parsedMonth, day);
    }
  }

  final dayOnly = RegExp(r'^(\d{1,2})日?$').firstMatch(normalized);
  if (dayOnly != null) {
    final day = int.tryParse(dayOnly.group(1)!);
    if (day != null) return _validDate(month.year, month.month, day);
  }

  return null;
}

DateTime? _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

({String title, String? note, String? dueTime, int priority}) _parseTodoText(
  String raw,
) {
  final parts = raw
      .split(RegExp(r'[，,]'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return (title: '', note: null, dueTime: null, priority: 0);
  }

  String? dueTime;
  var priority = 0;
  final notes = <String>[];
  for (final part in parts.skip(1)) {
    final timeMatch = RegExp(r'^时间\s+([0-2]?\d[:：][0-5]\d)$').firstMatch(part);
    if (timeMatch != null) {
      dueTime = timeMatch.group(1)!.replaceAll('：', ':').padLeft(5, '0');
      continue;
    }
    final priorityMatch = RegExp(r'^优先级\s+(\d+)$').firstMatch(part);
    if (priorityMatch != null) {
      priority = int.tryParse(priorityMatch.group(1)!) ?? 0;
      continue;
    }
    notes.add(part);
  }

  return (
    title: parts.first,
    note: notes.isEmpty ? null : notes.join('，'),
    dueTime: dueTime,
    priority: priority,
  );
}

_MarkdownExpenseRestoreCandidate? _parseExpenseLine(
  String raw,
  DateTime fallbackDate,
  int index,
) {
  final timeMatch = RegExp(r'^([0-2]?\d[:：][0-5]\d)\s+(.+)$').firstMatch(raw);
  final time = timeMatch?.group(1)?.replaceAll('：', ':');
  final text = timeMatch?.group(2)?.trim() ?? raw;

  final direct = RegExp(
    r'^(.+?)[:：]\s*(?:¥|￥|RMB\s*)?(\d+(?:\.\d+)?)(?:\s*元)?(?:[，,]\s*(.+))?$',
    caseSensitive: false,
  ).firstMatch(text);
  if (direct != null) {
    final amount = double.tryParse(direct.group(2)!);
    final category = direct.group(1)?.trim() ?? '';
    if (amount != null && amount > 0 && category.isNotEmpty) {
      return _MarkdownExpenseRestoreCandidate(
        amount: amount,
        category: category,
        note: direct.group(3)?.trim(),
        createdAt: _timeOnDate(time, fallbackDate, index),
      );
    }
  }

  final parsed = LuiLiteParser.parse(text);
  if (parsed.type != ParsedInputType.expense) return null;
  final items = validExpenseLineItemsFromMetadata(parsed.metadata);
  if (items.isEmpty) return null;
  final item = items.first;
  return _MarkdownExpenseRestoreCandidate(
    amount: item.amount,
    category: item.name.isEmpty ? parsed.content : item.name,
    note: parsed.content.isEmpty ? null : parsed.content,
    createdAt: _timeOnDate(time ?? parsed.time, fallbackDate, index),
  );
}

DateTime _timeOnDate(String? time, DateTime date, int index) {
  final normalized = time?.replaceAll('：', ':');
  final match = normalized == null
      ? null
      : RegExp(r'^([0-2]?\d):([0-5]\d)$').firstMatch(normalized);
  if (match != null) {
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour <= 23) {
      return DateTime(date.year, date.month, date.day, hour, minute);
    }
  }
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).add(Duration(minutes: index));
}

List<Map<String, Object?>> _extractProjectFileUpdates(
  String raw, {
  required String projectDir,
  required DateTime updatedAt,
}) {
  final updates = <Map<String, Object?>>[];
  final seen = <String>{};
  final linkPattern = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');

  for (final line in raw.split('\n')) {
    for (final match in linkPattern.allMatches(line)) {
      final rawHref = match.group(2)?.trim();
      if (rawHref == null || rawHref.isEmpty) continue;
      final relativePath = _projectLinkedRelativePath(
        rawHref,
        projectDir: projectDir,
      );
      if (relativePath == null || !seen.add(relativePath)) continue;

      final fileName = p.posix.basename(relativePath);
      final isImage = _isImagePath(relativePath);
      updates.add({
        'id':
            '${updatedAt.microsecondsSinceEpoch}-restore-file-${updates.length}',
        'time': _dateLabel(updatedAt),
        'createdAt': updatedAt.millisecondsSinceEpoch,
        'source': isImage ? '图片资料' : '文件',
        'text': fileName,
        'entryType': isImage ? 'image' : 'file',
        if (isImage) 'imageRelativePath': relativePath,
        if (!isImage) 'fileRelativePath': relativePath,
        'mimeType': _mediaMimeType(relativePath),
        'colorValue': 0xFF2F6F73,
      });
    }
  }

  return updates;
}

String? _projectLinkedRelativePath(
  String rawHref, {
  required String projectDir,
}) {
  final withoutAnchor = rawHref.split('#').first.trim();
  if (withoutAnchor.isEmpty ||
      withoutAnchor.startsWith('http://') ||
      withoutAnchor.startsWith('https://') ||
      withoutAnchor.startsWith('mailto:') ||
      withoutAnchor.startsWith('content://')) {
    return null;
  }

  final decoded = Uri.decodeFull(withoutAnchor).replaceAll('\\', '/');
  final normalized = p.posix.normalize(
    decoded.startsWith('projects/')
        ? decoded
        : p.posix.join(projectDir, decoded),
  );
  final safe = _safeRelativePath(normalized);
  if (safe == null || !safe.startsWith('projects/')) return null;
  if (_isMarkdownPath(safe) && !safe.contains('/materials/')) return null;
  return safe;
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
  if (raw is Map) return raw.cast<String, Object?>();
  if (raw is! String || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return decoded.cast<String, Object?>();
  } catch (_) {}
  return const {};
}

class _PreparedMediaAttachments {
  _PreparedMediaAttachments({
    required this.rows,
    this.unavailable = 0,
    this.createdPaths = const {},
  });

  final List<Map<String, Object?>> rows;
  final int unavailable;
  final Set<String> createdPaths;
}

class _PreparedProjectFiles {
  _PreparedProjectFiles({
    this.restored = 0,
    this.unavailable = 0,
    this.createdPaths = const {},
  });

  final int restored;
  final int unavailable;
  final Set<String> createdPaths;
}

Iterable<String> _projectReferencedRelativePaths(Map<String, Object?> project) {
  final updates = _listOfMaps(project['updates']);
  final favorites = _listOfMaps(project['favorites']);
  final paths = <String>[];

  for (final update in updates) {
    final filePath = update['fileRelativePath'];
    if (filePath is String) paths.add(filePath);

    final imagePath = update['imageRelativePath'];
    if (imagePath is String) paths.add(imagePath);

    final imagePaths = update['imageRelativePaths'];
    if (imagePaths is List) {
      for (final path in imagePaths) {
        if (path is String) paths.add(path);
      }
    }
  }

  for (final favorite in favorites) {
    final relativePath = favorite['relativePath'];
    if (relativePath is String) paths.add(relativePath);
  }

  return paths.where((path) {
    final safe = _safeRelativePath(path);
    return safe != null && safe.startsWith('projects/');
  });
}

int? _snapshotIntValue(Object? value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  _ => null,
};

String? _safeRelativePath(String raw) {
  final normalized = raw.replaceAll('\\', '/');
  if (normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) {
    return null;
  }
  final clean = p.posix.normalize(normalized);
  if (clean.isEmpty || clean == '.' || clean.startsWith('../')) return null;
  return clean;
}

String _joinRelativePath(String root, String relativePath) {
  return p.joinAll([root, ...relativePath.split('/')]);
}

Future<bool> _matchesBackupFile(
  File file, {
  required int expectedSize,
  required String expectedSha256,
}) async {
  if (!await file.exists()) return false;
  if (await file.length() != expectedSize) return false;
  final actual = await _sha256File(file);
  return actual.toLowerCase() == expectedSha256.toLowerCase();
}

Future<String> _sha256File(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

String _safeExtension(String path) {
  final extension = p.extension(path).toLowerCase();
  return RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension) ? extension : '';
}

String _mediaMimeType(String path) {
  return switch (_safeExtension(path)) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    '.heic' => 'image/heic',
    '.m4a' => 'audio/mp4',
    '.aac' => 'audio/aac',
    '.mp3' => 'audio/mpeg',
    '.wav' => 'audio/wav',
    _ => 'application/octet-stream',
  };
}

bool _isImagePath(String path) {
  return switch (_safeExtension(path)) {
    '.jpg' || '.jpeg' || '.png' || '.webp' || '.heic' => true,
    _ => false,
  };
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
