import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/app.dart';
import 'package:liflow_app/app_router.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/features/search/domain/search_models.dart';
import 'package:liflow_app/features/search/data/search_index_service.dart';
import 'package:liflow_app/features/projects/project_store.dart';
import 'package:liflow_app/features/search/application/search_providers.dart';
import 'package:liflow_app/features/search/presentation/search_page.dart';
import 'package:liflow_app/core/stt/stt_engine.dart';
import 'package:liflow_app/core/stt/stt_providers.dart';
import 'package:liflow_app/features/dashboard/dashboard_providers.dart';
import 'package:liflow_app/features/timeline/timeline_providers.dart';
import 'package:liflow_app/shell/liflow_shell.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SearchSettings extends AppSettingsRepository {
  _SearchSettings(super.database, this.projectsJson);
  final String projectsJson;
  @override
  Future<DatabaseRow?> findByKey(String key) async {
    if (key != projectsSettingsKey) {
      throw StateError('Storage setup unavailable in navigation test');
    }
    return {'key': key, 'value': projectsJson};
  }
}

class _SearchRecords extends RecordsRepository {
  _SearchRecords(super.database);
  @override
  Future<List<DatabaseRow>> findByDate(DateTime date) async => [];
  @override
  Future<List<String>> findDistinctTypes() async => [];
}

class _ProjectSearchResults implements LocalSearchDataSource {
  @override
  Future<SearchResultPage> search(SearchQuery query) async => SearchResultPage(
    items: [
      for (final id in ['alpha', 'beta'])
        if (query.filters.projectId == null || query.filters.projectId == id)
          SearchResultItem(
            kind: SearchResultKind.project,
            stableId: 'project-$id',
            projectId: id,
            title: 'Alpha $id',
            matchReason: SearchMatchReason.projectName,
            matchLevel: 1,
            updatedAt: 1,
          ),
    ],
    backend: SearchBackend.likeFallback,
    hasMore: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('project search keeps scope and query across source navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final projectsJson = jsonEncode([
      {
        'id': 'alpha',
        'name': 'Alpha project with a very long name',
        'status': '进行中',
        'todos': [],
        'updates': [],
      },
      {
        'id': 'beta',
        'name': 'Alpha other',
        'status': '归档',
        'todos': [],
        'updates': [],
      },
    ]);
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(database),
        appSettingsRepositoryProvider.overrideWithValue(
          _SearchSettings(database, projectsJson),
        ),
        recordsRepositoryProvider.overrideWithValue(_SearchRecords(database)),
        localSearchRepositoryProvider.overrideWithValue(
          _ProjectSearchResults(),
        ),
        searchIndexWarmupProvider.overrideWith(
          (ref) async => const SearchIndexState(
            backend: 'like_fallback',
            status: 'ready',
            schemaVersion: 1,
            updatedAt: 1,
          ),
        ),
        sttEngineProvider.overrideWithValue(_CountingSttEngine()),
        dashboardSummaryProvider.overrideWith((ref) async => _emptySummary()),
        dashboardReviewProvider.overrideWith((ref) async => null),
        timelineEventsProvider.overrideWith((ref) async => const []),
        deletedRecordsProvider.overrideWith((ref) async => const []),
        searchDebounceDurationProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LiflowApp()),
    );
    router.go('/projects');
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await container.read(projectSearchSummariesProvider.future);
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('projects-search')));
    await tester.pumpAndSettle();
    final searchContainer = ProviderScope.containerOf(
      tester.element(find.byType(SearchPage)),
    );
    expect(searchContainer.read(searchFormProvider).filters.projectId, 'alpha');
    await tester.enterText(find.byKey(const ValueKey('search-input')), 'Alpha');
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await searchContainer.read(searchResultsProvider.future);
    });
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('search-result-project-beta')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('search-result-project-alpha')));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/projects/search/project/alpha',
    );
    router.pop();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('search-input')))
          .controller!
          .text,
      'Alpha',
    );
    expect(searchContainer.read(searchFormProvider).filters.projectId, 'alpha');
    await tester.tap(find.byTooltip('搜索全部项目'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await searchContainer.read(searchResultsProvider.future);
    });
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('search-result-project-beta')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('返回项目'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/projects');
    router.go('/dashboard/search');
    await tester.pumpAndSettle();
    final globalContainer = ProviderScope.containerOf(
      tester.element(find.byType(SearchPage)),
    );
    expect(globalContainer.read(searchFormProvider).isEmpty, isTrue);
    expect(globalContainer.read(searchFormProvider).filters.projectId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('router and swipe keep the visible branch in sync', (
    tester,
  ) async {
    final sttEngine = _CountingSttEngine();
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(
          LocalDatabase(
            databaseFactory: databaseFactoryFfi,
            databasePath: inMemoryDatabasePath,
          ),
        ),
        sttEngineProvider.overrideWithValue(sttEngine),
        dashboardSummaryProvider.overrideWith((ref) async => _emptySummary()),
        dashboardReviewProvider.overrideWith((ref) async => null),
        timelineEventsProvider.overrideWith((ref) async => const []),
        deletedRecordsProvider.overrideWith((ref) async => const []),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LiflowApp()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(router.routeInformationProvider.value.uri.path, '/record');
    expect(_branchPage(tester), closeTo(1, 0.01));
    expect(sttEngine.initializeCount, 0);

    await tester.tap(find.text('盘').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/dashboard');
    expect(_branchContainer(tester).navigationShell.currentIndex, 3);
    await tester.pump(const Duration(milliseconds: 700));
    expect(_branchPage(tester), closeTo(3, 0.01));

    router.go('/line');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/line');
    expect(_branchPage(tester), closeTo(0, 0.01));

    await tester.drag(
      find.byKey(const ValueKey('liflow-branch-page-view')),
      const Offset(-500, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/record');
    expect(_branchPage(tester), closeTo(1, 0.01));
  });

  testWidgets('dark shell uses semantic surface and navigation colors', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(
          LocalDatabase(
            databaseFactory: databaseFactoryFfi,
            databasePath: inMemoryDatabasePath,
          ),
        ),
        sttEngineProvider.overrideWithValue(_CountingSttEngine()),
        dashboardSummaryProvider.overrideWith((ref) async => _emptySummary()),
        dashboardReviewProvider.overrideWith((ref) async => null),
        timelineEventsProvider.overrideWith((ref) async => const []),
        deletedRecordsProvider.overrideWith((ref) async => const []),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LiflowApp()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final navigation = find.byKey(const ValueKey('liflow-bottom-navigation'));
    final context = tester.element(navigation);
    final colors = Theme.of(context).colorScheme;
    final decoration =
        tester.widget<DecoratedBox>(navigation).decoration as BoxDecoration;
    final topBorder = decoration.border as Border;
    final unselectedLabel = tester.widget<Text>(
      find.descendant(of: navigation, matching: find.text('线')),
    );
    final intentPill = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('unified-intent-pill')),
    );
    final pillDecoration = intentPill.decoration as BoxDecoration;

    expect(Theme.of(context).brightness, Brightness.dark);
    expect(decoration.color, colors.surface.withAlpha(242));
    expect(topBorder.top.color, colors.outlineVariant);
    expect(unselectedLabel.style?.color, colors.onSurfaceVariant);
    expect(pillDecoration.color, colors.surface.withAlpha(218));
    expect(
      (pillDecoration.border as Border).top.color,
      colors.outlineVariant.withAlpha(180),
    );
  });

  testWidgets(
    'dashboard collapsed and expanded search routes cover bottom navigation',
    (tester) async {
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = LocalDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          sttEngineProvider.overrideWithValue(_CountingSttEngine()),
          dashboardSummaryProvider.overrideWith((ref) async => _emptySummary()),
          dashboardReviewProvider.overrideWith((ref) async => null),
          timelineEventsProvider.overrideWith((ref) async => const []),
          deletedRecordsProvider.overrideWith((ref) async => const []),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const LiflowApp(),
        ),
      );
      router.go('/dashboard');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      final collapsedSearch = find.ancestor(
        of: find.byKey(const ValueKey('dashboard-search-shortcut')),
        matching: find.byType(InkWell),
      );
      tester.widget<InkWell>(collapsedSearch).onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        router.routeInformationProvider.value.uri.path,
        '/dashboard/search',
      );
      expect(find.byKey(const ValueKey('search-page')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('liflow-bottom-navigation')),
        findsNothing,
      );

      router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.byKey(const ValueKey('dashboard-open-review-pill')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('dashboard-empty-expanded-search')),
        findsOneWidget,
      );
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('dashboard-empty-expanded-search')),
          )
          .onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        router.routeInformationProvider.value.uri.path,
        '/dashboard/search',
      );
      expect(
        find.byKey(const ValueKey('liflow-bottom-navigation')),
        findsNothing,
      );
    },
  );
}

