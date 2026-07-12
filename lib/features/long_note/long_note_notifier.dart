import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/markdown_note_service.dart';
import '../../core/markdown/markdown_storage_service.dart';
import '../../core/database/repository_providers.dart';
import '../projects/project_store.dart';
import 'long_note_state.dart';

final longNoteProvider = NotifierProvider<LongNoteNotifier, LongNoteState>(
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

  Future<bool> save(String title, String body, {ProjectOption? project}) async {
    final trimmedTitle = title.trim();
    final trimmedBody = body.trim();
    if (trimmedTitle.isEmpty && trimmedBody.isEmpty) return false;

    state = state.copyWith(isSaving: true, errorMessage: null, savedPath: null);

    try {
      final now = DateTime.now();
      final settings = ref.read(appSettingsRepositoryProvider);
      final dirService = MarkdownDirectoryService(settings);
      final noteService = MarkdownNoteService(dirService);

      final savedNote = await noteService.saveLongNoteWithInfo(
        title: trimmedTitle,
        body: trimmedBody,
        dateTime: now,
        projectId: project?.id,
        projectName: project?.name,
      );
      final path = savedNote.location;

      // Write timeline index
      final wordCount = trimmedBody
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .split(' ')
          .where((w) => w.isNotEmpty)
          .length;

      final content = trimmedTitle.isNotEmpty ? trimmedTitle : _fallbackTitle();

      final recordId = await ref
          .read(recordsRepositoryProvider)
          .create(
            date: now,
            type: 'long_note',
            content: content,
            metadata: {
              'path': path,
              'title': content,
              'fileName': savedNote.fileName,
              'relativePath': savedNote.relativePath,
              'displayPath': MarkdownStorageService.displayPathForLocation(
                path,
              ),
              'wordCount': wordCount,
              if (project != null) ...{
                'projectId': project.id,
                'projectName': project.name,
                'projectEntryType': 'long_note',
              },
            },
          );

      if (project != null) {
        await addProjectLongNote(
          ref,
          projectId: project.id,
          title: content,
          path: path,
          relativePath: savedNote.relativePath,
          fileName: savedNote.fileName,
          recordId: recordId,
          updatedAt: now,
        );
      }

      ref
          .read(dataVersionProvider.notifier)
          .increment(
            domains: project == null
                ? const {DataDomain.records}
                : const {DataDomain.projects, DataDomain.records},
          );

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
