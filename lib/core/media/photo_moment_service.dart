import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../database/repositories.dart';
import '../database/repository_providers.dart';
import '../markdown/markdown_directory_service.dart';
import '../markdown/markdown_filename.dart';
import '../markdown/markdown_storage_service.dart';

final photoMomentServiceProvider = Provider<PhotoMomentService>((ref) {
  final settings = ref.watch(appSettingsRepositoryProvider);
  final directoryService = MarkdownDirectoryService(settings);
  return PhotoMomentService(
    recordsRepository: ref.watch(recordsRepositoryProvider),
    mediaAttachmentsRepository: ref.watch(mediaAttachmentsRepositoryProvider),
    directoryService: directoryService,
    storageService: MarkdownStorageService(directoryService),
  );
});

class PhotoMomentService {
  PhotoMomentService({
    required RecordsRepository recordsRepository,
    required MediaAttachmentsRepository mediaAttachmentsRepository,
    required MarkdownDirectoryService directoryService,
    MarkdownStorageService? storageService,
  }) : _recordsRepository = recordsRepository,
       _mediaAttachmentsRepository = mediaAttachmentsRepository,
       _directoryService = directoryService,
       _storageService =
           storageService ?? MarkdownStorageService(directoryService);

  final RecordsRepository _recordsRepository;
  final MediaAttachmentsRepository _mediaAttachmentsRepository;
  final MarkdownDirectoryService _directoryService;
  final MarkdownStorageService _storageService;

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

  Future<int> createExpenseReceipt({
    required String sourceImagePath,
    required String expenseName,
    double? expenseAmount,
    List<int> expenseIds = const [],
    DateTime? createdAt,
  }) async {
    final writtenAt = createdAt ?? DateTime.now();
    final cleanedName = expenseName.trim().isEmpty ? '消费' : expenseName.trim();
    final filenameLabel = expenseAmount == null
        ? cleanedName
        : '${cleanedName}_${_formatExpenseAmount(expenseAmount)}';
    final storedPath = await _copyPhotoToLibrary(
      sourceImagePath,
      writtenAt,
      filenameLabel: filenameLabel,
      copyToVisibleDocuments: false,
    );

    final recordId = await _recordsRepository.create(
      date: writtenAt,
      type: 'moment_photo',
      content: '消费凭证：$cleanedName',
      tags: const ['消费', '报销'],
      metadata: {
        'source': 'expense_receipt',
        if (expenseIds.isNotEmpty) 'linkedExpenseIds': expenseIds,
      },
      createdAt: writtenAt,
    );

    try {
      await _mediaAttachmentsRepository.create(
        recordId: recordId,
        mediaType: 'image',
        sourceType: 'expense_receipt',
        localPath: storedPath,
        sortOrder: 0,
        createdAt: writtenAt,
      );
    } catch (_) {
      await _recordsRepository.permanentDelete(recordId);
      rethrow;
    }
    return recordId;
  }

  Future<int> syncPrivatePhotoCopiesToVisibleDocuments() async {
    if (!Platform.isAndroid) return 0;
    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri == null || treeUri.isEmpty) return 0;

    var copied = 0;
    final attachments = await _mediaAttachmentsRepository.findAll();
    for (final attachment in attachments) {
      if (attachment['media_type'] != 'image') continue;
      if (attachment['source_type'] == 'expense_receipt') continue;

      final storedPath = attachment['local_path'] as String?;
      if (storedPath == null || storedPath.isEmpty) continue;

      final sourceFile = File(storedPath);
      if (!await sourceFile.exists()) continue;

      final createdAtMillis = attachment['created_at'] as int?;
      final writtenAt = createdAtMillis == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(createdAtMillis);
      final relativePath = _visiblePhotoRelativePath(storedPath, writtenAt);

      try {
        await _storageService.writeRelativeBinaryFile(
          relativePath: relativePath,
          sourcePath: storedPath,
          mimeType: _mimeTypeForPath(storedPath),
        );
        copied += 1;
      } catch (_) {
        // Keep the private copy usable even if the visible folder grant changed.
      }
    }
    return copied;
  }

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
    bool copyToVisibleDocuments = true,
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

    await sourceFile.copy(targetPath);
    if (copyToVisibleDocuments) {
      await _copyPhotoToVisibleDocuments(targetPath, writtenAt);
    }
    return targetPath;
  }

  Future<void> _copyPhotoToVisibleDocuments(
    String storedPath,
    DateTime writtenAt,
  ) async {
    if (!Platform.isAndroid) return;

    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri == null || treeUri.isEmpty) return;

    try {
      await _storageService.writeRelativeBinaryFile(
        relativePath: _visiblePhotoRelativePath(storedPath, writtenAt),
        sourcePath: storedPath,
        mimeType: _mimeTypeForPath(storedPath),
      );
    } catch (_) {
      // The timeline still uses the private copy; visible export is best-effort.
    }
  }

  String _visiblePhotoRelativePath(String path, DateTime writtenAt) {
    return p.posix.join(
      'documents',
      'photos',
      MarkdownFilename.monthDir(writtenAt),
      p.basename(path),
    );
  }

  String _mimeTypeForPath(String path) {
    final extension = p.extension(path).toLowerCase();
    return switch (extension) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.heic' || '.heif' => 'image/heic',
      _ => 'image/jpeg',
    };
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
    String extension,
  ) {
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
    return '${name}_${date}_$time$extension';
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
