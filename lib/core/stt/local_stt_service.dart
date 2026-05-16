import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'stt_asset_manager.dart';
import 'stt_engine.dart';
import 'stt_text_post_processor.dart';

const _sttSampleRate = 16000;
const _workerRecycleAfterTranscriptions = 2;

class SttPermissionException implements Exception {
  const SttPermissionException();

  @override
  String toString() => '麦克风权限未开启，请允许 Liflow 使用麦克风。';
}

class LocalSttService implements SttEngine {
  LocalSttService({SttAssetManager? assetManager, AudioRecorder? recorder})
    : _assetManager = assetManager ?? SttAssetManager(),
      _recorder = recorder ?? AudioRecorder();

  static final LocalSttService instance = LocalSttService(
    assetManager: SttAssetManager(
      archiveSha256: senseVoiceModelArchiveSha256,
      bundledArchiveSha256: senseVoiceModelArchiveSha256,
    ),
  );

  final SttAssetManager _assetManager;
  final AudioRecorder _recorder;

  Future<SttAvailability>? _initializing;
  SttAvailability? _availability;
  SttAssetPaths? _paths;
  Future<void>? _workerStarting;
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  ReceivePort? _workerReceivePort;
  StreamSubscription<dynamic>? _workerSub;
  _LocalSttListenSession? _activeSession;
  final _pendingTranscriptions =
      <int, Completer<_SenseVoiceTranscriptionResult>>{};
  var _nextTranscriptionId = 0;
  var _workerTranscriptionCount = 0;

  @override
  Future<SttAvailability> initialize() {
    final availability = _availability;
    if (availability?.isReady == true) {
      return Future.value(availability);
    }
    _initializing ??= _initialize();
    return _initializing!;
  }

  Future<SttAvailability> _initialize() async {
    if (!Platform.isAndroid) {
      return const SttAvailability.unavailable('离线语音第一版仅支持 Android 真机。');
    }

    try {
      final paths = await _assetManager.ensureReady();
      _paths = paths;
      unawaited(
        _startWorker(paths).catchError((Object error) {
          if (kDebugMode) {
            debugPrint('SenseVoice worker warmup failed: $error');
          }
        }),
      );
      const availability = SttAvailability.ready();
      _availability = availability;
      return availability;
    } catch (error) {
      _initializing = null;
      if (kDebugMode) {
        return SttAvailability.error('离线语音暂不可用：$error');
      }
      return const SttAvailability.unavailable('离线语音暂不可用，请使用文字记录');
    }
  }

  Future<void> _startWorker(SttAssetPaths paths) {
    if (_workerSendPort != null) return Future.value();
    _workerStarting ??= _spawnWorker(paths).catchError((Object error) {
      _workerStarting = null;
      throw error;
    });
    return _workerStarting!;
  }

  Future<void> _spawnWorker(SttAssetPaths paths) async {
    final receivePort = ReceivePort();
    final ready = Completer<SendPort>();
    _workerReceivePort = receivePort;
    _workerSub = receivePort.listen((message) {
      if (message is! Map) return;
      final type = message['type'];

      if (type == 'ready') {
        final sendPort = message['sendPort'];
        if (sendPort is SendPort && !ready.isCompleted) {
          _workerSendPort = sendPort;
          ready.complete(sendPort);
        }
        return;
      }

      if (type == 'initError') {
        if (!ready.isCompleted) {
          ready.completeError(StateError(message['message'].toString()));
        }
        return;
      }

      final requestId = message['requestId'];
      if (requestId is! int) return;
      final pending = _pendingTranscriptions.remove(requestId);
      if (pending == null || pending.isCompleted) return;

      if (type == 'result') {
        pending.complete(_SenseVoiceTranscriptionResult.fromMessage(message));
        _noteWorkerTranscriptionFinished();
      } else if (type == 'error') {
        pending.completeError(StateError(message['message'].toString()));
        _noteWorkerTranscriptionFinished();
      }
    });

    _workerIsolate = await Isolate.spawn<Map<String, Object?>>(
      _senseVoiceWorkerMain,
      {
        'replyTo': receivePort.sendPort,
        'modelPath': paths.senseVoiceModel,
        'tokensPath': paths.tokens,
        'modelVersion': paths.modelVersion,
      },
      debugName: 'LiflowSenseVoiceWorker',
      errorsAreFatal: true,
    );

    await ready.future.timeout(const Duration(seconds: 60));
  }

