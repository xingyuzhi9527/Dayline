import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../database/repositories.dart';
import '../database/repository_providers.dart';
import '../markdown/markdown_directory_service.dart';
import '../markdown/markdown_filename.dart';
import '../markdown/markdown_storage_service.dart';
import '../storage/recoverable_local_file_writer.dart';
import '../stt/stt_engine.dart';

final audioRecordingServiceProvider = Provider<AudioRecordingService>((ref) {
  final settings = ref.watch(appSettingsRepositoryProvider);
  final directoryService = MarkdownDirectoryService(settings);
  return AudioRecordingService(
    recordsRepository: ref.watch(recordsRepositoryProvider),
    mediaAttachmentsRepository: ref.watch(mediaAttachmentsRepositoryProvider),
    directoryService: directoryService,
    storageService: MarkdownStorageService(directoryService),
  );
});

class AudioRecordingService {
  AudioRecordingService({
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
  static const _localFileWriter = RecoverableLocalFileWriter();

  Future<int> createVoiceMemo({
    required SttRecordingDraft draft,
    String content = '',
    List<String> tags = const [],
    Map<String, Object?> metadata = const {},
    DateTime? createdAt,
    bool deleteDraftAfterAttach = true,
  }) async {
    final writtenAt = createdAt ?? DateTime.now();
    final recordId = await _recordsRepository.create(
      date: writtenAt,
      type: 'voice_memo',
      content: content.trim().isEmpty ? '语音片段' : content.trim(),
      tags: tags,
      metadata: {...metadata, 'source': 'voice', 'hasAudio': true},
      createdAt: writtenAt,
    );

    try {
      await attachDraftToRecord(
        recordId: recordId,
        draft: draft,
        writtenAt: writtenAt,
        deleteDraftAfterAttach: deleteDraftAfterAttach,
      );
    } catch (_) {
      await _recordsRepository.permanentDelete(recordId);
      rethrow;
    }

    return recordId;
  }

  Future<int> attachDraftToRecord({
    required int recordId,
    required SttRecordingDraft draft,
    DateTime? writtenAt,
    bool deleteDraftAfterAttach = true,
  }) async {
    final storedPath = await _copyAudioToLibrary(
      draft.path,
      writtenAt ?? DateTime.now(),
    );

    try {
      final attachmentId = await _mediaAttachmentsRepository.create(
        recordId: recordId,
        mediaType: 'audio',
        sourceType: 'voice',
        localPath: storedPath,
        durationMs: draft.duration.inMilliseconds,
        sortOrder: 0,
        createdAt: writtenAt,
      );
      if (deleteDraftAfterAttach) {
        await deleteDraftIfExists(draft);
      }
      return attachmentId;
    } catch (_) {
      await _deleteFileIfExists(storedPath);
      rethrow;
    }
  }

  Future<void> deleteDraftIfExists(SttRecordingDraft? draft) async {
    if (draft == null) return;
    await _deleteFileIfExists(draft.path);
  }

  Future<void> deleteAttachmentsForRecord(int recordId) async {
    final attachments = await _mediaAttachmentsRepository.findByRecordId(
      recordId,
    );
    for (final attachment in attachments) {
      if (attachment['media_type'] != 'audio') continue;
      await _deleteFileIfExists(attachment['local_path'] as String?);
      await _deleteFileIfExists(attachment['thumbnail_path'] as String?);
    }
  }

  Future<String> _copyAudioToLibrary(
    String sourceAudioPath,
    DateTime writtenAt,
  ) async {
    final sourceFile = File(sourceAudioPath);
    if (!await sourceFile.exists()) {
      throw StateError('Recorded audio not found: $sourceAudioPath');
    }

    final audioDir = await _directoryService.ensureAudioAttachmentsDir(
      writtenAt,
    );
    final extension = p.extension(sourceAudioPath).toLowerCase();
    final safeExtension = extension.isEmpty ? '.wav' : extension;
    final filename = _buildAudioFilename(writtenAt, safeExtension);
    final targetPath = p.join(audioDir, filename);

    await _localFileWriter.copyFile(
      sourcePath: sourceFile.path,
      targetPath: targetPath,
    );
    unawaited(_copyAudioToVisibleDocuments(targetPath, writtenAt));
    return targetPath;
  }

  Future<void> _copyAudioToVisibleDocuments(
    String storedPath,
    DateTime writtenAt,
  ) async {
    if (!Platform.isAndroid) return;

    final treeUri = await _directoryService.getTreeRootUri();
    if (treeUri == null || treeUri.isEmpty) return;

    try {
      await _storageService.writeRelativeBinaryFile(
        relativePath: _visibleAudioRelativePath(storedPath, writtenAt),
        sourcePath: storedPath,
        mimeType: _mimeTypeForPath(storedPath),
      );
    } catch (_) {
      // Keep the private copy usable even if the visible folder grant changed.
    }
  }

  String _visibleAudioRelativePath(String path, DateTime writtenAt) {
    return p.posix.join(
      'documents',
      'audio',
      MarkdownFilename.monthDir(writtenAt),
      p.basename(path),
    );
  }

  String _mimeTypeForPath(String path) {
    final extension = p.extension(path).toLowerCase();
    return switch (extension) {
      '.m4a' => 'audio/mp4',
      '.aac' => 'audio/aac',
      '.mp3' => 'audio/mpeg',
      _ => 'audio/wav',
    };
  }

  String _buildAudioFilename(DateTime writtenAt, String extension) {
    final date = [
      writtenAt.year.toString().padLeft(4, '0'),
      writtenAt.month.toString().padLeft(2, '0'),
      writtenAt.day.toString().padLeft(2, '0'),
    ].join();
    final time = [
      writtenAt.hour.toString().padLeft(2, '0'),
      writtenAt.minute.toString().padLeft(2, '0'),
      writtenAt.second.toString().padLeft(2, '0'),
    ].join();
    final millis = writtenAt.millisecond.toString().padLeft(3, '0');
    return 'audio_${date}_$time$millis$extension';
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
}
