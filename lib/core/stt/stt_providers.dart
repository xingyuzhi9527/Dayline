import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'debug_stt_engine.dart';
import 'local_stt_service.dart';
import 'stt_engine.dart';

final sttEngineProvider = Provider<SttEngine>((ref) {
  final engine = Platform.isAndroid
      ? LocalSttService.instance
      : kDebugMode
      ? DebugSttEngine()
      : _UnavailableSttEngine();

  return engine;
});

class _UnavailableSttEngine implements SttEngine {
  @override
  Future<SttAvailability> initialize() async {
    return const SttAvailability.unavailable('离线语音暂不可用，请使用文字记录');
  }

  @override
  Future<SttListenSession> startListening({bool transcribe = true}) {
    throw StateError('离线语音暂不可用，请使用文字记录');
  }

  @override
  Future<void> dispose() async {}
}
