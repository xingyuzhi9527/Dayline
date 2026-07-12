import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../database/repositories.dart';
import '../database/repository_providers.dart';
import '../markdown/markdown_directory_service.dart';
import '../markdown/markdown_filename.dart';
import '../storage/recoverable_local_file_writer.dart';

final photoMomentServiceProvider = Provider<PhotoMomentService>((ref) {
  final settings = ref.watch(appSettingsRepositoryProvider);
  final directoryService = MarkdownDirectoryService(settings);
  return PhotoMomentService(
    recordsRepository: ref.watch(recordsRepositoryProvider),
    mediaAttachmentsRepository: ref.watch(mediaAttachmentsRepositoryProvider),
    directoryService: directoryService,
  );
});

class PhotoMomentService {
  PhotoMomentService({
    required RecordsRepository recordsRepository,
    required MediaAttachmentsRepository mediaAttachmentsRepository,
    required MarkdownDirectoryService directoryService,
  }) : _recordsRepository = recordsRepository,
       _mediaAttachmentsRepository = mediaAttachmentsRepository,
       _directoryService = directoryService;

  final RecordsRepository _recordsRepository;
  final MediaAttachmentsRepository _mediaAttachmentsRepository;
  final MarkdownDirectoryService _directoryService;
  static const _localFileWriter = RecoverableLocalFileWriter();

  Future<int> createFromCameraCapture({
    required String sourceImagePath,
    String note = '',
    List<String> tags = const [],
    DateTime? createdAt,
  }) async {
    final writtenAt = createdAt ?? DateTime.now();
    final storedPath = await _copyPhotoToLibrary(sourceImagePath, writtenAt);

    final recordId = await _recordsRepository.create(
      date: writtenAt,
      type: 'moment_photo',
      content: note.trim(),
      tags: _normalizeTags(tags),
      metadata: const {'source': 'camera'},
      createdAt: writtenAt,
    );

    try {
      await _mediaAttachmentsRepository.create(
        recordId: recordId,
        mediaType: 'image',
        sourceType: 'camera',
        localPath: storedPath,
        sortOrder: 0,
        createdAt: writtenAt,
      );
    } catch (_) {
      await _recordsRepository.permanentDelete(recordId);
      rethrow;
    }

    await _cleanupTempCapture(sourceImagePath, storedPath);
    return recordId;
  }

  Future<int> createFromImageSelection({
    required List<String> sourceImagePaths,
    String note = '',
    List<String> tags = const [],
    DateTime? createdAt,
  }) async {
    if (sourceImagePaths.isEmpty) {
      throw StateError('No photos selected.');
    }

    final writtenAt = createdAt ?? DateTime.now();
    final storedPaths = await _copyPhotosToLibrary(sourceImagePaths, writtenAt);

    final recordId = await _recordsRepository.create(
      date: writtenAt,
      type: 'moment_photo',
      content: note.trim(),
      tags: _normalizeTags(tags),
      metadata: {'source': 'gallery', 'photoCount': storedPaths.length},
      createdAt: writtenAt,
    );

    try {
      for (var index = 0; index < storedPaths.length; index += 1) {
        await _mediaAttachmentsRepository.create(
          recordId: recordId,
          mediaType: 'image',
          sourceType: 'gallery',
          localPath: storedPaths[index],
          sortOrder: index,
          createdAt: writtenAt,
        );
      }
    } catch (_) {
      await _recordsRepository.permanentDelete(recordId);
      for (final path in storedPaths) {
        await _deleteFileIfExists(path);
      }
      rethrow;
    }

    return recordId;
  }

  Future<int> createExpenseReceipt({
    required String sourceImagePath,
    required String expenseName,
    double? expenseAmount,
    List<int> expenseIds = const [],
    DateTime? createdAt,
    String? operationId,
  }) async {
    final writtenAt = createdAt ?? DateTime.now();
    final cleanedName = expenseName.trim().isEmpty ? '消费' : expenseName.trim();
    final filenameLabel = expenseAmount == null
        ? cleanedName
        : '${cleanedName}_${_formatExpenseAmount(expenseAmount)}';
    final storedPath = await _copyReceiptToLibrary(
      sourceImagePath,
      writtenAt,
      filenameLabel: filenameLabel,
      operationId: operationId,
    );

    int? recordId;
    try {
      recordId = await _recordsRepository.create(
        date: writtenAt,
        type: 'moment_photo',
        content: '消费凭证：$cleanedName',
        tags: const ['消费', '报销'],
        metadata: {
          'source': 'expense_receipt',
          if (expenseIds.isNotEmpty) 'linkedExpenseIds': expenseIds,
          if (operationId != null && operationId.trim().isNotEmpty)
            'writeOperationId': operationId,
        },
        createdAt: writtenAt,
      );
      await _mediaAttachmentsRepository.create(
        recordId: recordId,
        mediaType: 'image',
        sourceType: 'expense_receipt',
        localPath: storedPath,
        sortOrder: 0,
        createdAt: writtenAt,
      );
    } catch (_) {
      if (recordId != null) {
        await _recordsRepository.permanentDelete(recordId);
      }
      await _deleteFileIfExists(storedPath);
      rethrow;
    }
    return recordId;
  }

