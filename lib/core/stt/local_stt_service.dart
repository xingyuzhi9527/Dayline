import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'stt_asset_manager.dart';
import 'stt_audio.dart';
import 'stt_engine.dart';
import 'stt_text_post_processor.dart';

const _sttSampleRate = 16000;

class SttPermissionException implements Exception {
  const SttPermissionException();

  @override
  String toString() => '麦克风权限未开启，请允许 Dayline 使用麦克风。';
}

class LocalSttService implements SttEngine {
  LocalSttService({
    SttAssetManager assetManager = const SttAssetManager(),
    AudioRecorder? recorder,
  })  : _assetManager = assetManager,
        _recorder = recorder ?? AudioRecorder();

  static final LocalSttService instance = LocalSttService();

  final SttAssetManager _assetManager;
  final AudioRecorder _recorder;

  Future<SttAvailability>? _initializing;
  SttAvailability? _availability;
  SttAssetPaths? _paths;
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  ReceivePort? _workerReceivePort;
  StreamSubscription<dynamic>? _workerSub;
  _LocalSttListenSession? _activeSession;
  var _nextSessionId = 0;

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
      await _startWorker(paths);
      _paths = paths;

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

  Future<void> _startWorker(SttAssetPaths paths) async {
    if (_workerSendPort != null) return;

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

      final sessionId = message['sessionId'];
      final activeSession = _activeSession;
      if (sessionId is int && activeSession?.sessionId == sessionId) {
        activeSession!.handleWorkerMessage(message);
      }
    });

    _workerIsolate = await Isolate.spawn<Map<String, Object?>>(
      _sttWorkerMain,
      {
        'replyTo': receivePort.sendPort,
        'encoder': paths.encoder,
        'decoder': paths.decoder,
        'joiner': paths.joiner,
        'tokens': paths.tokens,
        'vadModel': paths.vadModel,
        'hotwords': paths.hotwords,
        'modelVersion': paths.root.path.split(Platform.pathSeparator).last,
      },
      debugName: 'DaylineLocalSttWorker',
      errorsAreFatal: true,
    );

    await ready.future.timeout(const Duration(seconds: 45));
  }

  @override
  Future<SttListenSession> startListening() async {
    final availability = await initialize();
    if (!availability.isReady) {
      throw StateError(availability.message);
    }

    final workerSendPort = _workerSendPort;
    final paths = _paths;
    if (workerSendPort == null || paths == null) {
      throw StateError('离线语音引擎还没有准备好。');
    }

    if (!await _recorder.hasPermission()) {
      throw const SttPermissionException();
    }

    await _activeSession?.cancel();

    final session = _LocalSttListenSession(
      sessionId: ++_nextSessionId,
      recorder: _recorder,
      workerSendPort: workerSendPort,
      modelVersion: paths.root.path.split(Platform.pathSeparator).last,
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
    _workerSendPort?.send({'type': 'dispose'});
    _workerIsolate?.kill(priority: Isolate.immediate);
    await _workerSub?.cancel();
    _workerReceivePort?.close();
    _workerSendPort = null;
    _workerIsolate = null;
    await _recorder.dispose();
  }
}

class _LocalSttListenSession implements SttListenSession {
  _LocalSttListenSession({
    required this.sessionId,
    required AudioRecorder recorder,
    required SendPort workerSendPort,
    required String modelVersion,
    required void Function(_LocalSttListenSession session) onFinished,
  })  : _recorder = recorder,
        _workerSendPort = workerSendPort,
        _metadata = SttMetadata(modelVersion: modelVersion),
        _onFinished = onFinished;

  final int sessionId;
  final AudioRecorder _recorder;
  final SendPort _workerSendPort;
  final SttMetadata _metadata;
  final void Function(_LocalSttListenSession session) _onFinished;
  final _controller = StreamController<SttTranscript>.broadcast();
  final _finalCompleter = Completer<SttTranscript>();
  final _watch = Stopwatch()..start();