double _branchPage(WidgetTester tester) {
  final pageView = tester.widget<PageView>(
    find.byKey(const ValueKey('liflow-branch-page-view')),
  );
  return pageView.controller!.page!;
}

LiflowBranchNavigatorContainer _branchContainer(WidgetTester tester) {
  return tester.widget<LiflowBranchNavigatorContainer>(
    find.byType(LiflowBranchNavigatorContainer),
  );
}

DashboardSummary _emptySummary() {
  return const DashboardSummary(
    date: '2026-07-12',
    recordCount: 0,
    totalTodos: 0,
    completedTodos: 0,
    trackerCount: 0,
    focusMinutes: 0,
    expenseTotal: 0,
    monthExpenseTotal: 0,
    expenseCount: 0,
    bodyLogCount: 0,
    topTags: [],
    categoryCounts: {},
    firstActivityTime: null,
    lastActivityTime: null,
    longestGapMinutes: 0,
    densestHourRange: '-',
    insights: [],
    allTimestamps: [],
    isReviewed: false,
  );
}

class _CountingSttEngine implements SttEngine {
  var initializeCount = 0;

  @override
  Future<SttAvailability> initialize() async {
    initializeCount += 1;
    return const SttAvailability.ready();
  }

  @override
  Future<SttListenSession> startListening({bool transcribe = true}) {
    throw UnsupportedError('Not used by this test.');
  }

  @override
  Future<void> dispose() async {}
}
