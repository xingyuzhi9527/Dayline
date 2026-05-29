import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import '../../core/media/audio_recording_service.dart';
import '../../core/media/photo_moment_service.dart';
import '../../core/parser/expense_line_item.dart';
import '../../core/parser/expense_note_cleaner.dart';
import '../../core/parser/lui_lite_parser.dart';
import '../../core/parser/parsed_input_time.dart';
import '../../core/stt/stt_engine.dart';
import '../../core/stt/stt_providers.dart';
import '../dashboard/daily_note_draft.dart';
import '../projects/project_store.dart';
import 'flash_record_state.dart';

final flashRecordProvider =
    NotifierProvider<FlashRecordNotifier, FlashRecordState>(
      FlashRecordNotifier.new,
    );

class FlashRecordNotifier extends Notifier<FlashRecordState> {
  static const _saveTimeout = Duration(seconds: 8);

  late final SttEngine _sttEngine;
  SttListenSession? _sttSession;
  StreamSubscription<SttTranscript>? _sttSub;
  SttRecordingDraft? _recordingDraft;
  AudioRecordingService? _audioRecordingService;
  bool _disposed = false;
  int _listenRequestId = 0;

  @override
  FlashRecordState build() {
    _sttEngine = ref.watch(sttEngineProvider);
    ref.onDispose(() {
      _disposed = true;
      unawaited(_sttSub?.cancel());
      unawaited(_sttSession?.cancel());
      unawaited(_audioRecordingService?.deleteDraftIfExists(_recordingDraft));
    });
    unawaited(
      Future<void>.microtask(() async {
        if (!_disposed) {
          await _initializeStt();
        }
      }),
    );
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
    unawaited(_discardRecordingDraft());
    state = _idleStateKeepingStt();
  }

  Future<void> save() async {
    final parsed = state.parsedInput;
    if (parsed == null) return;

    state = state.copyWith(phase: FlashPhase.saving);

    try {
      final draft = state.recordingDraft;
      if (draft != null) {
        _audioService();
      }
      final draftConsumed = await _persist(
        parsed,
        recordingDraft: draft,
        selectedProjectId: state.selectedProjectId,
        receiptImagePath: state.expenseReceiptImagePath,
      ).timeout(_saveTimeout);
      await ensureDailyDraftAfterActivity(ref, DateTime.now());
      if (!draftConsumed) {
        await _audioRecordingService?.deleteDraftIfExists(draft);
      }
      ref.read(dataVersionProvider.notifier).increment();
      _recordingDraft = null;
      state = state.copyWith(
        phase: FlashPhase.saved,
        recordingDraft: null,
        selectedProjectId: null,
        expenseReceiptImagePath: null,
      );
    } on TimeoutException {
      state = state.copyWith(
        phase: FlashPhase.confirming,
        errorMessage: '保存超时，请再试一次。',
      );
    } catch (e) {
      state = state.copyWith(
        phase: FlashPhase.confirming,
        errorMessage: e.toString(),
      );
    }
  }

  void resetAfterSaved() {
    state = _idleStateKeepingStt();
  }

  FlashRecordState _idleStateKeepingStt() {
    return FlashRecordState(
      sttStatus: state.sttStatus,
      sttStatusMessage: state.sttStatusMessage,
      recordingMode: state.recordingMode,
    );
  }

  Future<void> saveAudioOnly() async {
    final draft = state.recordingDraft;
    if (draft == null) {
      state = state.copyWith(errorMessage: '没有可保存的录音。');
      return;
    }

    state = state.copyWith(phase: FlashPhase.saving);

    try {
      await _audioService()
          .createVoiceMemo(
            draft: draft,
            content: state.rawText,
            createdAt: DateTime.now(),
          )
          .timeout(_saveTimeout);
      ref.read(dataVersionProvider.notifier).increment();
      _recordingDraft = null;
      state = state.copyWith(phase: FlashPhase.saved, recordingDraft: null);
    } on TimeoutException {
      state = state.copyWith(
        phase: FlashPhase.recognized,
        errorMessage: '保存超时，请再试一次。',
      );
    } catch (e) {
      state = state.copyWith(
        phase: FlashPhase.recognized,
        errorMessage: e.toString(),
      );
    }
  }

  // ---- text path ----

  Future<void> saveAsText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final parsed = LuiLiteParser.parse(trimmed);
    state = state.copyWith(
      phase: FlashPhase.idle,
      rawText: trimmed,
      source: 'text',
      parsedInput: parsed,
      textSaving: true,
      errorMessage: null,
    );

    try {
      await _persist(parsed).timeout(_saveTimeout);
      await ensureDailyDraftAfterActivity(ref, DateTime.now());
      ref.read(dataVersionProvider.notifier).incrementSoon();
      state = state.copyWith(
        phase: FlashPhase.idle,
        rawText: '',
        parsedInput: null,
        textSaving: false,
        savedSequence: state.savedSequence + 1,
      );
    } on TimeoutException {
      state = state.copyWith(
        phase: FlashPhase.idle,
        textSaving: false,
        errorMessage: '保存超时，请再试一次。',
      );
    } catch (e) {
      state = state.copyWith(
        phase: FlashPhase.idle,
        textSaving: false,
        errorMessage: e.toString(),
      );
    }
  }

  // ---- persistence ----

  Future<bool> _persist(
    ParsedInput parsed, {
    SttRecordingDraft? recordingDraft,
    String? selectedProjectId,
    String? receiptImagePath,
  }) async {
    final now = DateTime.now();
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
  }) async {
    final content = parsed.content.trim().isEmpty
        ? state.rawText.trim()
        : parsed.content.trim();
    final title = content.isEmpty ? state.rawText.trim() : content;
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
