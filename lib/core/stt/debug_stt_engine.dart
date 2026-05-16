import 'dart:async';
import 'dart:math';

import 'stt_engine.dart';
import 'stt_text_post_processor.dart';

const debugSttMockResults = [
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

class DebugSttEngine implements SttEngine {
  DebugSttEngine({Random? random}) : _random = random ?? Random();

  final Random _random;

  @override
  Future<SttAvailability> initialize() async => const SttAvailability.ready();

  @override
  Future<SttListenSession> startListening({bool transcribe = true}) async {
    final session = _DebugSttListenSession(
      debugSttMockResults[_random.nextInt(debugSttMockResults.length)],
    );
    session.start();
    return session;
  }

  @override
  Future<void> dispose() async {}
}

class _DebugSttListenSession implements SttListenSession {
  _DebugSttListenSession(this._mockText);

  final String _mockText;
  final _controller = StreamController<SttTranscript>.broadcast();
  final _finalCompleter = Completer<SttTranscript>();
  Timer? _timer;
  var _finished = false;
  String _latestText = '';

  @override
  Stream<SttTranscript> get transcripts => _controller.stream;

  void start() {
    _controller.add(
      const SttTranscript(text: '', isFinal: false, audioLevel: 0.2),
    );
    _timer = Timer(const Duration(milliseconds: 800), () {
      if (_finished) return;
      _latestText = _mockText;
      final transcript = SttTranscript(
        text: postProcessTranscript(_latestText),
        isFinal: true,
        audioLevel: 0,
        metadata: const SttMetadata(modelVersion: 'debug-mock'),
      );
      _complete(transcript);
    });
  }

  @override
  Future<SttTranscript> stop({bool transcribe = true}) async {
    if (_finished) return _finalCompleter.future;
    _timer?.cancel();
    final transcript = SttTranscript(
      text: postProcessTranscript(
        _latestText.isEmpty ? _mockText : _latestText,
      ),
      isFinal: true,
      audioLevel: 0,
      metadata: const SttMetadata(modelVersion: 'debug-mock'),
    );
    _complete(transcript);
    return transcript;
  }

  @override
  Future<void> cancel() async {
    _timer?.cancel();
    if (!_finished) {
      _finished = true;
      await _controller.close();
      _finalCompleter.complete(const SttTranscript(text: '', isFinal: true));
    }
  }

  void _complete(SttTranscript transcript) {
    if (_finished) return;
    _finished = true;
    _controller
      ..add(transcript)
      ..close();
    _finalCompleter.complete(transcript);
  }
}