  StreamSubscription<Uint8List>? _audioSub;
  var _stopping = false;
  var _finished = false;
  var _latestText = '';

  @override
  Stream<SttTranscript> get transcripts => _controller.stream;

  Future<void> start() async {
    _workerSendPort.send({'type': 'start', 'sessionId': sessionId});

    try {
      final audio = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sttSampleRate,
          numChannels: 1,
          autoGain: true,
          echoCancel: false,
          noiseSuppress: true,
          streamBufferSize: 4096,
        ),
      );

      _audioSub = audio.listen(
        _sendAudio,
        onError: _handleAudioError,
        cancelOnError: true,
      );
    } catch (_) {
      _workerSendPort.send({'type': 'cancel', 'sessionId': sessionId});
      rethrow;
    }
  }

  void _sendAudio(Uint8List data) {
    if (_stopping || _finished) return;
    _workerSendPort.send({
      'type': 'audio',
      'sessionId': sessionId,
      'data': TransferableTypedData.fromList([data]),
    });
  }

  void handleWorkerMessage(Map<dynamic, dynamic> message) {
    final type = message['type'];
    if (type == 'transcript') {
      final transcript = _transcriptFromWorker(message);
      if (transcript.text.isNotEmpty) {
        _latestText = transcript.text;
      }
      if (!_controller.isClosed) {
        _controller.add(transcript);
      }
      if (transcript.isFinal) {
        unawaited(_stopRecorder(cancel: false));
        _finish(transcript);
      }
      return;
    }

    if (type == 'error') {
      final transcript = SttTranscript(
        text: postProcessTranscript(_latestText),
        isFinal: true,
        metadata: SttMetadata(
          modelVersion: _metadata.modelVersion,
          elapsed: _watch.elapsed,
        ),
      );
      unawaited(_stopRecorder(cancel: true));
      _finish(transcript);
    }
  }

  SttTranscript _transcriptFromWorker(Map<dynamic, dynamic> message) {
    return SttTranscript(
      text: (message['text'] as String? ?? '').trim(),
      isFinal: message['isFinal'] == true,
      audioLevel: (message['audioLevel'] as num?)?.toDouble() ?? 0,
      metadata: SttMetadata(
        modelVersion:
            message['modelVersion'] as String? ?? _metadata.modelVersion,
        elapsed: message['elapsedMs'] is int
            ? Duration(milliseconds: message['elapsedMs'] as int)
            : null,
      ),
    );
  }

  @override
  Future<SttTranscript> stop() async {
    if (_finished) return _finalCompleter.future;
    if (_stopping) return _finalCompleter.future;
    _stopping = true;

    await _stopRecorder(cancel: false);
    _workerSendPort.send({'type': 'stop', 'sessionId': sessionId});
    return _finalCompleter.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        final fallback = SttTranscript(
          text: postProcessTranscript(_latestText),
          isFinal: true,
          metadata: SttMetadata(
            modelVersion: _metadata.modelVersion,
            elapsed: _watch.elapsed,
          ),
        );
        _finish(fallback);
        return fallback;
      },
    );
  }

  @override
  Future<void> cancel() async {
    if (_finished) return;
    _stopping = true;
    await _stopRecorder(cancel: true);
    _workerSendPort.send({'type': 'cancel', 'sessionId': sessionId});
    _finish(const SttTranscript(text: '', isFinal: true));
  }

  Future<void> _stopRecorder({required bool cancel}) async {
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      if (await _recorder.isRecording()) {
        if (cancel) {
          await _recorder.cancel();
        } else {
          await _recorder.stop();
        }
      }
    } catch (_) {}
  }

  void _handleAudioError(Object error, StackTrace stackTrace) {
    _workerSendPort.send({'type': 'cancel', 'sessionId': sessionId});
    _finish(const SttTranscript(text: '', isFinal: true));
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

void _sttWorkerMain(Map<String, Object?> init) {
  final replyTo = init['replyTo']! as SendPort;
  final commandPort = ReceivePort();

  late final sherpa.OnlineRecognizer recognizer;
  late final sherpa.VadModelConfig vadConfig;
  final modelVersion = init['modelVersion']! as String;

  try {
    sherpa.initBindings();
    recognizer = sherpa.OnlineRecognizer(
      sherpa.OnlineRecognizerConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: init['encoder']! as String,
            decoder: init['decoder']! as String,
            joiner: init['joiner']! as String,
          ),
          tokens: init['tokens']! as String,
          numThreads: 2,
          provider: 'cpu',
          debug: false,
          modelType: '',
        ),
        decodingMethod: 'modified_beam_search',
        maxActivePaths: 2,
        enableEndpoint: true,
        hotwordsFile: init['hotwords']! as String,
        hotwordsScore: 1.5,
      ),
    );
    vadConfig = sherpa.VadModelConfig(
      sileroVad: sherpa.SileroVadModelConfig(
        model: init['vadModel']! as String,
        threshold: 0.5,
        minSilenceDuration: 0.35,
        minSpeechDuration: 0.2,
        maxSpeechDuration: 12,
      ),
      sampleRate: _sttSampleRate,
      numThreads: 1,
      provider: 'cpu',
      debug: false,
    );
  } catch (error) {
    replyTo.send({'type': 'initError', 'message': error.toString()});
    commandPort.close();
    return;
  }

  _SttWorkerSession? session;
  replyTo.send({'type': 'ready', 'sendPort': commandPort.sendPort});

  commandPort.listen((message) {
    if (message is! Map) return;
    final type = message['type'];

    if (type == 'dispose') {
      session?.finish(sendFinal: false);
      recognizer.free();
      commandPort.close();
      Isolate.exit();
    }

    final sessionId = message['sessionId'];
    if (sessionId is! int) return;

    try {
      switch (type) {
        case 'start':
          session?.finish(sendFinal: false);
          session = _SttWorkerSession(
            sessionId: sessionId,
            replyTo: replyTo,
            recognizer: recognizer,
            vadConfig: vadConfig,
            modelVersion: modelVersion,
          );
        case 'audio':
          final active = session;
          if (active?.sessionId != sessionId) return;
          final data = message['data'];
          if (data is TransferableTypedData) {
            active!.acceptPcm(data.materialize().asUint8List());
          }
        case 'stop':
          final active = session;
          if (active?.sessionId == sessionId) {
            active!.finish(sendFinal: true);
            session = null;
          }
        case 'cancel':
          final active = session;
          if (active?.sessionId == sessionId) {
            active!.finish(sendFinal: false);
            session = null;
          }
      }
    } catch (error) {
      replyTo.send({
        'type': 'error',
        'sessionId': sessionId,
        'message': error.toString(),
      });
      session?.finish(sendFinal: false);
      session = null;
    }
  });
}

