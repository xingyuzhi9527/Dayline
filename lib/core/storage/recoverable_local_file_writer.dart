import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Replaces a local file through same-directory sidecars so an interrupted
/// write can be repaired on the next read or write.
class RecoverableLocalFileWriter {
  const RecoverableLocalFileWriter();

  static const _temporarySuffix = '.liflow-tmp';
  static const _backupSuffix = '.liflow-backup';

  static final Map<String, Future<void>> _operationTails = {};

  Future<void> writeText(String targetPath, String content) async {
    await _replace(
      targetPath,
      (temporaryPath) =>
          File(temporaryPath).writeAsString(content, flush: true),
    );
  }

  Future<void> copyFile({
    required String sourcePath,
    required String targetPath,
  }) async {
    if (p.normalize(sourcePath) == p.normalize(targetPath)) {
      if (await File(sourcePath).exists()) return;
      throw FileSystemException('Source file not found', sourcePath);
    }
    await _replace(targetPath, (temporaryPath) async {
      await File(sourcePath).copy(temporaryPath);
      // File.copy closes its handles, but opening and flushing the temporary
      // file makes the durability boundary explicit before promotion.
      final handle = await File(temporaryPath).open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
    });
  }

  Future<void> recover(String targetPath) async {
    await _withOperationLock(targetPath, () => _recoverUnlocked(targetPath));
  }

  Future<void> _replace(
    String targetPath,
    Future<void> Function(String temporaryPath) prepareTemporary,
  ) async {
    await _withOperationLock(targetPath, () async {
      final target = File(targetPath);
      final temporary = File(_temporaryPath(targetPath));
      final backup = File(_backupPath(targetPath));
      await target.parent.create(recursive: true);
      await _recoverUnlocked(targetPath);

      var hadOriginal = await target.exists();
      var promoted = false;
      try {
        await _deleteIfExists(temporary);
        await prepareTemporary(temporary.path);

        hadOriginal = await target.exists();
        if (hadOriginal) {
          await _deleteIfExists(backup);
          await target.rename(backup.path);
        }

        await temporary.rename(target.path);
        promoted = true;
      } catch (error, stackTrace) {
        await _rollback(
          target: target,
          temporary: temporary,
          backup: backup,
          hadOriginal: hadOriginal,
          promoted: promoted,
        );
        Error.throwWithStackTrace(error, stackTrace);
      }

      // Promotion is already complete. A cleanup failure must not turn a
      // successful content write into an apparent failed write; the next
      // operation will repair any remaining sidecar.
      await _deleteIfExists(temporary, ignoreErrors: true);
      await _deleteIfExists(backup, ignoreErrors: true);
    });
  }

  Future<void> _recoverUnlocked(String targetPath) async {
    final target = File(targetPath);
    final temporary = File(_temporaryPath(targetPath));
    final backup = File(_backupPath(targetPath));
    final targetExists = await target.exists();
    final backupExists = await backup.exists();

    if (backupExists) {
      if (targetExists) {
        // The new file was promoted before the process stopped. Keep it and
        // discard the old copy.
        await _deleteIfExists(backup);
      } else {
        // The old file was moved aside but the replacement never landed.
        await backup.rename(target.path);
      }
    }

    // A temporary file is never authoritative. It can be left behind when
    // writing or promotion was interrupted, so always discard it.
    await _deleteIfExists(temporary);
  }

  Future<void> _rollback({
    required File target,
    required File temporary,
    required File backup,
    required bool hadOriginal,
    required bool promoted,
  }) async {
    await _deleteIfExists(temporary, ignoreErrors: true);
    if (promoted) {
      // The replacement is valid once promoted. Keep it and remove the old
      // backup; this branch only matters if a post-promotion cleanup failed.
      await _deleteIfExists(backup, ignoreErrors: true);
      return;
    }

    if (hadOriginal && await backup.exists() && !await target.exists()) {
      try {
        await backup.rename(target.path);
      } catch (_) {
        // Preserve the original error. A later operation can retry recovery.
      }
    }
  }

  Future<T> _withOperationLock<T>(
    String targetPath,
    Future<T> Function() action,
  ) async {
    final key = p.normalize(targetPath);
    final previous = _operationTails[key] ?? Future<void>.value();
    final gate = Completer<void>();
    _operationTails[key] = gate.future;
    try {
      await previous;
      return await action();
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (identical(_operationTails[key], gate.future)) {
        _operationTails.remove(key);
      }
    }
  }

  Future<void> _deleteIfExists(File file, {bool ignoreErrors = false}) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      if (!ignoreErrors) rethrow;
    }
  }

  String _temporaryPath(String targetPath) => '$targetPath$_temporarySuffix';

  String _backupPath(String targetPath) => '$targetPath$_backupSuffix';
}
