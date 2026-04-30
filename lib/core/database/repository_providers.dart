import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class DataVersionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state = state + 1;
}

final dataVersionProvider = NotifierProvider<DataVersionNotifier, int>(
  DataVersionNotifier.new,
);
