import 'dart:async';

enum SttAvailabilityStatus { loading, ready, unavailable, error }

class SttAvailability {
  const SttAvailability({required this.status, required this.message});

  const SttAvailability.loading()
    : status = SttAvailabilityStatus.loading,
      message = '正在唤醒离线大脑...';

  const SttAvailability.ready()
    : status = SttAvailabilityStatus.ready,
      message = '时刻准备记录你的灵感';

  const SttAvailability.unavailable(this.message)
    : status = SttAvailabilityStatus.unavailable;

  const SttAvailability.error(this.message)
    : status = SttAvailabilityStatus.error;

  final SttAvailabilityStatus status;
  final String message;

  bool get isReady => status == SttAvailabilityStatus.ready;
}

class SttMetadata {
  const SttMetadata({
    this.modelVersion,
    this.language,
    this.elapsed,
    this.emotion,
    this.events,
  });

  final String? modelVersion;
  final String? language;
  final Duration? elapsed;
  final String? emotion;
  final String? events;
}

class SttRecordingDraft {
  const SttRecordingDraft({
    required this.path,
    required this.duration,
    this.mimeType = 'audio/wav',
    this.sampleRate,
    this.codec = 'wav',
  });

  final String path;
  final Duration duration;
  final String mimeType;
  final int? sampleRate;
  final String codec;
}

class SttTranscript {
  const SttTranscript({
    required this.text,
    required this.isFinal,
    this.audioLevel = 0,
    this.metadata = const SttMetadata(),
    this.recordingDraft,
  });

  final String text;
  final bool isFinal;
  final double audioLevel;
  final SttMetadata metadata;
  final SttRecordingDraft? recordingDraft;
}

abstract interface class SttEngine {
  Future<SttAvailability> initialize();

  Future<SttListenSession> startListening();

  Future<void> dispose();
}

abstract interface class SttListenSession {
  Stream<SttTranscript> get transcripts;

  Future<SttTranscript> stop({bool transcribe = true});

  Future<void> cancel();
}