class _SttWorkerSession {
  _SttWorkerSession({
    required this.sessionId,
    required SendPort replyTo,
    required sherpa.OnlineRecognizer recognizer,
    required sherpa.VadModelConfig vadConfig,
    required this.modelVersion,
  })  : _replyTo = replyTo,
        _recognizer = recognizer,
        _vad = sherpa.VoiceActivityDetector(
          config: vadConfig,
          bufferSizeInSeconds: 4,
        ),
        _stream = recognizer.createStream();

  static const _maxPreRollSamples = _sttSampleRate ~/ 4;
  static const _partialDecodeInterval = Duration(milliseconds: 220);
  static const _levelEmitInterval = Duration(milliseconds: 120);
  static const _silenceEndpoint = Duration(milliseconds: 900);

  final int sessionId;
  final String modelVersion;
  final SendPort _replyTo;
  final sherpa.OnlineRecognizer _recognizer;
  final sherpa.VoiceActivityDetector _vad;
  final sherpa.OnlineStream _stream;
  final _preRoll = Queue<Float32List>();
  final _watch = Stopwatch()..start();

  Timer? _endpointTimer;
  var _preRollSamples = 0;
  var _speechStarted = false;
  var _finished = false;
  var _latestText = '';
  DateTime _lastSpeechAt = DateTime.now();
  DateTime _lastDecodeAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastLevelEmitAt = DateTime.fromMillisecondsSinceEpoch(0);

