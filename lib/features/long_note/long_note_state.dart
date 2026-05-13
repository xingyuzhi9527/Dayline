import 'package:flutter/foundation.dart';

@immutable
class LongNoteState {
  const LongNoteState({
    this.title = '',
    this.body = '',
    this.isSaving = false,
    this.savedPath,
    this.errorMessage,
  });

  final String title;
  final String body;
  final bool isSaving;
  final String? savedPath;
  final String? errorMessage;

  bool get canSave =>
      (title.trim().isNotEmpty || body.trim().isNotEmpty) && !isSaving;

  bool get hasContent => title.trim().isNotEmpty || body.trim().isNotEmpty;

  LongNoteState copyWith({
    String? title,
    String? body,
    bool? isSaving,
    String? savedPath,
    String? errorMessage,
  }) {
    return LongNoteState(
      title: title ?? this.title,
      body: body ?? this.body,
      isSaving: isSaving ?? this.isSaving,
      savedPath: savedPath ?? this.savedPath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
