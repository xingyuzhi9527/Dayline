import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/local_database.dart';
import '../../core/database/derived_sync_jobs_repository.dart';
import '../../core/database/repository_providers.dart';
import '../../core/database/write_operations_repository.dart';
import '../../core/media/audio_recording_service.dart';
import '../../core/media/photo_moment_service.dart';
import '../../core/performance/perf_trace.dart';
import '../../core/parser/expense_line_item.dart';
import '../../core/parser/expense_note_cleaner.dart';
import '../../core/parser/lui_lite_parser.dart';
import '../../core/parser/parsed_input_time.dart';
import '../../core/stt/stt_engine.dart';
import '../../core/stt/stt_providers.dart';
import '../dashboard/daily_note_draft.dart';
import '../monthly_expenses/monthly_expense_report_sync.dart';
import '../projects/project_store.dart';
import 'flash_record_state.dart';

final flashRecordProvider =
    NotifierProvider<FlashRecordNotifier, FlashRecordState>(
      FlashRecordNotifier.new,
    );

final flashSaveTimeoutProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 8);
});

class FlashRecordNotifier extends Notifier<FlashRecordState> {
  static const _parsedWriteOperationType = 'flash_record.parsed.v2';
  static const _audioWriteOperationType = 'flash_record.audio.v2';
  static const _dailyDraftSyncJobType = 'daily_draft';
  static const _monthlyExpenseSyncJobType = 'monthly_expense_report';
  static const _projectFlashArchiveSyncJobType = 'project_flash_archive';
  static final _riskyAmountMemoContext = RegExp(
    r'(工资|薪资|收入|房贷|申报|报销|预算|以上|以内|不超过|至少|额度|规则)',
  );
  static final _technicalMemoContext = RegExp(
    r'(文件|测试|规则|git|刷新|检测|发现|代码|项目|需求|bug|修复|优化|功能)',
    caseSensitive: false,
  );
  static final _amountToken = RegExp(
    r'(?:¥|￥|RMB)\s*\d+(?:\.\d+)?|\d+(?:\.\d+)?\s*(?:元|块|块钱)',
    caseSensitive: false,
  );

  late SttEngine _sttEngine;
  SttListenSession? _sttSession;
  StreamSubscription<SttTranscript>? _sttSub;
  SttRecordingDraft? _recordingDraft;
  AudioRecordingService? _audioRecordingService;
  Future<void>? _saveInFlight;
  Future<void>? _derivedSyncDrainInFlight;
  bool _disposed = false;
  int _listenRequestId = 0;

  @override
  FlashRecordState build() {
    _disposed = false;
    _sttEngine = ref.watch(sttEngineProvider);
    unawaited(Future<void>.microtask(_drainDerivedSyncJobsSafely));
    ref.onDispose(() {
      _disposed = true;
      unawaited(_sttSub?.cancel());
      unawaited(_sttSession?.cancel());
      unawaited(_audioRecordingService?.deleteDraftIfExists(_recordingDraft));
    });
    return const FlashRecordState();
  }

  Future<SttAvailability> _initializeStt() async {
    if (!_disposed && state.sttStatus != SttAvailabilityStatus.ready) {
      state = state.copyWith(
        sttStatus: SttAvailabilityStatus.loading,
        sttStatusMessage: const SttAvailability.loading().message,
        errorMessage: null,
      );
    }
    final availability = await _sttEngine.initialize();
    if (_disposed) return availability;
    state = state.copyWith(
      sttStatus: availability.status,
      sttStatusMessage: availability.message,
    );
    return availability;
  }

  // ---- voice path ----

  void setRecordingMode(FlashRecordingMode mode) {
    if (state.phase == FlashPhase.listening ||
        state.phase == FlashPhase.saving) {
      return;
    }
    state = state.copyWith(recordingMode: mode, errorMessage: null);
  }

