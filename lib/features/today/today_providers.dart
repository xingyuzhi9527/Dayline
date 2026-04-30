import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository_providers.dart';

final todayRecordCountProvider = FutureProvider<int>((ref) async {
  ref.watch(dataVersionProvider);
  final today = DateTime.now();
  return ref.read(recordsRepositoryProvider).countByDate(today);
});

final todayTodoListProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) async {
  ref.watch(dataVersionProvider);
  final today = DateTime.now();
  return ref.read(todosRepositoryProvider).findByDate(today);
});

final todayTodoStatsProvider = FutureProvider<(int, int)>((ref) async {
  ref.watch(dataVersionProvider);
  final today = DateTime.now();
  final repo = ref.read(todosRepositoryProvider);
  final total = await repo.countByDate(today);
  final completed = await repo.countCompletedByDate(today);
  return (total, completed);
});

final todayFocusMinutesProvider = FutureProvider<int>((ref) async {
  ref.watch(dataVersionProvider);
  final today = DateTime.now();
  return ref.read(focusSessionsRepositoryProvider).sumMinutesByDate(today);
});

final todayTrackerLogCountProvider = FutureProvider<int>((ref) async {
  ref.watch(dataVersionProvider);
  final today = DateTime.now();
  return ref.read(trackerLogsRepositoryProvider).countByDate(today);
});

final todayActiveTrackersProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) async {
  ref.watch(dataVersionProvider);
  return ref.read(trackersRepositoryProvider).findActive();
});

final todayLoggedTrackerIdsProvider = FutureProvider<Set<int>>((ref) async {
  ref.watch(dataVersionProvider);
  final today = DateTime.now();
  final logs = await ref.read(trackerLogsRepositoryProvider).findByDate(today);
  return logs.map((l) => l['tracker_id'] as int).toSet();
});

final recentRecordsProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) async {
  ref.watch(dataVersionProvider);
  return ref.read(recordsRepositoryProvider).findRecent(limit: 3);
});
