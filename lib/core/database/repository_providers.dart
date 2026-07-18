import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'derived_sync_jobs_repository.dart';
import 'daily_reviews_repository.dart';
import 'local_database.dart';
import 'repositories.dart';
import 'write_operations_repository.dart';

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

final libraryItemsRepositoryProvider = Provider<LibraryItemsRepository>((ref) {
  return LibraryItemsRepository(ref.watch(localDatabaseProvider));
});

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(localDatabaseProvider));
});

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  return AppSettingsRepository(ref.watch(localDatabaseProvider));
});

final mediaAttachmentsRepositoryProvider = Provider<MediaAttachmentsRepository>(
  (ref) {
    return MediaAttachmentsRepository(ref.watch(localDatabaseProvider));
  },
);

final dailyReviewsRepositoryProvider = Provider<DailyReviewsRepository>((ref) {
  return DailyReviewsRepository(ref.watch(localDatabaseProvider));
});

final writeOperationsRepositoryProvider = Provider<WriteOperationsRepository>((
  ref,
) {
  return WriteOperationsRepository(ref.watch(localDatabaseProvider));
});

final derivedSyncJobsRepositoryProvider = Provider<DerivedSyncJobsRepository>((
  ref,
) {
  return DerivedSyncJobsRepository(ref.watch(localDatabaseProvider));
});

class DataVersionNotifier extends Notifier<int> {
  Timer? _debounceTimer;
  final _domainVersions = <DataDomain, int>{
    for (final domain in DataDomain.values) domain: 0,
  };
  final _pendingDomains = <DataDomain>{};
  var _pendingAllDomains = false;

  @override
  int build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });
    return 0;
  }

  void increment({Set<DataDomain>? domains}) {
    final affected = domains ?? DataDomain.values;
    for (final domain in affected) {
      _domainVersions[domain] = (_domainVersions[domain] ?? 0) + 1;
    }
    state = state + 1;
  }

  int versionFor(DataDomain domain) => _domainVersions[domain] ?? 0;

  void incrementSoon({
    Duration delay = const Duration(milliseconds: 250),
    Set<DataDomain>? domains,
  }) {
    if (domains == null) {
      _pendingAllDomains = true;
    } else if (!_pendingAllDomains) {
      _pendingDomains.addAll(domains);
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () {
      final pending = _pendingAllDomains
          ? null
          : Set<DataDomain>.unmodifiable(_pendingDomains);
      _pendingAllDomains = false;
      _pendingDomains.clear();
      _debounceTimer = null;
      increment(domains: pending);
    });
  }
}

enum DataDomain {
  records,
  todos,
  trackers,
  trackerLogs,
  focus,
  expenses,
  bodyLogs,
  reviews,
  projects,
  media,
}

final dataVersionProvider = NotifierProvider<DataVersionNotifier, int>(
  DataVersionNotifier.new,
);

/// A narrow invalidation signal for high-frequency aggregate providers.
///
/// The global [dataVersionProvider] remains available for legacy pages, while
/// dashboard/today providers can subscribe only to the tables they query.
final dataDomainVersionProvider = Provider.family<int, DataDomain>((
  ref,
  domain,
) {
  ref.watch(dataVersionProvider);
  return ref.read(dataVersionProvider.notifier).versionFor(domain);
});
