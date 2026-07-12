import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repositories.dart';
import '../../core/database/repository_providers.dart';

/// A single canonical date key shared by all Today queries.
///
/// The timer makes an app that stays open across midnight pick up the new day
/// without requiring a full app restart. Consumers are auto-disposed as well,
/// so their query results do not remain cached while the Today page is away.
final todayDateKeyProvider = Provider.autoDispose<String>((ref) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final nextMidnight = DateTime(today.year, today.month, today.day + 1);
  final timer = Timer(nextMidnight.difference(now), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return dateKey(today);
});

DateTime _today(Ref ref) {
  final parsed = DateTime.parse(ref.watch(todayDateKeyProvider));
  return DateTime(parsed.year, parsed.month, parsed.day);
}

final todayRecordCountProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(dataDomainVersionProvider(DataDomain.records));
  final today = _today(ref);
  return ref.read(recordsRepositoryProvider).countByDate(today);
});

final todayTodoListProvider =
    FutureProvider.autoDispose<List<Map<String, Object?>>>((ref) async {
      ref.watch(dataDomainVersionProvider(DataDomain.todos));
      final today = _today(ref);
      return ref.read(todosRepositoryProvider).findByDate(today);
    });

final todayTodoAgendaProvider =
    FutureProvider.autoDispose<List<Map<String, Object?>>>((ref) async {
      ref.watch(dataDomainVersionProvider(DataDomain.todos));
      final today = _today(ref);
      return ref.read(todosRepositoryProvider).findAgenda(anchorDate: today);
    });

final todayTodoStatsProvider = FutureProvider.autoDispose<(int, int)>((
  ref,
) async {
  ref.watch(dataDomainVersionProvider(DataDomain.todos));
  final today = _today(ref);
  final repo = ref.read(todosRepositoryProvider);
  final total = await repo.countByDate(today);
  final completed = await repo.countCompletedByDate(today);
  return (total, completed);
});

final todayFocusMinutesProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(dataDomainVersionProvider(DataDomain.focus));
  final today = _today(ref);
  return ref.read(focusSessionsRepositoryProvider).sumMinutesByDate(today);
});

final todayTrackerLogCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  ref.watch(dataDomainVersionProvider(DataDomain.trackerLogs));
  final today = _today(ref);
  return ref.read(trackerLogsRepositoryProvider).countByDate(today);
});

final todayActiveTrackersProvider =
    FutureProvider.autoDispose<List<Map<String, Object?>>>((ref) async {
      for (final domain in const [
        DataDomain.trackerLogs,
        DataDomain.trackers,
      ]) {
        ref.watch(dataDomainVersionProvider(domain));
      }
      final today = _today(ref);
      final logs = await ref
          .read(trackerLogsRepositoryProvider)
          .findByDate(today);
      if (logs.isEmpty) return const [];

      final loggedIds = logs.map((l) => l['tracker_id'] as int).toSet();
      final trackers = await ref.read(trackersRepositoryProvider).findAll();
      return trackers
          .where((tracker) => loggedIds.contains(tracker['id'] as int))
          .toList(growable: false);
    });

final todayLoggedTrackerIdsProvider = FutureProvider.autoDispose<Set<int>>((
  ref,
) async {
  ref.watch(dataDomainVersionProvider(DataDomain.trackerLogs));
  final today = _today(ref);
  final logs = await ref.read(trackerLogsRepositoryProvider).findByDate(today);
  return logs.map((l) => l['tracker_id'] as int).toSet();
});

final recentRecordsProvider =
    FutureProvider.autoDispose<List<Map<String, Object?>>>((ref) async {
      ref.watch(dataDomainVersionProvider(DataDomain.records));
      return ref.read(recordsRepositoryProvider).findRecent(limit: 3);
    });
