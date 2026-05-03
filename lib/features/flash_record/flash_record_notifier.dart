import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/database/repository_providers.dart';
import '../../core/parser/lui_lite_parser.dart';
import 'flash_record_state.dart';

final flashRecordProvider =
    NotifierProvider<FlashRecordNotifier, FlashRecordState>(
  FlashRecordNotifier.new,
);

const _mockResults = [
  '今天跑步30分钟',
  '花了88元 买了件卫衣 #购物',
  '待办 明天交报告',
  '体重70.5公斤',
  '心情不错 今天挺充实的',
  '番茄工作25分钟',
  '喝了8杯水',
  '学习Flutter 2小时',
  '开会 产品评审',
  '聚会 跟老同学吃饭',
];

class FlashRecordNotifier extends Notifier<FlashRecordState> {
  static const _saveTimeout = Duration(seconds: 8);

  final _speech = stt.SpeechToText();
  final _random = Random();
  bool _speechReady = false;
  bool _speechPressed = false;
  bool _disposed = false;
  int _listenRequestId = 0;
  String? _preferredLocaleId;

  @override
  FlashRecordState build() {
    ref.onDispose(() {
      _disposed = true;
      unawaited(_speech.cancel());
    });
    _checkSpeechAvailability();
    return const FlashRecordState();
  }

  Future<void> _checkSpeechAvailability() async {
    try {
      final available = await _speech.initialize(
        onError: _handleSpeechError,
        onStatus: _handleSpeechStatus,
        debugLogging: false,
        finalTimeout: const Duration(milliseconds: 500),
      );
      if (!_disposed) {
        _speechReady = available;
        state = state.copyWith(
          speechAvailable: available,
          speechChecking: false,
        );
      }
    } catch (_) {
      if (!_disposed) {
        _speechReady = false;
        state = state.copyWith(
          speechAvailable: false,
          speechChecking: false,
        );
      }
    }
  }

  // ---- voice path ----

  Future<void> startListening() async {
    _speechPressed = true;
    final requestId = ++_listenRequestId;
    state = state.copyWith(
      phase: FlashPhase.listening,
      rawText: '',
      parsedInput: null,
      errorMessage: null,
      source: 'voice',
    );

    // If speech is known-unavailable, simulate immediately
    if (!state.speechAvailable) {
      _simulateListening(requestId);
      return;
    }

    // Try real speech recognition
    try {
      final localeId = await _resolvePreferredLocaleId();
      if (_disposed || requestId != _listenRequestId || !_speechPressed) return;

      await _speech.listen(
        onResult: _handleSpeechResult,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        localeId: localeId,
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: true,
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
    } catch (e) {
      if (_disposed) return;
      // Real speech failed — fall back to mock
      _simulateListening(requestId);
    }
  }

  void _simulateListening(int requestId) {
    if (_disposed || requestId != _listenRequestId || !_speechPressed) return;

    // Simulate a short listening delay, then produce a mock result
    Future.delayed(const Duration(milliseconds: 800), () {
      if (_disposed || requestId != _listenRequestId || !_speechPressed) return;
      final mockText = _mockResults[_random.nextInt(_mockResults.length)];
      state = state.copyWith(
        phase: FlashPhase.recognized,
        rawText: mockText,
        errorMessage: null,
      );
    });
  }

  Future<void> stopListening() async {
    _speechPressed = false;
    if (state.phase != FlashPhase.listening) return;

    if (_speechReady && _speech.isListening) {
      try {
        await _speech.stop();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } catch (e) {
        if (_disposed) return;
        state = state.copyWith(
          phase: FlashPhase.idle,
          errorMessage: '语音停止失败：${_friendlySpeechError(e)}',
        );
        return;
      }
    }

    // If mock simulated a result, it's already in recognized state — keep it
    final recognizedText = state.rawText.trim();
    if (recognizedText.isEmpty) {
      state = state.copyWith(
        phase: FlashPhase.idle,
        errorMessage: '没有听清，再按住说一次。',
      );
      return;
    }

    state = state.copyWith(
      phase: FlashPhase.recognized,
      rawText: recognizedText,
      errorMessage: null,
    );
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    if (_disposed || state.phase != FlashPhase.listening) return;
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;
    state = state.copyWith(
      phase: result.finalResult ? FlashPhase.recognized : FlashPhase.listening,
      rawText: text,
      errorMessage: null,
    );
  }

  void _handleSpeechStatus(String status) {
    if (_disposed || state.phase != FlashPhase.listening) return;
    if (status != 'done' && status != 'notListening') return;

    final recognizedText = state.rawText.trim();
    if (recognizedText.isNotEmpty) {
      state = state.copyWith(
        phase: FlashPhase.recognized,
        rawText: recognizedText,
        errorMessage: null,
      );
    } else if (!_speechPressed) {
      state = state.copyWith(
        phase: FlashPhase.idle,
        errorMessage: '没有听清，再按住说一次。',
      );
    }
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (_disposed || state.phase != FlashPhase.listening) return;

    // If we got partial text from real speech, keep it
    final recognizedText = state.rawText.trim();
    if (recognizedText.isNotEmpty) {
      state = state.copyWith(
        phase: FlashPhase.recognized,
        rawText: recognizedText,
        errorMessage: null,
      );
      return;
    }

    // Otherwise fall back to mock
    final mockText = _mockResults[_random.nextInt(_mockResults.length)];
    state = state.copyWith(
      phase: FlashPhase.recognized,
      rawText: mockText,
      errorMessage: null,
    );
  }

  Future<String?> _resolvePreferredLocaleId() async {
    if (_preferredLocaleId != null) return _preferredLocaleId;

    try {
      final locales = await _speech.locales();
      for (final locale in locales) {
        final normalized = locale.localeId.toLowerCase().replaceAll('-', '_');
        if (normalized == 'zh_cn') {
          _preferredLocaleId = locale.localeId;
          return _preferredLocaleId;
        }
      }
      for (final locale in locales) {
        if (locale.localeId.toLowerCase().startsWith('zh')) {
          _preferredLocaleId = locale.localeId;
          return _preferredLocaleId;
        }
      }
    } catch (_) {}
    return null;
  }

  String _friendlySpeechError(Object error) {
    if (error is SpeechRecognitionError) {
      if (error.errorMsg == 'error_permission') {
        return '麦克风权限未开启，请允许 Dayline 使用麦克风。';
      }
      if (error.errorMsg == 'error_no_match') {
        return '没有听清，再按住说一次。';
      }
      return error.errorMsg;
    }
    final message = error.toString();
    if (message.contains('MissingPluginException')) {
      return '当前运行环境还没有加载语音识别插件。';
    }
    return message;
  }

  // ---- confirm / save flow ----

  void confirmParsed() {
    final parsed = LuiLiteParser.parse(state.rawText);
    state = state.copyWith(phase: FlashPhase.confirming, parsedInput: parsed);
  }

  void cancelConfirm() {
    state = const FlashRecordState();
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
    state = const FlashRecordState();
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
