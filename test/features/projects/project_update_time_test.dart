import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/core/database/repository_providers.dart';
import 'package:liflow_app/features/projects/projects_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets(
    'project summary and update row read complete stored timestamps',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final timestamp = DateTime(2026, 9, 26, 12, 5);
      final projects = [
        {
          'id': 'project-time',
          'name': '时间项目',
          'status': '进行中',
          'goal': '验证真实时间',
          'lastUpdate': '今天 12:05',
          'lastUpdatedAt': timestamp.millisecondsSinceEpoch,
          'todos': const [],
          'updates': [
            {
              'id': '${timestamp.microsecondsSinceEpoch}-update',
              'time': '今天 12:05',
              'createdAt': timestamp.millisecondsSinceEpoch,
              'source': '项目',
              'text': '一次更新',
              'colorValue': 0xFF000000,
            },
          ],
        },
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsRepositoryProvider.overrideWithValue(
              _FakeSettingsRepository(jsonEncode(projects)),
            ),
            recordsRepositoryProvider.overrideWithValue(_EmptyRecords()),
          ],
          child: const MaterialApp(home: ProjectsPage(standalone: true)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2026-09-26 12:05'), findsWidgets);
      expect(find.text('今天 12:05'), findsNothing);
    },
  );
}

class _FakeSettingsRepository extends AppSettingsRepository {
  _FakeSettingsRepository(this.projects)
    : super(
        LocalDatabase(
          databaseFactory: databaseFactoryFfi,
          databasePath: inMemoryDatabasePath,
        ),
      );

  final String projects;

  @override
  Future<DatabaseRow?> findByKey(String key) async =>
      key == 'projects_state_v1' ? {'key': key, 'value': projects} : null;
}

class _EmptyRecords extends RecordsRepository {
  _EmptyRecords()
    : super(
        LocalDatabase(
          databaseFactory: databaseFactoryFfi,
          databasePath: inMemoryDatabasePath,
        ),
      );

  @override
  Future<List<DatabaseRow>> findAll() async => const [];
}
