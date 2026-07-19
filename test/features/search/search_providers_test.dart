import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/features/search/application/search_providers.dart';
import 'package:liflow_app/features/search/domain/search_models.dart';

void main() {
  test(
    'Given empty text, when results load, then repository is not called',
    () async {
      final repository = _FakeSearchRepository();
      final container = ProviderContainer(
        overrides: [
          localSearchRepositoryProvider.overrideWithValue(repository),
          searchDebounceDurationProvider.overrideWithValue(Duration.zero),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(searchResultsProvider.future);

      expect(result.items, isEmpty);
      expect(repository.queries, isEmpty);
    },
  );

  test(
    'Given rapid input, when debounce settles, then only latest query runs',
    () async {
      final repository = _FakeSearchRepository();
      final container = ProviderContainer(
        overrides: [
          localSearchRepositoryProvider.overrideWithValue(repository),
          searchDebounceDurationProvider.overrideWithValue(Duration.zero),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        searchResultsProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      container.read(searchFormProvider.notifier).setText('first query');
      container.read(searchFormProvider.notifier).setText('latest query');
      final result = await container.read(searchResultsProvider.future);

      expect(repository.queries.map((query) => query.text), ['latest query']);
      expect(result.items.single.title, 'latest query');
    },
  );

  test(
    'Given an in-flight old generation, then its result cannot replace new state',
    () async {
      final repository = _ControllableSearchRepository();
      final container = ProviderContainer(
        overrides: [
          localSearchRepositoryProvider.overrideWithValue(repository),
          searchDebounceDurationProvider.overrideWithValue(Duration.zero),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        searchResultsProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      container.read(searchFormProvider.notifier).setText('old query');
      await repository.waitForCalls(1);
      container.read(searchFormProvider.notifier).setText('new query');
      await repository.waitForCalls(2);
      repository.complete('new query');
      final latest = await container.read(searchResultsProvider.future);
      repository.complete('old query');

      expect(latest.items.single.title, 'new query');
      expect(
        container.read(searchResultsProvider).value?.items.single.title,
        'new query',
      );
    },
  );
}

class _FakeSearchRepository implements LocalSearchDataSource {
  final queries = <SearchQuery>[];

  @override
  Future<SearchResultPage> search(SearchQuery query) async {
    queries.add(query);
    return _page(query.text);
  }
}

class _ControllableSearchRepository implements LocalSearchDataSource {
  final calls = <String, Completer<SearchResultPage>>{};
  final _changed = StreamController<void>.broadcast();

  @override
  Future<SearchResultPage> search(SearchQuery query) {
    final completer = Completer<SearchResultPage>();
    calls[query.text] = completer;
    _changed.add(null);
    return completer.future;
  }

  Future<void> waitForCalls(int count) async {
    while (calls.length < count) {
      await _changed.stream.first;
    }
  }

  void complete(String query) {
    calls[query]!.complete(_page(query));
  }
}

SearchResultPage _page(String title) {
  return SearchResultPage(
    items: [
      SearchResultItem(
        kind: SearchResultKind.record,
        stableId: title,
        title: title,
        matchReason: SearchMatchReason.content,
        matchLevel: 0,
        updatedAt: 0,
      ),
    ],
    backend: SearchBackend.likeFallback,
    hasMore: false,
  );
}