  @override
  Future<SttListenSession> startListening({bool transcribe = true}) async {
    SttAssetPaths? paths;
    if (transcribe) {
      final availability = await initialize();
      if (!availability.isReady) {
        throw StateError(availability.message);
      }

      paths = _paths;
      if (paths == null) {
        throw StateError('离线语音引擎还没有准备好。');
      }
    }

    if (!await _recorder.hasPermission()) {
      throw const SttPermissionException();
    }

    if (!await _recorder.isEncoderSupported(AudioEncoder.wav)) {
      throw StateError('当前设备不支持 WAV 录音，无法使用 SenseVoice 离线识别。');
    }

    await _activeSession?.cancel();

    final tempDir = await getTemporaryDirectory();
    final wavFile = File(
      p.join(
        tempDir.path,
        'liflow-stt-${DateTime.now().microsecondsSinceEpoch}.wav',
      ),
    );

    final session = _LocalSttListenSession(
      recorder: _recorder,
      wavFile: wavFile,
      paths: paths,
      transcribe: _transcribeFile,
      onFinished: (session) {
        if (identical(_activeSession, session)) {
          _activeSession = null;
        }
      },
    );
    _activeSession = session;
    await session.start();
    return session;
  }

  @override
  Future<void> dispose() async {
    await _activeSession?.cancel();
    await _disposeWorker(completePending: true);
    await _recorder.dispose();
  }

  void _noteWorkerTranscriptionFinished() {
    _workerTranscriptionCount += 1;
    if (_workerTranscriptionCount < _workerRecycleAfterTranscriptions) {
      return;
    }
    if (_pendingTranscriptions.isNotEmpty) return;

    final paths = _paths;
    if (paths == null) return;

    unawaited(
      Future<void>.delayed(Duration.zero, () async {
        await _disposeWorker(completePending: false);
        await _startWorker(paths);
      }).catchError((Object error) {
        if (kDebugMode) {
          debugPrint('SenseVoice worker recycle failed: $error');
        }
      }),
    );
  }

  Future<void> _disposeWorker({required bool completePending}) async {
    final sendPort = _workerSendPort;
    final isolate = _workerIsolate;
    final receivePort = _workerReceivePort;
    final sub = _workerSub;

    _workerStarting = null;
    _workerSendPort = null;
    _workerIsolate = null;
    _workerReceivePort = null;
    _workerSub = null;
    _workerTranscriptionCount = 0;

    sendPort?.send({'type': 'dispose'});
    await Future<void>.delayed(const Duration(milliseconds: 80));
    isolate?.kill(priority: Isolate.immediate);

    if (completePending) {
      for (final pending in _pendingTranscriptions.values) {
        if (!pending.isCompleted) {
          pending.completeError(StateError('Offline speech engine is closed.'));
        }
      }
      _pendingTranscriptions.clear();
    }

    await sub?.cancel();
    receivePort?.close();
  }

  Future<_SenseVoiceTranscriptionResult> _transcribeFile(String wavPath) {
    final paths = _paths;
    if (paths == null) {
      throw StateError('离线语音引擎还没有准备好。');
    }

    return _startWorker(paths).then((_) {
      final workerSendPort = _workerSendPort;
      if (workerSendPort == null) {
        throw StateError('离线语音引擎还没有准备好。');
      }

      final requestId = ++_nextTranscriptionId;
      final completer = Completer<_SenseVoiceTranscriptionResult>();
      _pendingTranscriptions[requestId] = completer;
      workerSendPort.send({
        'type': 'transcribe',
        'requestId': requestId,
        'wavPath': wavPath,
      });
      return completer.future;
    });
  }
}