  Future<int> syncPrivatePhotoCopiesToVisibleDocuments() async => 0;

  Future<void> updatePhotoMoment({
    required int recordId,
    required String note,
    required List<String> tags,
  }) async {
    final existing = await _recordsRepository.findById(recordId);
    if (existing == null) {
      throw StateError('Photo moment record $recordId not found.');
    }

    await _recordsRepository.updateDetails(
      recordId,
      content: note.trim(),
      time: existing['time'] as String?,
      tags: _normalizeTags(tags),
      metadata: _decodeMetadata(existing['metadata']),
    );
  }

  Future<void> softDeletePhotoMoment(int recordId) {
    return _recordsRepository.softDelete(recordId);
  }

  Future<void> permanentlyDeletePhotoMoment(int recordId) async {
    final attachments = await _mediaAttachmentsRepository.findByRecordId(
      recordId,
    );
    await _recordsRepository.permanentDelete(recordId);

    for (final attachment in attachments) {
      await _deleteFileIfExists(attachment['local_path'] as String?);
      await _deleteFileIfExists(attachment['thumbnail_path'] as String?);
    }
  }

  Future<String> _copyPhotoToLibrary(
    String sourceImagePath,
    DateTime writtenAt, {
    String? filenameLabel,
  }) async {
    final sourceFile = File(sourceImagePath);
    if (!await sourceFile.exists()) {
      throw StateError('Captured photo not found: $sourceImagePath');
    }

    final photoDir = await _directoryService.ensurePhotoAttachmentsDir(
      writtenAt,
    );
    final extension = p.extension(sourceImagePath).toLowerCase();
    final safeExtension = extension.isEmpty ? '.jpg' : extension;
    final filename = filenameLabel == null || filenameLabel.trim().isEmpty
        ? _buildPhotoFilename(writtenAt, safeExtension)
        : _buildNamedPhotoFilename(filenameLabel, writtenAt, safeExtension);
    final targetPath = p.join(photoDir, filename);

    await _localFileWriter.copyFile(
      sourcePath: sourceFile.path,
      targetPath: targetPath,
    );
    return targetPath;
  }

  Future<String> _copyReceiptToLibrary(
    String sourceImagePath,
    DateTime writtenAt, {
    String? filenameLabel,
    String? operationId,
  }) async {
    final sourceFile = File(sourceImagePath);
    if (!await sourceFile.exists()) {
      throw StateError('Receipt photo not found: $sourceImagePath');
    }

    final receiptDir = await _directoryService.ensureReceiptAttachmentsDir(
      writtenAt,
    );
    final extension = p.extension(sourceImagePath).toLowerCase();
    final safeExtension = extension.isEmpty ? '.jpg' : extension;
    final filename = filenameLabel == null || filenameLabel.trim().isEmpty
        ? _buildPhotoFilename(writtenAt, safeExtension)
        : _buildNamedPhotoFilename(
            filenameLabel,
            writtenAt,
            safeExtension,
            uniqueSuffix: operationId,
          );
    final candidatePath = p.join(receiptDir, filename);
    final targetPath = operationId == null || operationId.trim().isEmpty
        ? await _availableTargetPath(candidatePath)
        : candidatePath;

    await _localFileWriter.copyFile(
      sourcePath: sourceFile.path,
      targetPath: targetPath,
    );
    return targetPath;
  }

  Future<List<String>> _copyPhotosToLibrary(
    List<String> sourceImagePaths,
    DateTime writtenAt,
  ) async {
    if (sourceImagePaths.length == 1) {
      return [await _copyPhotoToLibrary(sourceImagePaths.single, writtenAt)];
    }

    final photoDir = await _directoryService.ensurePhotoAttachmentsDir(
      writtenAt,
    );
    final folderName = p.basenameWithoutExtension(
      _buildPhotoFilename(writtenAt, '.jpg'),
    );
    final targetDir = Directory(p.join(photoDir, folderName));
    await targetDir.create(recursive: true);

    final storedPaths = <String>[];
    final usedNames = <String>{};
    for (final sourceImagePath in sourceImagePaths) {
      final sourceFile = File(sourceImagePath);
      if (!await sourceFile.exists()) {
        throw StateError('Selected photo not found: $sourceImagePath');
      }

      final basename = _uniqueBasename(p.basename(sourceImagePath), usedNames);
      final targetPath = p.join(targetDir.path, basename);
      await _localFileWriter.copyFile(
        sourcePath: sourceFile.path,
        targetPath: targetPath,
      );
      storedPaths.add(targetPath);
    }
    return storedPaths;
  }

