import 'package:flutter/foundation.dart';

import '../../core/parser/lui_lite_parser.dart';

const _unchanged = Object();

@immutable
class RecordState {
  const RecordState({
    this.inputText = '',
    this.parsedInput,
    this.isSaving = false,
    this.errorMessage,
  });

  final String inputText;
  final ParsedInput? parsedInput;
  final bool isSaving;
  final String? errorMessage;

  RecordState copyWith({
    String? inputText,
    Object? parsedInput = _unchanged,
    bool? isSaving,
    Object? errorMessage = _unchanged,
  }) {
    return RecordState(
      inputText: inputText ?? this.inputText,
      parsedInput: identical(parsedInput, _unchanged)
          ? this.parsedInput
          : parsedInput as ParsedInput?,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: identical(errorMessage, _unchanged)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  bool get hasPreview => parsedInput != null;
  bool get canSubmit => inputText.trim().isNotEmpty && !isSaving;
}
