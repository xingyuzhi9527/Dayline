import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/app.dart';
import 'package:liflow_app/app_router.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/stt/stt_engine.dart';
import 'package:liflow_app/core/stt/stt_providers.dart';
import 'package:liflow_app/features/dashboard/dashboard_providers.dart';
import 'package:liflow_app/features/timeline/timeline_providers.dart';
import 'package:liflow_app/shell/liflow_shell.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

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