  String _buildPhotoFilename(DateTime writtenAt, String extension) {
    final date = [
      writtenAt.year.toString().padLeft(4, '0'),
      writtenAt.month.toString().padLeft(2, '0'),
      writtenAt.day.toString().padLeft(2, '0'),
    ].join('');
    final time = [
      writtenAt.hour.toString().padLeft(2, '0'),
      writtenAt.minute.toString().padLeft(2, '0'),
      writtenAt.second.toString().padLeft(2, '0'),
    ].join('');
    final millis = writtenAt.millisecond.toString().padLeft(3, '0');
    return 'photo_${date}_$time$millis$extension';
  }

  String _buildNamedPhotoFilename(
    String label,
    DateTime writtenAt,
    String extension, {
    String? uniqueSuffix,
  }) {
    final safeName = MarkdownFilename.sanitize(
      label,
    ).replaceAll(RegExp(r'\s+'), '_').trim();
    final date = [
      writtenAt.year.toString().padLeft(4, '0'),
      writtenAt.month.toString().padLeft(2, '0'),
      writtenAt.day.toString().padLeft(2, '0'),
    ].join('');
    final time = [
      writtenAt.hour.toString().padLeft(2, '0'),
      writtenAt.minute.toString().padLeft(2, '0'),
      writtenAt.second.toString().padLeft(2, '0'),
    ].join('');
    final name = safeName.isEmpty ? '消费' : safeName;
    final suffix = _safeFilenameSuffix(uniqueSuffix);
    return '${name}_${date}_$time${suffix == null ? '' : '_$suffix'}$extension';
  }

  String? _safeFilenameSuffix(String? value) {
    final sanitized = value?.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (sanitized == null || sanitized.isEmpty) return null;
    return sanitized.length <= 16
        ? sanitized
        : sanitized.substring(sanitized.length - 16);
  }

  Future<String> _availableTargetPath(String candidatePath) async {
    if (!await File(candidatePath).exists()) return candidatePath;

    final extension = p.extension(candidatePath);
    final stem = p.basenameWithoutExtension(candidatePath);
    final parent = p.dirname(candidatePath);
    var index = 2;
    while (true) {
      final path = p.join(parent, '$stem-$index$extension');
      if (!await File(path).exists()) return path;
      index += 1;
    }
  }

  String _uniqueBasename(String basename, Set<String> usedNames) {
    final fallback = basename.trim().isEmpty ? 'photo.jpg' : basename.trim();
    if (usedNames.add(fallback)) return fallback;

    final extension = p.extension(fallback);
    final stem = p.basenameWithoutExtension(fallback);
    var index = 2;
    while (true) {
      final candidate = '$stem-$index$extension';
      if (usedNames.add(candidate)) return candidate;
      index += 1;
    }
  }

  String _formatExpenseAmount(double amount) {
    final rounded = (amount * 100).round() / 100;
    if (rounded == rounded.truncateToDouble()) {
      return rounded.toStringAsFixed(0);
    }
    return rounded.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }

  Future<void> _cleanupTempCapture(
    String sourceImagePath,
    String storedPath,
  ) async {
    final normalizedSource = p.normalize(sourceImagePath);
    final normalizedStored = p.normalize(storedPath);
    if (normalizedSource == normalizedStored) return;

    try {
      final sourceFile = File(sourceImagePath);
      if (await sourceFile.exists()) {
        await sourceFile.delete();
      }
    } catch (_) {}
  }

  Future<void> _deleteFileIfExists(String? path) async {
    if (path == null || path.isEmpty) return;

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Map<String, Object?> _decodeMetadata(Object? raw) {
    if (raw is Map<String, Object?>) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return decoded.cast<String, Object?>();
      } catch (_) {
        return const {};
      }
    }
    return const {};
  }

  List<String> _normalizeTags(Iterable<String> tags) {
    final seen = <String>{};
    final normalized = <String>[];

    for (final tag in tags) {
      final value = tag
          .replaceFirst(RegExp(r'^[#＃]+'), '')
          .replaceAll(RegExp(r'\s+'), '')
          .trim();
      if (value.isEmpty || seen.contains(value)) continue;
      seen.add(value);
      normalized.add(value);
    }

    return normalized;
  }
}
