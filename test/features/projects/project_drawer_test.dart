import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/features/projects/project_store.dart';
import 'package:liflow_app/features/projects/projects_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets(
    'Given multiple projects, When drawer selects a project, Then card stays stable',
    (tester) async {
      _configureView(tester);
      await _pumpProjectsPage(tester, _projectFixtures());

      final cardFinder = find.byKey(const ValueKey('project-current-card'));
      final initialCardSize = tester.getSize(cardFinder);

      expect(
        find.byKey(const ValueKey('project-switcher-drawer')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('project-drawer-open-button')),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('project-switcher-drawer')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('project-drawer-item-active-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('project-drawer-item-active-b')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('project-filter-completed')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('project-drawer-item-completed')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('project-switcher-drawer')),
        findsNothing,
      );
      expect(tester.getSize(cardFinder), initialCardSize);
      expect(find.text('已经完成'), findsWidgets);
    },
  );

  testWidgets(
    'Given only a completed project, When page loads, Then it becomes current',
    (tester) async {
      _configureView(tester);
      await _pumpProjectsPage(tester, [
        _project(id: 'only-completed', name: '唯一项目', status: '完成'),
      ]);

      expect(
        find.byKey(const ValueKey('project-current-card')),
        findsOneWidget,
      );
      expect(find.text('唯一项目'), findsOneWidget);
    },
  );
}

void _configureView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpProjectsPage(
  WidgetTester tester,
  List<Map<String, Object?>> projects,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(
          _FakeAppSettingsRepository(jsonEncode(projects)),
        ),
        recordsRepositoryProvider.overrideWithValue(_EmptyRecordsRepository()),
      ],
      child: const MaterialApp(home: ProjectsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

List<Map<String, Object?>> _projectFixtures() => [
  _project(id: 'active-a', name: '当前项目', status: '进行中'),
  _project(id: 'active-b', name: '准备项目', status: '未开始'),
  _project(id: 'completed', name: '已经完成', status: '完成'),
  _project(id: 'archived', name: '归档项目', status: '归档'),
];

Map<String, Object?> _project({
  required String id,
  required String name,
  required String status,
}) {
  return {
    'id': id,
    'name': name,
    'status': status,
    'goal': '保持项目推进清晰',
    'lastUpdate': '刚刚',
    'todos': const [],
    'updates': const [],
  };
}

class _FakeAppSettingsRepository extends AppSettingsRepository {
  _FakeAppSettingsRepository(this.projectsJson)
    : super(
        LocalDatabase(
          databaseFactory: databaseFactoryFfi,
          databasePath: inMemoryDatabasePath,
        ),
      );

  final String projectsJson;

  @override
  Future<DatabaseRow?> findByKey(String key) async {
    if (key != projectsSettingsKey) return null;
    return {'key': key, 'value': projectsJson};
  }
}

class _EmptyRecordsRepository extends RecordsRepository {
  _EmptyRecordsRepository()
    : super(
        LocalDatabase(
          databaseFactory: databaseFactoryFfi,
          databasePath: inMemoryDatabasePath,
        ),
      );

  @override
  Future<List<DatabaseRow>> findByDate(DateTime date) async => const [];
}
