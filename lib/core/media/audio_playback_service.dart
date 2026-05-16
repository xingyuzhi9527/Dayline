import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final audioPlaybackProvider =
    NotifierProvider<AudioPlaybackNotifier, AudioPlaybackState>(
      AudioPlaybackNotifier.new,
    );

@immutable
class AudioPlaybackState {
  const AudioPlaybackState({
    this.path,
    this.isPlaying = false,
    this.errorMessage,
  });

  final String? path;
  final bool isPlaying;
  final String? errorMessage;

  AudioPlaybackState copyWith({
    Object? path = _unchanged,
    bool? isPlaying,
    Object? errorMessage = _unchanged,
  }) {
    return AudioPlaybackState(
      path: identical(path, _unchanged) ? this.path : path as String?,
      isPlaying: isPlaying ?? this.isPlaying,
      errorMessage: identical(errorMessage, _unchanged)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

const _unchanged = Object();

class AudioPlaybackNotifier extends Notifier<AudioPlaybackState> {
  static const _channel = MethodChannel('liflow/audio_player');

  var _disposed = false;

  @override
  AudioPlaybackState build() {
    _disposed = false;
    _channel.setMethodCallHandler(_handleNativeCall);
    ref.onDispose(() {
      _disposed = true;
      _channel.setMethodCallHandler(null);
      unawaited(_channel.invokeMethod<void>('stop').catchError((_) {}));
    });
    return const AudioPlaybackState();
  }

  Future<void> toggle(String path) async {
    if (state.isPlaying && state.path == path) {
      await stop();
      return;
    }
    await play(path);
  }

  Future<void> play(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      state = const AudioPlaybackState(errorMessage: '录音文件缺失');
      return;
    }

    state = AudioPlaybackState(path: path, isPlaying: true);
    try {
      await _channel.invokeMethod<void>('play', {'path': path});
    } catch (error) {
      if (_disposed) return;
      state = AudioPlaybackState(path: path, errorMessage: '播放失败：$error');
    }
  }

  Future<void> stop() async {
    final previousPath = state.path;
    if (!_disposed) {
      state = AudioPlaybackState(path: previousPath);
    }
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (_disposed) return;
    if (call.method != 'onPlaybackComplete' &&
        call.method != 'onPlaybackStop') {
      return;
    }

    final path = call.arguments is Map
        ? (call.arguments as Map)['path'] as String?
        : null;
    if (path != null && state.path != path) return;
    state = AudioPlaybackState(path: state.path);
  }
}
