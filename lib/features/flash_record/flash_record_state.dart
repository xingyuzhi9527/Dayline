import 'package:flutter/foundation.dart';

import '../../core/parser/lui_lite_parser.dart';

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
    this.speechAvailable = false,
    this.speechChecking = true,
  });

  final FlashPhase phase;
  final String rawText;
  final ParsedInput? parsedInput;
  final String? errorMessage;
  final String source;
  final bool speechAvailable;
  final bool speechChecking;

  bool get hasResult => parsedInput != null;
  bool get isInputActive => phase == FlashPhase.idle;

  FlashRecordState copyWith({
    FlashPhase? phase,
    String? rawText,
    Object? parsedInput = _unchanged,
    Object? errorMessage = _unchanged,
    String? source,
    bool? speechAvailable,
    bool? speechChecking,
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
      speechAvailable: speechAvailable ?? this.speechAvailable,
      speechChecking: speechChecking ?? this.speechChecking,
    );
  }
}
