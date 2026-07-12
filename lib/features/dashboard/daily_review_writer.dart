import '../../core/database/repositories.dart';
import '../../core/database/repository_providers.dart';
import '../../core/markdown/daily_review_markdown.dart';
import '../../core/markdown/markdown_directory_service.dart';
import '../../core/markdown/markdown_note_service.dart';
import '../../core/markdown/markdown_storage_service.dart';

class DailyReviewSaveResult {
  const DailyReviewSaveResult({required this.syncedNote, this.syncError});

  final bool syncedNote;
  final Object? syncError;
}

Future<DailyReviewSaveResult> saveDailyReviewForDate(
  Object ref, {
  required DateTime date,
  required String kept,
  required String adjust,
  required String nextAction,
}) async {
  final day = DateTime(date.year, date.month, date.day);
  await _read(ref, dailyReviewsRepositoryProvider).upsert(
    date: dateKey(day),
    kept: kept,
    adjust: adjust,
    nextAction: nextAction,
  );

  var syncedNote = false;
  Object? syncError;
  try {
    syncedNote = await _syncDailyNoteReview(
      ref,
      day,
      kept: kept,
      adjust: adjust,
      nextAction: nextAction,
    );
  } catch (e) {
    syncError = e;
  }
  _read(
    ref,
    dataVersionProvider.notifier,
  ).increment(domains: {DataDomain.reviews});
  return DailyReviewSaveResult(syncedNote: syncedNote, syncError: syncError);
}

Future<bool> _syncDailyNoteReview(
  Object ref,
  DateTime date, {
  required String kept,
  required String adjust,
  required String nextAction,
}) async {
  final settings = _read(ref, appSettingsRepositoryProvider);
  final dirService = MarkdownDirectoryService(settings);
  if (!await dirService.isConfigured()) return false;

  final noteService = MarkdownNoteService(dirService);
  final location = await noteService.findDailyNote(date);
  if (location == null) return false;

  final storage = MarkdownStorageService(dirService);
  final raw = await storage.readTextFileLocation(location);
  final updated = upsertDailyReviewSection(
    raw,
    kept: kept,
    adjust: adjust,
    nextAction: nextAction,
  );
  await storage.writeTextFileLocation(location, updated);
  return true;
}

T _read<T>(Object ref, dynamic provider) {
  return (ref as dynamic).read(provider) as T;
}
