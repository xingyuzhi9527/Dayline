import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'daily_reviews_repository.dart';
import 'local_database.dart';
import 'repositories.dart';

final recordsRepositoryProvider = Provider<RecordsRepository>((ref) {
  return RecordsRepository(ref.watch(localDatabaseProvider));
});

final todosRepositoryProvider = Provider<TodosRepository>((ref) {
  return TodosRepository(ref.watch(localDatabaseProvider));
});

final trackersRepositoryProvider = Provider<TrackersRepository>((ref) {
  return TrackersRepository(ref.watch(localDatabaseProvider));
});

final trackerLogsRepositoryProvider = Provider<TrackerLogsRepository>((ref) {
  return TrackerLogsRepository(ref.watch(localDatabaseProvider));
});

final focusSessionsRepositoryProvider = Provider<FocusSessionsRepository>((
  ref,
) {
  return FocusSessionsRepository(ref.watch(localDatabaseProvider));
});

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  return ExpensesRepository(ref.watch(localDatabaseProvider));
});

final bodyLogsRepositoryProvider = Provider<BodyLogsRepository>((ref) {
  return BodyLogsRepository(ref.watch(localDatabaseProvider));
});

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  return AppSettingsRepository(ref.watch(localDatabaseProvider));
});

final dailyReviewsRepositoryProvider = Provider<DailyReviewsRepository>((ref) {
  return DailyReviewsRepository(ref.watch(localDatabaseProvider));
});

class DataVersionNotifier extends Notifier<int> {
  Timer? _debounceTimer;

  @override
  int build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });
    return 0;
  }

  void increment() => state = state + 1;

  void incrementSoon([
    Duration delay = const Duration(milliseconds: 250),
  ]) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, increment);
  }
}

final dataVersionProvider = NotifierProvider<DataVersionNotifier, int>(
  DataVersionNotifier.new,
);