  void acceptPcm(Uint8List data) {
    if (_finished) return;

    final samples = pcm16ToFloat32(data);
    final level = rmsAudioLevel(samples);
    _emitLevel(level);

    _vad.acceptWaveform(samples);
    final voiceNow = _vad.isDetected() || level > 0.025;

    if (!_speechStarted) {
      _appendPreRoll(samples);
      if (!voiceNow) return;
      _speechStarted = true;
      for (final chunk in _preRoll) {
        _stream.acceptWaveform(samples: chunk, sampleRate: _sttSampleRate);
      }
      _preRoll.clear();
      _preRollSamples = 0;
    }

    _stream.acceptWaveform(samples: samples, sampleRate: _sttSampleRate);
    _decodeAndEmit(level);

    if (voiceNow) {
      _lastSpeechAt = DateTime.now();
    }
    _scheduleEndpointCheck();
  }

  void _appendPreRoll(Float32List samples) {
    _preRoll.add(samples);
    _preRollSamples += samples.length;

    while (_preRollSamples > _maxPreRollSamples && _preRoll.isNotEmpty) {
      _preRollSamples -= _preRoll.removeFirst().length;
    }
  }

  void _emitLevel(double level) {
    final now = DateTime.now();
    if (now.difference(_lastLevelEmitAt) < _levelEmitInterval) return;
    _lastLevelEmitAt = now;
    _emit(text: _latestText, isFinal: false, audioLevel: level);
  }

  void _decodeAndEmit(double level, {bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastDecodeAt) < _partialDecodeInterval) {
      return;
    }
    _lastDecodeAt = now;

    while (_recognizer.isReady(_stream)) {
      _recognizer.decode(_stream);
    }

    final result = _recognizer.getResult(_stream);
    final text = result.text.trim();
    if (text.isEmpty || text == _latestText) return;

    _latestText = text;
    _emit(text: _latestText, isFinal: false, audioLevel: level);
  }

  void _scheduleEndpointCheck() {
    _endpointTimer?.cancel();
    _endpointTimer = Timer(_silenceEndpoint, () {
      final hasTrailingSilence =
          DateTime.now().difference(_lastSpeechAt) >= _silenceEndpoint;
      if (!_finished &&
          _speechStarted &&
          _latestText.trim().isNotEmpty &&
          (hasTrailingSilence || _recognizer.isEndpoint(_stream))) {
        finish(sendFinal: true);
      }
    });
  }

  void finish({required bool sendFinal}) {
    if (_finished) return;
    _finished = true;
    _endpointTimer?.cancel();

    if (sendFinal) {
      _vad.flush();
      while (!_vad.isEmpty()) {
        final segment = _vad.front();
        _stream.acceptWaveform(
          samples: segment.samples,
          sampleRate: _sttSampleRate,
        );
        _vad.pop();
      }

      _stream.inputFinished();
      _decodeAndEmit(0, force: true);
      _emit(
        text: postProcessTranscript(_latestText),
        isFinal: true,
        audioLevel: 0,
      );
    }

    _watch.stop();
    _stream.free();
    _vad.free();
  }

  void _emit({
    required String text,
    required bool isFinal,
    required double audioLevel,
  }) {
    _replyTo.send({
      'type': 'transcript',
      'sessionId': sessionId,
      'text': text,
      'isFinal': isFinal,
      'audioLevel': audioLevel,
      'elapsedMs': _watch.elapsedMilliseconds,
      'modelVersion': modelVersion,
    });
  }
}