class _LocalSttListenSession implements SttListenSession {
  _LocalSttListenSession({
    required AudioRecorder recorder,
    required File wavFile,
    required SttAssetPaths? paths,
    required Future<_SenseVoiceTranscriptionResult> Function(String wavPath)
    transcribe,
    required void Function(_LocalSttListenSession session) onFinished,
  }) : _recorder = recorder,
       _wavFile = wavFile,
       _transcribe = transcribe,
       _metadata = SttMetadata(modelVersion: paths?.modelVersion),
       _onFinished = onFinished;

  final AudioRecorder _recorder;
  final File _wavFile;
  final Future<_SenseVoiceTranscriptionResult> Function(String wavPath)
  _transcribe;
  final SttMetadata _metadata;
  final void Function(_LocalSttListenSession session) _onFinished;
  final _controller = StreamController<SttTranscript>.broadcast();
  final _finalCompleter = Completer<SttTranscript>();
  final _watch = Stopwatch()..start();

  StreamSubscription<Amplitude>? _amplitudeSub;
  var _stopping = false;
  var _finished = false;

  @override
  Stream<SttTranscript> get transcripts => _controller.stream;

  Future<void> start() async {
    await _wavFile.parent.create(recursive: true);
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: _sttSampleRate,
        numChannels: 1,
        autoGain: true,
        echoCancel: false,
        noiseSuppress: true,
      ),
      path: _wavFile.path,
    );

    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 180))
        .listen(_emitAmplitude);
  }

  void _emitAmplitude(Amplitude amplitude) {
    if (_finished || _controller.isClosed) return;
    _controller.add(
      SttTranscript(
        text: '',
        isFinal: false,
        audioLevel: _normalizeDbfs(amplitude.current),
        metadata: _metadata,
      ),
    );
  }

  double _normalizeDbfs(double dbfs) {
    if (dbfs.isNaN || dbfs.isInfinite) return 0;
    return ((dbfs + 60) / 60).clamp(0.0, 1.0).toDouble();
  }

  @override
  Future<SttTranscript> stop({bool transcribe = true}) async {
    if (_finished) return _finalCompleter.future;
    if (_stopping) return _finalCompleter.future;
    _stopping = true;

    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    String? recordedPath;
    try {
      if (await _recorder.isRecording()) {
        recordedPath = await _recorder.stop();
      }
    } catch (_) {}

    final wavPath = recordedPath ?? _wavFile.path;
    final draft = SttRecordingDraft(
      path: wavPath,
      duration: _watch.elapsed,
      sampleRate: _sttSampleRate,
    );
    if (!transcribe) {
      final transcript = SttTranscript(
        text: '',
        isFinal: true,
        metadata: SttMetadata(
          modelVersion: _metadata.modelVersion,
          elapsed: _watch.elapsed,
        ),
        recordingDraft: draft,
      );
      _finish(transcript);
      return transcript;
    }

    try {
      final result = await _transcribe(
        wavPath,
      ).timeout(const Duration(seconds: 90));
      final transcript = result.toTranscript(recordingDraft: draft);
      _finish(transcript);
      return transcript;
    } catch (_) {
      final fallback = SttTranscript(
        text: '',
        isFinal: true,
        metadata: SttMetadata(
          modelVersion: _metadata.modelVersion,
          elapsed: _watch.elapsed,
        ),
        recordingDraft: draft,
      );
      _finish(fallback);
      return fallback;
    }
  }

  @override
  Future<void> cancel() async {
    if (_finished) return;
    _stopping = true;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.cancel();
      }
    } catch (_) {}
    await _deleteWav();
    _finish(const SttTranscript(text: '', isFinal: true));
  }

  Future<void> _deleteWav() async {
    try {
      if (await _wavFile.exists()) {
        await _wavFile.delete();
      }
    } catch (_) {}
  }

  void _finish(SttTranscript transcript) {
    if (_finished) return;
    _finished = true;
    _watch.stop();
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
    if (!_finalCompleter.isCompleted) {
      _finalCompleter.complete(transcript);
    }
    _onFinished(this);
  }
}

