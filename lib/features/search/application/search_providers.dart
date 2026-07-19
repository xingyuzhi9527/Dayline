import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/repository_providers.dart';
import '../../projects/project_store.dart';
import '../data/local_search_repository.dart';
import '../data/search_index_repository.dart';
import '../data/search_index_service.dart';
import '../domain/search_models.dart';

class SearchFormNotifier extends Notifier<SearchQuery> {
  @override
  SearchQuery build() => const SearchQuery();

  void setText(String value) {
    state = state.copyWith(text: value);
  }

  void setFilters(SearchFilters filters) {
    state = state.copyWith(filters: filters);
  }

  void clearText() {
    state = state.copyWith(text: '');
  }

  void reset() {
    state = const SearchQuery();
  }
}

final searchFormProvider =
    NotifierProvider.autoDispose<SearchFormNotifier, SearchQuery>(
      SearchFormNotifier.new,
    );

final searchIndexServiceProvider = Provider<SearchIndexService>((ref) {
  return SearchIndexService(ref.watch(localDatabaseProvider));
});

final searchIndexRepositoryProvider = Provider<SearchIndexRepository>((ref) {
  return SearchIndexRepository(
    ref.watch(localDatabaseProvider),
    ref.watch(searchIndexServiceProvider),
  );
});

final localSearchRepositoryProvider = Provider<LocalSearchDataSource>((ref) {
  return LocalSearchRepository(
    ref.watch(searchIndexRepositoryProvider),
    projectLoader: () => loadProjectSearchSummaries(ref),
  );
});

final searchDebounceDurationProvider = Provider<Duration>((ref) {
  return const Duration(milliseconds: 250);
});

final searchRecordTypesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) {
  ref.watch(dataDomainVersionProvider(DataDomain.records));
  return ref.watch(recordsRepositoryProvider).findDistinctTypes();
});

final searchIndexWarmupProvider = FutureProvider.autoDispose<SearchIndexState>((
  ref,
) {
  return ref.watch(searchIndexServiceProvider).ensureReady();
});

final searchResultsProvider = FutureProvider.autoDispose<SearchResultPage>((
  ref,
) async {
  final query = ref.watch(searchFormProvider);
  ref.watch(dataDomainVersionProvider(DataDomain.records));
  ref.watch(dataDomainVersionProvider(DataDomain.projects));
  if (query.isEmpty) return SearchResultPage.idle;

  var disposed = false;
  final ready = Completer<void>();
  final timer = Timer(
    ref.watch(searchDebounceDurationProvider),
    ready.complete,
  );
  ref.onDispose(() {
    disposed = true;
    timer.cancel();
    if (!ready.isCompleted) ready.complete();
  });
  await ready.future;
  if (disposed) return SearchResultPage.idle;

  return ref.watch(localSearchRepositoryProvider).search(query);
});