  Future<void> startListening() async {
    if (_saveInFlight != null) return;
    if (!await _releaseCompletedOperationForNewText('')) return;

    final requestId = ++_listenRequestId;
    await _discardRecordingDraft();
    _recordingDraft = null;
    state = state.copyWith(
      phase: FlashPhase.listening,
      rawText: '',
      partialText: '',
      audioLevel: 0,
      parsedInput: null,
      errorMessage: null,
      source: 'voice',
      transcriptFinal: false,
      recordingDraft: null,
      selectedProjectId: null,
      expenseReceiptImagePath: null,
    );

    final shouldTranscribe =
        state.recordingMode == FlashRecordingMode.transcribe;
    if (shouldTranscribe) {
      final availability = state.sttStatus == SttAvailabilityStatus.ready
          ? const SttAvailability.ready()
          : await _initializeStt();

      if (_disposed || requestId != _listenRequestId) return;

      if (!availability.isReady) {
        state = state.copyWith(
          phase: FlashPhase.idle,
          errorMessage: kDebugMode ? availability.message : '离线语音暂不可用，请使用文字记录',
        );
        return;
      }
    }

    try {
      await _sttSub?.cancel();
      await _sttSession?.cancel();

      final session = await _sttEngine.startListening(
        transcribe: shouldTranscribe,
      );
      if (_disposed || requestId != _listenRequestId) {
        await session.cancel();
        return;
      }

      _sttSession = session;
      _sttSub = session.transcripts.listen((transcript) {
        _handleTranscript(requestId, transcript);
      });
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        phase: FlashPhase.idle,
        errorMessage: _friendlySttError(e),
      );
    }
  }

  Future<void> stopListening() async {
    if (state.phase != FlashPhase.listening) return;

    ++_listenRequestId;
    final session = _sttSession;
    if (session == null) {
      state = state.copyWith(
        phase: FlashPhase.idle,
        errorMessage: '离线语音还没有开始，请再试一次。',
      );
      return;
    }

    try {
      final shouldTranscribe =
          state.recordingMode == FlashRecordingMode.transcribe;
      final transcript = await session.stop(transcribe: shouldTranscribe);
      if (_disposed) return;
      _completeTranscript(transcript, transcribed: shouldTranscribe);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        phase: FlashPhase.idle,
        errorMessage: '语音停止失败：${_friendlySttError(e)}',
      );
    }
  }

  void _handleTranscript(int requestId, SttTranscript transcript) {
    if (_disposed || requestId != _listenRequestId) return;
    if (state.phase != FlashPhase.listening) return;

    if (transcript.isFinal) {
      _completeTranscript(
        transcript,
        transcribed: state.recordingMode == FlashRecordingMode.transcribe,
      );
      return;
    }

    final text = transcript.text.trim();
    state = state.copyWith(
      rawText: text.isNotEmpty ? text : state.rawText,
      partialText: text,
      audioLevel: transcript.audioLevel,
      sttMetadata: transcript.metadata,
      transcriptFinal: false,
      errorMessage: null,
    );
  }

  void _completeTranscript(
    SttTranscript transcript, {
    required bool transcribed,
  }) {
    final recognizedText = transcript.text.trim();
    final draft = transcript.recordingDraft;
    if (transcribed) {
      if (recognizedText.isEmpty) {
        if (draft != null) {
          unawaited(_audioService().deleteDraftIfExists(draft));
        }
        _recordingDraft = null;
        state = state.copyWith(
          phase: FlashPhase.idle,
          rawText: '',
          partialText: '',
          audioLevel: 0,
          parsedInput: null,
          sttMetadata: transcript.metadata,
          transcriptFinal: true,
          recordingDraft: null,
          errorMessage: '没有听清，再按住说一次。',
        );
        return;
      }
      if (draft != null) {
        unawaited(_audioService().deleteDraftIfExists(draft));
      }
      _recordingDraft = null;
      final parsed = LuiLiteParser.parse(recognizedText);
      state = state.copyWith(
        phase: FlashPhase.confirming,
        rawText: recognizedText,
        partialText: recognizedText,
        audioLevel: 0,
        parsedInput: parsed,
        sttMetadata: transcript.metadata,
        transcriptFinal: true,
        recordingDraft: null,
        errorMessage: null,
      );
      return;
    }

    if (draft != null) {
      _recordingDraft = draft;
      _audioService();
      state = state.copyWith(
        phase: FlashPhase.recognized,
        rawText: recognizedText,
        partialText: recognizedText,
        audioLevel: 0,
        parsedInput: null,
        sttMetadata: transcript.metadata,
        transcriptFinal: true,
        recordingDraft: draft,
        errorMessage: null,
      );
      unawaited(saveAudioOnly());
      return;
    }

    state = state.copyWith(
      phase: FlashPhase.idle,
      rawText: '',
      partialText: '',
      audioLevel: 0,
      errorMessage: '没有听清，再按住说一次。',
    );
  }

  String _friendlySttError(Object error) {
    final message = error.toString();
    if (message.contains('麦克风权限')) {
      return '麦克风权限未开启，请允许 Liflow 使用麦克风。';
    }
    return message;
  }

  // ---- confirm / save flow ----

  void confirmParsed([String? editedText]) {
    final textToParse = editedText ?? state.rawText;
    final parsed = LuiLiteParser.parse(textToParse);
    state = state.copyWith(
      phase: FlashPhase.confirming,
      parsedInput: parsed,
      rawText: textToParse,
    );
  }

  void switchParsedType(ParsedInputType newType) {
    final parsed = state.parsedInput;
    if (parsed == null || parsed.type == newType) return;
    if (newType == ParsedInputType.expense) {
      final reparsed = LuiLiteParser.parse(state.rawText.trim());
      if (reparsed.type == ParsedInputType.expense) {
        state = state.copyWith(
          parsedInput: reparsed.copyWith(
            type: newType,
            confidence: 1,
            tags: parsed.tags.isEmpty ? reparsed.tags : parsed.tags,
          ),
        );
        return;
      }
    }
    state = state.copyWith(
      parsedInput: parsed.copyWith(type: newType, confidence: 1),
    );
  }

  void updateParsedText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(rawText: text, errorMessage: null);
      return;
    }

    state = state.copyWith(
      rawText: text,
      parsedInput: LuiLiteParser.parse(trimmed),
      errorMessage: null,
    );
  }

  void updateParsedTags(List<String> tags) {
    final parsed = state.parsedInput;
    if (parsed == null) return;

    state = state.copyWith(
      parsedInput: parsed.copyWith(tags: _normalizeTags(tags)),
      errorMessage: null,
    );
  }

  void updateExpenseItems(List<ExpenseLineItem> items) {
    final parsed = state.parsedInput;
    if (parsed == null) return;

    state = state.copyWith(
      parsedInput: parsed.copyWith(
        metadata: expenseMetadataForItems(items, base: parsed.metadata),
      ),
      errorMessage: null,
    );
  }

  void setExpenseReceiptImagePath(String? path) {
    state = state.copyWith(expenseReceiptImagePath: path, errorMessage: null);
  }

  void selectProject(String? projectId) {
    state = state.copyWith(selectedProjectId: projectId, errorMessage: null);
  }

  void cancelConfirm() {
    if (_saveInFlight != null) {
      state = state.copyWith(errorMessage: '保存仍在处理，请稍候。');
      return;
    }
    unawaited(_cancelConfirmWhenIdle());
  }

  Future<void> _cancelConfirmWhenIdle() async {
    final operationId = state.saveOperationId;
    if (operationId != null) {
      final operation = await ref
          .read(writeOperationsRepositoryProvider)
          .findById(operationId);
      if (operation?.status == WriteOperationStatus.committed) {
        if (!_disposed) {
          state = state.copyWith(errorMessage: '记录已写入，正在完成文件同步，请再次保存。');
        }
        return;
      }
    }

    await _discardRecordingDraft();
    if (_disposed) return;
    state = _idleStateKeepingStt();
    await _releaseOperation(operationId);
  }

  Future<void> save() async {
    final parsed = state.parsedInput;
    if (parsed == null || state.phase == FlashPhase.saved) return;

    final currentSave = _saveInFlight;
    if (currentSave != null) {
      await _waitForExistingSave(currentSave);
      return;
    }

    final draft = state.recordingDraft;
    final selectedProjectId = state.selectedProjectId;
    final receiptImagePath = state.expenseReceiptImagePath;
    final rawText = state.rawText;
    state = state.copyWith(phase: FlashPhase.saving, errorMessage: null);

    await _startSaveOperation(
      onTimeout: () {
        state = state.copyWith(
          phase: FlashPhase.saving,
          errorMessage: '保存仍在处理，请稍候。',
        );
      },
      operation: () async {
        try {
          if (draft != null) {
            _audioService();
          }
          final operation = await _prepareOperation(
            type: _parsedWriteOperationType,
            fingerprint: _parsedOperationFingerprint(
              parsed,
              rawText: rawText,
              selectedProjectId: selectedProjectId,
              receiptImagePath: receiptImagePath,
              recordingDraft: draft,
            ),
          );
          await _commitParsedOperation(
            operation,
            parsed,
            rawText: rawText,
            recordingDraft: draft,
            selectedProjectId: selectedProjectId,
            receiptImagePath: receiptImagePath,
          );
          if (_disposed) return;
          ref
              .read(dataVersionProvider.notifier)
              .increment(
                domains: _domainsForParsedInput(
                  parsed,
                  hasAudio: draft != null,
                  hasReceipt: receiptImagePath?.trim().isNotEmpty == true,
                  projectEntry: selectedProjectId != null,
                ),
              );
          _recordingDraft = null;
          state = state.copyWith(
            phase: FlashPhase.saved,
            recordingDraft: null,
            selectedProjectId: null,
            expenseReceiptImagePath: null,
            saveOperationId: operation.id,
            errorMessage: null,
          );
        } catch (e) {
          if (_disposed) return;
          state = state.copyWith(
            phase: FlashPhase.confirming,
            errorMessage: e.toString(),
          );
        }
      },
    );
  }

  void resetAfterSaved() {
    final operationId = state.saveOperationId;
    state = _idleStateKeepingStt();
    unawaited(_acknowledgeOperation(operationId));
  }

  FlashRecordState _idleStateKeepingStt() {
    return FlashRecordState(
      sttStatus: state.sttStatus,
      sttStatusMessage: state.sttStatusMessage,
      recordingMode: state.recordingMode,
      saveOperationId: null,
    );
  }

  Future<void> saveAudioOnly() async {
    final currentSave = _saveInFlight;
    if (currentSave != null) {
      await _waitForExistingSave(currentSave);
      return;
    }

    if (!await _releaseCompletedOperationForNewText('')) return;

    final draft = state.recordingDraft;
    if (draft == null) {
      state = state.copyWith(errorMessage: '没有可保存的录音。');
      return;
    }

    final content = state.rawText;
    state = state.copyWith(phase: FlashPhase.saving, errorMessage: null);

    await _startSaveOperation(
      onTimeout: () {
        state = state.copyWith(
          phase: FlashPhase.saving,
          errorMessage: '保存仍在处理，请稍候。',
        );
      },
      operation: () async {
        try {
          final operation = await _prepareOperation(
            type: _audioWriteOperationType,
            fingerprint: _audioOperationFingerprint(draft, content),
          );
          await _commitAudioOperation(
            operation,
            draft: draft,
            content: content,
          );
          if (_disposed) return;
          ref
              .read(dataVersionProvider.notifier)
              .increment(domains: const {DataDomain.records, DataDomain.media});
          _recordingDraft = null;
          state = state.copyWith(
            phase: FlashPhase.saved,
            recordingDraft: null,
            saveOperationId: operation.id,
            errorMessage: null,
          );
        } catch (e) {
          if (_disposed) return;
          state = state.copyWith(
            phase: FlashPhase.recognized,
            errorMessage: e.toString(),
          );
        }
      },
    );
  }

  // ---- text path ----

  Future<void> saveAsText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final currentSave = _saveInFlight;
    if (currentSave != null) {
      await _waitForExistingSave(currentSave);
      return;
    }

    if (!await _releaseCompletedOperationForNewText(trimmed)) return;

    final parsed = LuiLiteParser.parse(trimmed);
    if (_requiresTextConfirmation(trimmed, parsed)) {
      state = state.copyWith(
        phase: FlashPhase.confirming,
        rawText: trimmed,
        source: 'text',
        parsedInput: parsed,
        textSaving: false,
        errorMessage: null,
      );
      return;
    }

    state = state.copyWith(
      phase: FlashPhase.idle,
      rawText: trimmed,
      source: 'text',
      parsedInput: parsed,
      textSaving: true,
      errorMessage: null,
    );

    await _startSaveOperation(
      onTimeout: () {
        state = state.copyWith(
          phase: FlashPhase.idle,
          textSaving: true,
          errorMessage: '保存仍在处理，请稍候。',
        );
      },
      operation: () async {
        try {
          final operation = await _prepareOperation(
            type: _parsedWriteOperationType,
            fingerprint: _parsedOperationFingerprint(parsed, rawText: trimmed),
          );
          await _commitParsedOperation(operation, parsed, rawText: trimmed);
          if (_disposed) return;
          ref
              .read(dataVersionProvider.notifier)
              .incrementSoon(domains: _domainsForParsedInput(parsed));
          state = state.copyWith(
            phase: FlashPhase.idle,
            rawText: '',
            parsedInput: null,
            textSaving: false,
            savedSequence: state.savedSequence + 1,
            saveOperationId: operation.id,
            errorMessage: null,
          );
        } catch (e) {
          if (_disposed) return;
          state = state.copyWith(
            phase: FlashPhase.idle,
            textSaving: false,
            errorMessage: e.toString(),
          );
        }
      },
    );
  }

  Future<void> _startSaveOperation({
    required Future<void> Function() operation,
    required void Function() onTimeout,
  }) async {
    late final Future<void> tracked;
    tracked = Future<void>.sync(operation).whenComplete(() {
      if (identical(_saveInFlight, tracked)) {
        _saveInFlight = null;
      }
    });
    _saveInFlight = tracked;
    await _waitForSave(tracked, onTimeout: onTimeout);
  }

  Future<void> _waitForExistingSave(Future<void> operation) async {
    await _waitForSave(
      operation,
      onTimeout: () {
        state = state.copyWith(errorMessage: '上一次保存仍在处理，请稍候。');
      },
    );
  }

  Future<void> _waitForSave(
    Future<void> operation, {
    required void Function() onTimeout,
  }) async {
    try {
      await operation.timeout(ref.read(flashSaveTimeoutProvider));
    } on TimeoutException {
      if (!_disposed) onTimeout();
    }
  }

  Future<WriteOperation> _prepareOperation({
    required String type,
    required String fingerprint,
  }) async {
    final repository = ref.read(writeOperationsRepositoryProvider);
    final preferredId = state.saveOperationId;
    if (preferredId != null && preferredId.trim().isNotEmpty) {
      final preferred = await repository.findById(preferredId);
      if (preferred != null &&
          preferred.type == type &&
          preferred.fingerprint == fingerprint) {
        return preferred;
      }

      if (preferred != null) {
        if (preferred.isCompleted) {
          await repository.acknowledge(preferred.id);
        } else if (preferred.isCommitted) {
          throw StateError('上一条保存已写入，正在完成派生文件同步，请稍候重试。');
        }
      }
      if (!_disposed) {
        state = state.copyWith(saveOperationId: null);
      }
    }

    final prepared = await repository.prepare(
      type: type,
      fingerprint: fingerprint,
    );
    if (!_disposed) {
      state = state.copyWith(saveOperationId: prepared.id);
    }
    return prepared;
  }

  Future<bool> _commitParsedOperation(
    WriteOperation operation,
    ParsedInput parsed, {
    required String rawText,
    SttRecordingDraft? recordingDraft,
    String? selectedProjectId,
    String? receiptImagePath,
  }) async {
    final operations = ref.read(writeOperationsRepositoryProvider);
    var current = await operations.findById(operation.id);
    if (current == null) {
      throw StateError('保存请求已不存在，请重新保存。');
    }

    if (!current.isCommitted) {
      current = await ref.read(localDatabaseProvider).transaction(() async {
        final latest = await operations.findById(operation.id);
        if (latest == null) {
          throw StateError('保存请求已不存在，请重新保存。');
        }
        if (latest.isCommitted) return latest;

        final draftConsumed = await _persist(
          parsed,
          operationId: latest.id,
          operationStartedAt: latest.createdAt,
          rawText: rawText,
          recordingDraft: recordingDraft,
          selectedProjectId: selectedProjectId,
          receiptImagePath: receiptImagePath,
        );
        await _enqueueParsedOperationMirrorJobs(
          latest,
          parsed,
          rawText: rawText,
          selectedProjectId: selectedProjectId,
        );
        return operations.markCommitted(
          operation.id,
          result: {'draftConsumed': draftConsumed},
        );
      });
    }

    if (!current.isCompleted) {
      current = await operations.markCompleted(operation.id);
      unawaited(_drainDerivedSyncJobsSafely());
      unawaited(_cleanupConsumedDraft(current, recordingDraft));
    }

    return current.result['draftConsumed'] == true;
  }

  Future<void> _enqueueParsedOperationMirrorJobs(
    WriteOperation operation,
    ParsedInput parsed, {
    required String rawText,
    String? selectedProjectId,
  }) async {
    final jobs = ref.read(derivedSyncJobsRepositoryProvider);
    await jobs.enqueue(
      key: 'daily:${_dateKey(operation.createdAt)}',
      type: _dailyDraftSyncJobType,
      payload: {'updatedAt': operation.createdAt.millisecondsSinceEpoch},
      enqueuedAt: operation.createdAt,
    );

    if (selectedProjectId != null) {
      await jobs.enqueue(
        key: 'project:${operation.id}',
        type: _projectFlashArchiveSyncJobType,
        payload: {
          'projectId': selectedProjectId,
          'text': _projectEntryText(parsed, rawText),
          'isTodo': parsed.type == ParsedInputType.todo,
          'operationId': operation.id,
          'updatedAt': operation.createdAt.millisecondsSinceEpoch,
        },
        enqueuedAt: operation.createdAt,
      );
    }

    if (parsed.type == ParsedInputType.expense) {
      await jobs.enqueue(
        key: 'expense:${_monthKey(operation.createdAt)}',
        type: _monthlyExpenseSyncJobType,
        payload: {'date': operation.createdAt.millisecondsSinceEpoch},
        enqueuedAt: operation.createdAt,
      );
    }
  }

  Future<void> _cleanupConsumedDraft(
    WriteOperation operation,
    SttRecordingDraft? recordingDraft,
  ) async {
    if (operation.result['draftConsumed'] == true) {
      try {
        await _audioRecordingService?.deleteDraftIfExists(recordingDraft);
      } catch (_) {
        // A leftover draft is harmless compared with blocking the save UI.
      }
    }
  }

  Future<void> _drainDerivedSyncJobs() async {
    if (_disposed) return;
    final inFlight = _derivedSyncDrainInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    late final Future<void> drain;
    drain = _runDerivedSyncDrain().whenComplete(() {
      if (identical(_derivedSyncDrainInFlight, drain)) {
        _derivedSyncDrainInFlight = null;
      }
    });
    _derivedSyncDrainInFlight = drain;
    await drain;
  }

  Future<void> _drainDerivedSyncJobsSafely() async {
    try {
      await _drainDerivedSyncJobs();
    } catch (_) {
      // The persisted outbox keeps jobs retryable on the next drain.
    }
  }

  Future<void> _runDerivedSyncDrain() async {
    await PerfTrace.measure('flash_record.derived_sync_drain', () async {
      final repository = ref.read(derivedSyncJobsRepositoryProvider);
      final jobs = await repository.findPending();
      for (final job in jobs) {
        if (_disposed) return;
        try {
          await _performDerivedSyncJob(job);
          await repository.delete(job.key);
        } catch (error) {
          try {
            await repository.markFailed(job.key, error);
          } catch (_) {
            // The app may be shutting down or the database may be closed.
          }
        }
      }
    });
  }

  Future<void> _performDerivedSyncJob(DerivedSyncJob job) async {
    switch (job.type) {
      case _dailyDraftSyncJobType:
        await ensureDailyDraftAfterActivity(
          ref,
          _millisPayloadDate(job, 'updatedAt'),
        );
      case _monthlyExpenseSyncJobType:
        final date = _millisPayloadDate(job, 'date');
        await syncMonthlyExpenseReportForDate(
          settingsRepository: ref.read(appSettingsRepositoryProvider),
          expensesRepository: ref.read(expensesRepositoryProvider),
          date: date,
          generatedAt: date,
        );
      case _projectFlashArchiveSyncJobType:
        await syncProjectFlashEntryArchive(
          ref,
          projectId: _stringPayload(job, 'projectId'),
          text: _stringPayload(job, 'text'),
          isTodo: job.payload['isTodo'] == true,
          operationId: _stringPayload(job, 'operationId'),
          updatedAt: _millisPayloadDate(job, 'updatedAt'),
          notify: false,
        );
      default:
        throw StateError('Unknown derived sync job type: ${job.type}');
    }
  }

  DateTime _millisPayloadDate(DerivedSyncJob job, String key) {
    final value = job.payload[key];
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    throw StateError('Invalid derived sync date for ${job.key}: $key');
  }

  String _stringPayload(DerivedSyncJob job, String key) {
    final value = job.payload[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw StateError('Invalid derived sync payload for ${job.key}: $key');
  }

  Future<void> _commitAudioOperation(
    WriteOperation operation, {
    required SttRecordingDraft draft,
    required String content,
  }) async {
    final operations = ref.read(writeOperationsRepositoryProvider);
    var current = await operations.findById(operation.id);
    if (current == null) {
      throw StateError('录音保存请求已不存在，请重新保存。');
    }

    if (!current.isCommitted) {
      current = await ref.read(localDatabaseProvider).transaction(() async {
        final latest = await operations.findById(operation.id);
        if (latest == null) {
          throw StateError('录音保存请求已不存在，请重新保存。');
        }
        if (latest.isCommitted) return latest;

        await _audioService().createVoiceMemo(
          draft: draft,
          content: content,
          createdAt: latest.createdAt,
          deleteDraftAfterAttach: false,
        );
        return operations.markCommitted(
          operation.id,
          result: const {'draftConsumed': true},
        );
      });
    }

    if (!current.isCompleted) {
      current = await operations.markCompleted(operation.id);
      unawaited(_finishAudioOperationMirrors(current, draft));
    }
  }

  Future<void> _finishAudioOperationMirrors(
    WriteOperation operation,
    SttRecordingDraft draft,
  ) async {
    if (operation.result['draftConsumed'] != true) return;
    try {
      await _audioService().deleteDraftIfExists(draft);
    } catch (_) {
      // The voice memo has already been committed; draft cleanup can lag.
    }
  }

  Future<bool> _releaseCompletedOperationForNewText(String text) async {
    final operationId = state.saveOperationId;
    if (operationId == null || operationId.trim().isEmpty) return true;

    // A failed request keeps its original text so an identical retry reuses
    // the request. Once the input has been cleared or changed, release the
    // previous completed/pending request before accepting a new one.
    if (state.rawText.trim() == text && state.parsedInput != null) return true;
    final operation = await ref
        .read(writeOperationsRepositoryProvider)
        .findById(operationId);
    if (operation?.status == WriteOperationStatus.committed) {
      if (!_disposed) {
        state = state.copyWith(errorMessage: '上一条保存已写入，正在完成文件同步，请稍候重试。');
      }
      return false;
    }
    await _releaseOperation(operationId);
    if (!_disposed) {
      state = state.copyWith(saveOperationId: null);
    }
    return true;
  }

  Future<void> _releaseOperation(String? operationId) async {
    final id = operationId?.trim();
    if (id == null || id.isEmpty) return;
    final repository = ref.read(writeOperationsRepositoryProvider);
    final operation = await repository.findById(id);
    if (operation == null) return;
    if (operation.status == WriteOperationStatus.pending) {
      await repository.abandon(id);
    } else if (operation.isCompleted) {
      await repository.acknowledge(id);
    }
  }

  Future<void> _acknowledgeOperation(String? operationId) async {
    final id = operationId?.trim();
    if (id == null || id.isEmpty) return;
    try {
      final repository = ref.read(writeOperationsRepositoryProvider);
      final operation = await repository.findById(id);
      if (operation?.isCompleted == true) {
        await repository.acknowledge(id);
      }
    } catch (_) {
      // Acknowledgement is housekeeping; the committed data is already safe.
    }
  }

  String _parsedOperationFingerprint(
    ParsedInput parsed, {
    String? rawText,
    String? selectedProjectId,
    String? receiptImagePath,
    SttRecordingDraft? recordingDraft,
  }) {
    return _fingerprint({
      'rawText': (rawText ?? state.rawText).trim(),
      'type': parsed.type.name,
      'content': parsed.content,
      'time': parsed.time,
      'date': parsed.date?.toIso8601String(),
      'tags': parsed.tags,
      'metadata': parsed.metadata,
      'selectedProjectId': selectedProjectId ?? state.selectedProjectId,
      'receiptImagePath': receiptImagePath ?? state.expenseReceiptImagePath,
      if (recordingDraft != null)
        'recordingDraft': {
          'path': recordingDraft.path,
          'durationMs': recordingDraft.duration.inMilliseconds,
          'mimeType': recordingDraft.mimeType,
          'sampleRate': recordingDraft.sampleRate,
          'codec': recordingDraft.codec,
        },
    });
  }

  String _audioOperationFingerprint(SttRecordingDraft draft, String content) {
    return _fingerprint({
      'content': content,
      'draftPath': draft.path,
      'durationMs': draft.duration.inMilliseconds,
      'mimeType': draft.mimeType,
      'sampleRate': draft.sampleRate,
      'codec': draft.codec,
    });
  }

  String _fingerprint(Object? payload) {
    final canonical = jsonEncode(_canonicalize(payload));
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _monthKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    return '${date.year}-$month';
  }

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final entries = {
        for (final entry in value.entries) '${entry.key}': entry.value,
      };
      final keys = entries.keys.toList()..sort();
      return {for (final key in keys) key: _canonicalize(entries[key])};
    }
    if (value is Iterable) {
      return [for (final item in value) _canonicalize(item)];
    }
    if (value is DateTime) return value.toIso8601String();
    return value;
  }

  static bool _requiresTextConfirmation(String rawText, ParsedInput parsed) {
    if (parsed.type == ParsedInputType.expense) {
      final amountCount = _amountToken.allMatches(rawText).length;
      return amountCount > 1 || _riskyAmountMemoContext.hasMatch(rawText);
    }

    if (parsed.type == ParsedInputType.tracker) {
      return rawText.length > 32 || _technicalMemoContext.hasMatch(rawText);
    }

    return false;
  }

  // ---- persistence ----

  Set<DataDomain> _domainsForParsedInput(
    ParsedInput parsed, {
    bool hasAudio = false,
    bool hasReceipt = false,
    bool projectEntry = false,
  }) {
    if (projectEntry) {
      return const {DataDomain.projects, DataDomain.records};
    }

    final domains = <DataDomain>{
      switch (parsed.type) {
        ParsedInputType.memo ||
        ParsedInputType.sleep ||
        ParsedInputType.mood => DataDomain.records,
        ParsedInputType.todo => DataDomain.todos,
        ParsedInputType.focus => DataDomain.focus,
        ParsedInputType.expense => DataDomain.expenses,
        ParsedInputType.body => DataDomain.bodyLogs,
        ParsedInputType.tracker => DataDomain.trackerLogs,
      },
    };

    if (hasAudio && domains.contains(DataDomain.records)) {
      domains.add(DataDomain.media);
    }
    if (hasReceipt && parsed.type == ParsedInputType.expense) {
      // The receipt creates a moment record and a media attachment.
      domains
        ..add(DataDomain.records)
        ..add(DataDomain.media);
    }
    return domains;
  }

  Future<bool> _persist(
    ParsedInput parsed, {
    required String operationId,
    required DateTime operationStartedAt,
    required String rawText,
    SttRecordingDraft? recordingDraft,
    String? selectedProjectId,
    String? receiptImagePath,
  }) async {
    final now = operationStartedAt;
    final createdAt = parsedInputTimeToDateTime(now, parsed.time) ?? now;
    final project = selectedProjectId == null
        ? null
        : await findProjectOption(ref, selectedProjectId);

    if (project != null) {
      return _saveProjectEntry(
        parsed,
        project: project,
        now: now,
        createdAt: createdAt,
        rawText: rawText,
      );
    }

    switch (parsed.type) {
      case ParsedInputType.memo:
        return _createRecordWithOptionalAudio(
          date: now,
          type: 'memo',
          content: parsed.content,
          time: parsed.time,
          tags: parsed.tags,
          metadata: parsed.metadata,
          createdAt: createdAt,
          recordingDraft: recordingDraft,
        );

      case ParsedInputType.todo:
        await ref
            .read(todosRepositoryProvider)
            .create(
              date: now,
              title: parsed.content,
              dueTime: parsed.time,
              createdAt: createdAt,
            );
        return false;

      case ParsedInputType.focus:
        final d = (parsed.metadata['durationMinutes'] as int?) ?? 0;
        await ref
            .read(focusSessionsRepositoryProvider)
            .create(
              date: now,
              startedAt: createdAt,
              durationMinutes: d,
              note: parsed.content,
              createdAt: createdAt,
            );
        return false;

      case ParsedInputType.expense:
        final items = validExpenseLineItemsFromMetadata(parsed.metadata);
        if (items.isEmpty) {
          throw StateError('消费金额需要至少一笔有效数字。');
        }
        final fallbackCategory = parsed.tags.isNotEmpty
            ? parsed.tags.first
            : 'other';
        final note = cleanExpenseNote(parsed.content);
        final expenseIds = <int>[];
        for (final item in items) {
          final expenseId = await ref
              .read(expensesRepositoryProvider)
              .create(
                date: now,
                amount: item.amount,
                category: item.name.isNotEmpty ? item.name : fallbackCategory,
                note: items.length == 1 ? note : null,
                createdAt: createdAt,
              );
          expenseIds.add(expenseId);
        }
        final receiptPath = receiptImagePath?.trim();
        if (receiptPath != null && receiptPath.isNotEmpty) {
          try {
            await ref
                .read(photoMomentServiceProvider)
                .createExpenseReceipt(
                  sourceImagePath: receiptPath,
                  expenseName: _expenseReceiptName(items, note),
                  expenseAmount: expenseLineItemsTotal(items),
                  expenseIds: expenseIds,
                  createdAt: createdAt,
                  operationId: operationId,
                );
          } catch (_) {
            // Keep the expense rows even if the optional reimbursement image fails.
          }
        }
        return false;

      case ParsedInputType.body:
        final v = (parsed.metadata['value'] as num?)?.toDouble() ?? 0.0;
        final m = (parsed.metadata['metric'] as String?) ?? 'weight';
        await ref
            .read(bodyLogsRepositoryProvider)
            .create(
              date: now,
              metric: m,
              value: v,
              note: parsed.content,
              createdAt: createdAt,
            );
        return false;

      case ParsedInputType.sleep:
        return _createRecordWithOptionalAudio(
          date: now,
          type: 'sleep',
          content: parsed.content,
          time: parsed.time,
          tags: parsed.tags,
          metadata: parsed.metadata,
          createdAt: createdAt,
          recordingDraft: recordingDraft,
        );

      case ParsedInputType.mood:
        return _createRecordWithOptionalAudio(
          date: now,
          type: 'mood',
          content: parsed.content,
          time: parsed.time,
          tags: parsed.tags,
          metadata: parsed.metadata,
          createdAt: createdAt,
          recordingDraft: recordingDraft,
        );

      case ParsedInputType.tracker:
        await _saveTrackerLog(parsed, now, createdAt);
        return false;
    }
  }

  Future<bool> _saveProjectEntry(
    ParsedInput parsed, {
    required ProjectOption project,
    required DateTime now,
    required DateTime createdAt,
    required String rawText,
  }) async {
    final content = parsed.content.trim().isEmpty
        ? rawText.trim()
        : parsed.content.trim();
    final title = content.isEmpty ? rawText.trim() : content;
    final tags = _normalizeTags([...parsed.tags, '项目', project.name]);
    final metadata = {
      ...parsed.metadata,
      'projectId': project.id,
      'projectName': project.name,
      'projectEntryType': parsed.type == ParsedInputType.todo
          ? 'todo'
          : 'update',
      'originalParsedType': parsed.type.name,
    };

    if (parsed.type == ParsedInputType.todo) {
      await addProjectTodo(
        ref,
        projectId: project.id,
        title: title,
        updatedAt: createdAt,
        syncArchive: false,
        notify: false,
      );
      await ref
          .read(recordsRepositoryProvider)
          .create(
            date: now,
            type: 'memo',
            content: '添加待办：$title',
            time: parsed.time,
            tags: tags,
            metadata: metadata,
            createdAt: createdAt,
          );
      return false;
    }

    await addProjectUpdate(
      ref,
      projectId: project.id,
      text: title,
      updatedAt: createdAt,
      syncArchive: false,
      notify: false,
    );
    await ref
        .read(recordsRepositoryProvider)
        .create(
          date: now,
          type: 'memo',
          content: title,
          time: parsed.time,
          tags: tags,
          metadata: metadata,
          createdAt: createdAt,
        );
    return false;
  }

  String _projectEntryText(ParsedInput parsed, String rawText) {
    final content = parsed.content.trim().isEmpty
        ? rawText.trim()
        : parsed.content.trim();
    return content.isEmpty ? rawText.trim() : content;
  }

  Future<bool> _createRecordWithOptionalAudio({
    required DateTime date,
    required String type,
    required String content,
    String? time,
    List<String> tags = const [],
    Map<String, Object?> metadata = const {},
    required DateTime createdAt,
    SttRecordingDraft? recordingDraft,
  }) async {
    final recordId = await ref
        .read(recordsRepositoryProvider)
        .create(
          date: date,
          type: type,
          content: content,
          time: time,
          tags: tags,
          metadata: recordingDraft == null
              ? metadata
              : {...metadata, 'source': 'voice', 'hasAudio': true},
          createdAt: createdAt,
        );

    if (recordingDraft == null) return false;

    try {
      await ref
          .read(audioRecordingServiceProvider)
          .attachDraftToRecord(
            recordId: recordId,
            draft: recordingDraft,
            writtenAt: createdAt,
            deleteDraftAfterAttach: false,
          );
      return true;
    } catch (_) {
      await ref.read(recordsRepositoryProvider).permanentDelete(recordId);
      rethrow;
    }
  }

  Future<void> _saveTrackerLog(
    ParsedInput parsed,
    DateTime now,
    DateTime createdAt,
  ) async {
    final trackerName = parsed.content.isNotEmpty
        ? parsed.content
        : (parsed.tags.isNotEmpty ? parsed.tags.first : 'tracker');
    final durationMinutes = parsed.metadata['durationMinutes'] as int?;
    final value = durationMinutes?.toDouble() ?? 1;

    final allTrackers = await ref.read(trackersRepositoryProvider).findAll();
    final existing = allTrackers.cast<Map<String, Object?>>().firstWhere(
      (t) => t['name'] == trackerName,
      orElse: () => <String, Object?>{},
    );

    final trackerId = existing.isNotEmpty
        ? existing['id'] as int
        : await ref
              .read(trackersRepositoryProvider)
              .create(
                name: trackerName,
                unit: durationMinutes == null ? null : '分钟',
              );

    await ref
        .read(trackerLogsRepositoryProvider)
        .create(
          trackerId: trackerId,
          date: now,
          value: value,
          note: parsed.content,
          createdAt: createdAt,
        );
  }

  static String _expenseReceiptName(List<ExpenseLineItem> items, String note) {
    final itemNames = items
        .map((item) => item.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (itemNames.length == 1) return itemNames.single;
    if (itemNames.length > 1) return itemNames.take(3).join('_');
    if (note.trim().isNotEmpty) return note.trim();
    return '消费';
  }

  static List<String> _normalizeTags(Iterable<String> tags) {
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

  Future<void> _discardRecordingDraft() async {
    final draft = _recordingDraft ?? state.recordingDraft;
    if (draft == null) return;
    await _audioService().deleteDraftIfExists(draft);
    _recordingDraft = null;
    if (!_disposed) {
      state = state.copyWith(recordingDraft: null);
    }
  }

  AudioRecordingService _audioService() {
    final existing = _audioRecordingService;
    if (existing != null) return existing;
    final service = ref.read(audioRecordingServiceProvider);
    _audioRecordingService = service;
    return service;
  }
}
