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

  testWidgets('给定八条项目待办，默认收纳第八条并可展开', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final todos = [
      for (var index = 0; index < 8; index++)
        {
          'id':
              '${now.add(Duration(minutes: index)).microsecondsSinceEpoch}-todo',
          'title': '测试待办 ${index + 1}',
          'done': false,
        },
    ];
    final projectsJson = jsonEncode([
      {
        'id': 'collapse-test-project',
        'name': '收纳测试',
        'status': '进行中',
        'goal': '保持项目页简洁',
        'lastUpdate': '刚刚',
        'todos': todos,
        'updates': [],
      },
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(
            _FakeAppSettingsRepository(projectsJson),
          ),
          recordsRepositoryProvider.overrideWithValue(
            _EmptyRecordsRepository(),
          ),
        ],
        child: const MaterialApp(home: ProjectsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final todoKeys = [
      for (final todo in todos) ValueKey(todo['id']! as String),
    ];
    expect(find.byKey(todoKeys.first), findsNothing);
    for (final key in todoKeys.skip(1)) {
      expect(find.byKey(key), findsOneWidget);
    }
    final archiveToggle = find.byKey(
      const ValueKey('project-todo-archive-toggle'),
    );
    expect(archiveToggle, findsOneWidget);
    expect(find.text('1 个待办已收纳'), findsOneWidget);

    await tester.ensureVisible(archiveToggle);
    await tester.tap(archiveToggle);
    await tester.pump();

    for (final key in todoKeys) {
      expect(find.byKey(key), findsOneWidget);
    }
  });
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
