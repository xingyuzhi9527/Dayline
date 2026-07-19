import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/core/theme/app_theme.dart';
import 'package:liflow_app/features/projects/project_store.dart';
import 'package:liflow_app/features/search/application/search_providers.dart';
import 'package:liflow_app/features/search/data/search_index_service.dart';
import 'package:liflow_app/features/search/domain/search_models.dart';
import 'package:liflow_app/features/search/presentation/search_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(binding.platformDispatcher.clearTextScaleFactorTestValue);
  });

  testWidgets(
    'Given a 320dp screen, then search, filters, and results do not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _ResultRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recordsRepositoryProvider.overrideWithValue(
              _RecordTypesRepository(),
            ),
            localSearchRepositoryProvider.overrideWithValue(repository),
            searchDebounceDurationProvider.overrideWithValue(Duration.zero),
            searchIndexWarmupProvider.overrideWith(
              (ref) async => _fallbackState,
            ),
            projectSearchSummariesProvider.overrideWith(
              (ref) async => const [],
            ),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const SearchPage()),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('search-input')),
        '中文搜索',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('search-result-record-1')),
        findsOneWidget,
      );
      expect(find.text('当前使用兼容搜索'), findsOneWidget);
      expect(find.text('仅显示前 100 条结果'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final clearSize = tester.getSize(
        find.byKey(const ValueKey('search-clear')),
      );
      expect(clearSize.width, greaterThanOrEqualTo(48));
      expect(clearSize.height, greaterThanOrEqualTo(48));

      await tester.tap(find.byKey(const ValueKey('search-filter-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(const ValueKey('search-project-filter')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('search-tag-input')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('search-record-type-custom_type')),
        findsOneWidget,
      );
      expect(find.text('多字段命中 · 2026-07-19'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Given repository failure, then error state can retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordsRepositoryProvider.overrideWithValue(_RecordTypesRepository()),
          localSearchRepositoryProvider.overrideWithValue(_ErrorRepository()),
          searchDebounceDurationProvider.overrideWithValue(Duration.zero),
          searchIndexWarmupProvider.overrideWith((ref) async => _fallbackState),
          projectSearchSummariesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const SearchPage()),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('search-input')), '失败查询');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('搜索暂时不可用'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _fallbackState = SearchIndexState(
  backend: 'like_fallback',
  status: 'ready',
  schemaVersion: 1,
  updatedAt: 1,
);

class _ResultRepository implements LocalSearchDataSource {
  @override
  Future<SearchResultPage> search(SearchQuery query) async {
    return const SearchResultPage(
      items: [
        SearchResultItem(
          kind: SearchResultKind.record,
          stableId: 'record-1',
          recordId: 1,
          date: '2026-07-19',
          recordType: 'memo',
          title: '中文搜索结果',
          matchReason: SearchMatchReason.multipleFields,
          matchLevel: 0,
          updatedAt: 1,
        ),
      ],
      backend: SearchBackend.likeFallback,
      hasMore: true,
    );
  }
}

class _ErrorRepository implements LocalSearchDataSource {
  @override
  Future<SearchResultPage> search(SearchQuery query) {
    throw StateError('search failed');
  }
}

class _RecordTypesRepository extends RecordsRepository {
  _RecordTypesRepository()
    : super(
        LocalDatabase(
          databaseFactory: databaseFactoryFfi,
          databasePath: inMemoryDatabasePath,
        ),
      );

  @override
  Future<List<String>> findDistinctTypes() async => const ['custom_type'];
}
