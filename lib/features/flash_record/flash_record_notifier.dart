import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';
import '../../core/parser/lui_lite_parser.dart';
import '../../core/stt/stt_engine.dart';
import '../../core/stt/stt_providers.dart';
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
  bool _disposed = false;
  int _listenRequestId = 0;

  @override
  FlashRecordState build() {
    _sttEngine = ref.watch(sttEngineProvider);
    ref.onDispose(() {
      _disposed = true;
      unawaited(_sttSub?.cancel());
      unawaited(_sttSession?.cancel());
    });
    scheduleMicrotask(() {
      if (!_disposed) {
        unawaited(_initializeStt());
      }
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

  Future<void> startListening() async {
    final requestId = ++_listenRequestId;
    state = state.copyWith(
      phase: FlashPhase.listening,
      rawText: '',
      partialText: '',
      audioLevel: 0,
      parsedInput: null,
      errorMessage: null,
      source: 'voice',
      transcriptFinal: false,
    );

    if (state.sttStatus != SttAvailabilityStatus.ready) {
      state = state.copyWith(
        phase: FlashPhase.idle,
        errorMessage: state.sttStatus == SttAvailabilityStatus.loading
            ? '离线大脑还在唤醒，稍等一下'
            : kDebugMode
            ? state.sttStatusMessage
            : '离线语音暂不可用，请使用文字记录',
      );
      return;
    }

    try {
      await _sttSub?.cancel();
      await _sttSession?.cancel();

      final session = await _sttEngine.startListening();
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

    final session = _sttSession;
    if (session == null) {
      state = state.copyWith(
        phase: FlashPhase.idle,
        errorMessage: '离线语音还没有开始，请再试一次。',
      );
      return;
    }

    try {
      final transcript = await session.stop();
      if (_disposed) return;
      _completeTranscript(transcript);
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
      _completeTranscript(transcript);
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

  void _completeTranscript(SttTranscript transcript) {
    final recognizedText = transcript.text.trim();
    if (recognizedText.isNotEmpty) {
      state = state.copyWith(
        phase: FlashPhase.recognized,
        rawText: recognizedText,
        partialText: recognizedText,
        audioLevel: 0,
        sttMetadata: transcript.metadata,
        transcriptFinal: true,
        errorMessage: null,
      );
    } else {
      state = state.copyWith(
        phase: FlashPhase.idle,
        rawText: '',
        partialText: '',
        audioLevel: 0,
        errorMessage: '没有听清，再按住说一次。',
      );
    }
  }

  String _friendlySttError(Object error) {
    final message = error.toString();
    if (message.contains('麦克风权限')) {
      return '麦克风权限未开启，请允许 Dayline 使用麦克风。';
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
    state = state.copyWith(
      parsedInput: parsed.copyWith(type: newType, tags: []),
    );
  }

  void cancelConfirm() {
    state = _idleStateKeepingStt();
  }

  Future<void> save() async {
    final parsed = state.parsedInput;
    if (parsed == null) return;

    state = state.copyWith(phase: FlashPhase.saving);

    try {
      await _persist(parsed).timeout(_saveTimeout);
      ref.read(dataVersionProvider.notifier).increment();
      state = state.copyWith(phase: FlashPhase.saved);
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

  void resetAfterSaved() {
    state = _idleStateKeepingStt();
  }

  FlashRecordState _idleStateKeepingStt() {
    return FlashRecordState(
      sttStatus: state.sttStatus,
      sttStatusMessage: state.sttStatusMessage,
    );
  }

  // ---- text path ----

  Future<void> saveAsText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final parsed = LuiLiteParser.parse(trimmed);
    state = state.copyWith(
      phase: FlashPhase.saving,
      rawText: trimmed,
      source: 'text',
      parsedInput: parsed,
    );

    try {
      await _persist(parsed).timeout(_saveTimeout);
      ref.read(dataVersionProvider.notifier).increment();
      state = state.copyWith(phase: FlashPhase.saved);
    } on TimeoutException {
      state = state.copyWith(
        phase: FlashPhase.idle,
        errorMessage: '保存超时，请再试一次。',
      );
    } catch (e) {
      state = state.copyWith(
        phase: FlashPhase.idle,
        errorMessage: e.toString(),
      );
    }
  }

  // ---- persistence ----

  Future<void> _persist(ParsedInput parsed) async {
    final now = DateTime.now();

    switch (parsed.type) {
      case ParsedInputType.memo:
        await ref.read(recordsRepositoryProvider).create(
              date: now,
              type: 'memo',
              content: parsed.content,
              time: parsed.time,
              tags: parsed.tags,
              metadata: parsed.metadata,
            );

      case ParsedInputType.todo:
        await ref.read(todosRepositoryProvider).create(
              date: now,
              title: parsed.content,
              dueTime: parsed.time,
            );

      case ParsedInputType.focus:
        final d = (parsed.metadata['durationMinutes'] as int?) ?? 25;
        await ref.read(focusSessionsRepositoryProvider).create(
              date: now,
              startedAt: now,
              durationMinutes: d,
              note: parsed.content,
            );

      case ParsedInputType.expense:
        final a = (parsed.metadata['amount'] as num?)?.toDouble() ?? 0.0;
        final c = parsed.tags.isNotEmpty ? parsed.tags.first : 'other';
        await ref.read(expensesRepositoryProvider).create(
              date: now,
              amount: a,
              category: c,
              note: parsed.content,
            );

      case ParsedInputType.body:
        final v = (parsed.metadata['value'] as num?)?.toDouble() ?? 0.0;
        final m = (parsed.metadata['metric'] as String?) ?? 'weight';
        await ref.read(bodyLogsRepositoryProvider).create(
              date: now,
              metric: m,
              value: v,
              note: parsed.content,
            );

      case ParsedInputType.sleep:
        await ref.read(recordsRepositoryProvider).create(
              date: now,
              type: 'sleep',
              content: parsed.content,
              time: parsed.time,
              tags: parsed.tags,
              metadata: parsed.metadata,
            );

      case ParsedInputType.mood:
        await ref.read(recordsRepositoryProvider).create(
              date: now,
              type: 'mood',
              content: parsed.content,
              time: parsed.time,
              tags: parsed.tags,
              metadata: parsed.metadata,
            );

      case ParsedInputType.tracker:
        await _saveTrackerLog(parsed, now);
    }
  }

  Future<void> _saveTrackerLog(ParsedInput parsed, DateTime now) async {
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
        : await ref.read(trackersRepositoryProvider).create(
              name: trackerName,
              unit: durationMinutes == null ? null : '分钟',
            );

    await ref.read(trackerLogsRepositoryProvider).create(
          trackerId: trackerId,
          date: now,
          value: value,
          note: parsed.content,
        );
  }
}
