import 'package:flutter/foundation.dart';

import '../../core/parser/lui_lite_parser.dart';

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
    ParsedInput? parsedInput,
    bool? isSaving,
    String? errorMessage,
  }) {
    return RecordState(
      inputText: inputText ?? this.inputText,
      parsedInput: parsedInput ?? this.parsedInput,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  bool get hasPreview => parsedInput != null;
  bool get canSubmit => inputText.trim().isNotEmpty && !isSaving;
}
