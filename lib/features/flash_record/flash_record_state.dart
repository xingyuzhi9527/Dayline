import 'package:flutter/foundation.dart';

import '../../core/parser/lui_lite_parser.dart';
import '../../core/stt/stt_engine.dart';

enum FlashPhase { idle, listening, recognized, confirming, saving, saved }

const _unchanged = Object();

@immutable
class FlashRecordState {
  const FlashRecordState({
    this.phase = FlashPhase.idle,
    this.rawText = '',
    this.parsedInput,
    this.errorMessage,
    this.source = 'voice',
    this.sttStatus = SttAvailabilityStatus.loading,
    this.sttStatusMessage = '正在唤醒离线大脑...',
    this.partialText = '',
    this.audioLevel = 0,
    this.transcriptFinal = false,
    this.sttMetadata,
    this.textSaving = false,
    this.savedSequence = 0,
  });

  final FlashPhase phase;
  final String rawText;
  final ParsedInput? parsedInput;
  final String? errorMessage;
  final String source;
  final SttAvailabilityStatus sttStatus;
  final String sttStatusMessage;
  final String partialText;
  final double audioLevel;
  final bool transcriptFinal;
  final SttMetadata? sttMetadata;
  final bool textSaving;
  final int savedSequence;

  bool get hasResult => parsedInput != null;
  bool get isInputActive =>
      phase == FlashPhase.idle || phase == FlashPhase.listening;
  bool get sttReady => sttStatus == SttAvailabilityStatus.ready;
  bool get sttLoading => sttStatus == SttAvailabilityStatus.loading;

  FlashRecordState copyWith({
    FlashPhase? phase,
    String? rawText,
    Object? parsedInput = _unchanged,
    Object? errorMessage = _unchanged,
    String? source,
    SttAvailabilityStatus? sttStatus,
    String? sttStatusMessage,
    String? partialText,
    double? audioLevel,
    bool? transcriptFinal,
    Object? sttMetadata = _unchanged,
    bool? textSaving,
    int? savedSequence,
  }) {
    return FlashRecordState(
      phase: phase ?? this.phase,
      rawText: rawText ?? this.rawText,
      parsedInput: identical(parsedInput, _unchanged)
          ? this.parsedInput
          : parsedInput as ParsedInput?,
      errorMessage: identical(errorMessage, _unchanged)
          ? this.errorMessage
          : errorMessage as String?,
      source: source ?? this.source,
      sttStatus: sttStatus ?? this.sttStatus,
      sttStatusMessage: sttStatusMessage ?? this.sttStatusMessage,
      partialText: partialText ?? this.partialText,
      audioLevel: audioLevel ?? this.audioLevel,
      transcriptFinal: transcriptFinal ?? this.transcriptFinal,
      sttMetadata: identical(sttMetadata, _unchanged)
          ? this.sttMetadata
          : sttMetadata as SttMetadata?,
      textSaving: textSaving ?? this.textSaving,
      savedSequence: savedSequence ?? this.savedSequence,
    );
  }
}
