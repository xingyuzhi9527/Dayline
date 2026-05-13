import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/markdown_note_service.dart';
import '../../core/database/repository_providers.dart';
import 'long_note_state.dart';

final longNoteProvider =
    NotifierProvider<LongNoteNotifier, LongNoteState>(
      LongNoteNotifier.new,
    );

class LongNoteNotifier extends Notifier<LongNoteState> {
  @override
  LongNoteState build() => const LongNoteState();

  void updateTitle(String title) {
    state = state.copyWith(title: title, errorMessage: null);
  }

  void updateBody(String body) {
    state = state.copyWith(body: body, errorMessage: null);
  }

  Future<bool> save() async {
    if (!state.canSave) return false;

    state = state.copyWith(isSaving: true, errorMessage: null, savedPath: null);

    try {
      final settings = ref.read(appSettingsRepositoryProvider);
      final dirService = MarkdownDirectoryService(settings);
      final noteService = MarkdownNoteService(dirService);

      final path = await noteService.saveLongNote(
        title: state.title,
        body: state.body,
        dateTime: DateTime.now(),
      );

      // Write timeline index
      final wordCount = state.body
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .split(' ')
          .where((w) => w.isNotEmpty)
          .length;

      final content = state.title.trim().isNotEmpty
          ? state.title.trim()
          : _fallbackTitle();

      await ref.read(recordsRepositoryProvider).create(
            date: DateTime.now(),
            type: 'long_note',
            content: content,
            metadata: {
              'path': path,
              'title': content,
              'wordCount': wordCount,
            },
          );

      ref.read(dataVersionProvider.notifier).increment();

      state = state.copyWith(isSaving: false, savedPath: path);
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: e.toString());
      return false;
    }
  }

  String _fallbackTitle() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} $h:$m';
  }
}