@immutable
class _SenseVoiceTranscriptionResult {
  const _SenseVoiceTranscriptionResult({
    required this.text,
    required this.language,
    required this.emotion,
    required this.events,
    required this.durationMs,
    required this.modelVersion,
  });

  final String text;
  final String language;
  final String emotion;
  final String events;
  final int durationMs;
  final String modelVersion;

  factory _SenseVoiceTranscriptionResult.fromMessage(
    Map<dynamic, dynamic> message,
  ) {
    return _SenseVoiceTranscriptionResult(
      text: message['text'] as String? ?? '',
      language: message['language'] as String? ?? '',
      emotion: message['emotion'] as String? ?? '',
      events: message['events'] as String? ?? '',
      durationMs: message['durationMs'] as int? ?? 0,
      modelVersion: message['modelVersion'] as String? ?? '',
    );
  }

  SttTranscript toTranscript({SttRecordingDraft? recordingDraft}) {
    return SttTranscript(
      text: postProcessTranscript(text),
      isFinal: true,
      metadata: SttMetadata(
        modelVersion: modelVersion,
        language: _emptyToNull(language),
        emotion: _emptyToNull(emotion),
        events: _emptyToNull(events),
        elapsed: Duration(milliseconds: durationMs),
      ),
      recordingDraft: recordingDraft,
    );
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

void _senseVoiceWorkerMain(Map<String, Object?> init) {
  final replyTo = init['replyTo']! as SendPort;
  final commandPort = ReceivePort();
  final modelPath = init['modelPath']! as String;
  final tokensPath = init['tokensPath']! as String;
  final modelVersion = init['modelVersion']! as String;

  late final sherpa.OfflineRecognizer recognizer;

  try {
    sherpa.initBindings();
    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          senseVoice: sherpa.OfflineSenseVoiceModelConfig(
            model: modelPath,
            language: 'auto',
            useInverseTextNormalization: true,
          ),
          tokens: tokensPath,
          numThreads: 4,
          provider: 'xnnpack',
          modelType: 'sense_voice',
          debug: false,
        ),
      ),
    );
  } catch (error) {
    replyTo.send({'type': 'initError', 'message': error.toString()});
    commandPort.close();
    return;
  }

  replyTo.send({'type': 'ready', 'sendPort': commandPort.sendPort});

  commandPort.listen((message) {
    if (message is! Map) return;
    final type = message['type'];

    if (type == 'dispose') {
      recognizer.free();
      commandPort.close();
      Isolate.exit();
    }

    if (type != 'transcribe') return;

    final requestId = message['requestId'];
    final wavPath = message['wavPath'];
    if (requestId is! int || wavPath is! String) return;

    try {
      final result = _transcribeSenseVoiceWithRecognizer(
        recognizer: recognizer,
        wavPath: wavPath,
        modelVersion: modelVersion,
      );
      replyTo.send({
        'type': 'result',
        'requestId': requestId,
        'text': result.text,
        'language': result.language,
        'emotion': result.emotion,
        'events': result.events,
        'durationMs': result.durationMs,
        'modelVersion': result.modelVersion,
      });
    } catch (error) {
      replyTo.send({
        'type': 'error',
        'requestId': requestId,
        'message': error.toString(),
      });
    }
  });
}

_SenseVoiceTranscriptionResult _transcribeSenseVoiceWithRecognizer({
  required sherpa.OfflineRecognizer recognizer,
  required String wavPath,
  required String modelVersion,
}) {
  sherpa.initBindings();

  final watch = Stopwatch()..start();
  sherpa.OfflineStream? stream;
  try {
    final wave = sherpa.readWave(wavPath);
    if (wave.samples.isEmpty) {
      throw StateError('无法读取音频文件');
    }

    stream = recognizer.createStream();
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    recognizer.decode(stream);
    final result = recognizer.getResult(stream);
    watch.stop();

    return _SenseVoiceTranscriptionResult(
      text: result.text,
      language: result.lang,
      emotion: result.emotion,
      events: result.event,
      durationMs: watch.elapsedMilliseconds,
      modelVersion: modelVersion,
    );
  } finally {
    stream?.free();
  }
}
