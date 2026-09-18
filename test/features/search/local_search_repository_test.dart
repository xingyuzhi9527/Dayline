import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/features/projects/project_store.dart';
import 'package:liflow_app/features/search/data/local_search_repository.dart';
import 'package:liflow_app/features/search/data/search_index_repository.dart';
import 'package:liflow_app/features/search/data/search_index_service.dart';
import 'package:liflow_app/features/search/domain/search_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late LocalDatabase database;
  late RecordsRepository records;
  late LocalSearchRepository repository;

  setUp(() {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    records = RecordsRepository(database);
    final indexService = SearchIndexService(database);
    repository = LocalSearchRepository(
      SearchIndexRepository(database, indexService),
      projectLoader: () async => const [
        ProjectSearchSummary(
          id: 'archived-1',
          name: '项目会议',
          status: '归档',
          updatedAt: 300,
        ),
        ProjectSearchSummary(
          id: 'active-1',
          name: '家庭项目会议',
          status: '进行中',
          updatedAt: 200,
        ),
      ],
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'Given current and archived projects, then both merge with record results',
    () async {
      final recordId = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: '今天的项目会议记录',
      );
      await SearchIndexService(database).ensureReady();

      final result = await repository.search(const SearchQuery(text: '项目会议'));

      expect(result.items.first.projectId, 'archived-1');
      expect(result.items.first.projectStatus, '归档');
      expect(
        result.items.map((item) => item.stableId),
        contains('record-$recordId'),
      );
      expect(result.items.map((item) => item.projectId), contains('active-1'));
    },
  );

  test('Given project-only scope, then record matches are excluded', () async {
    await records.create(
      date: DateTime(2026, 7, 19),
      type: 'memo',
      content: '项目会议',
    );

    final result = await repository.search(
      const SearchQuery(
        text: '项目会议',
        filters: SearchFilters(scope: SearchScope.projects),
      ),
    );

    expect(result.items, isNotEmpty);
    expect(
      result.items.every((item) => item.kind == SearchResultKind.project),
      isTrue,
    );
  });

  test(
    'Given record-only filters in all scope, then matching projects remain',
    () async {
      final result = await repository.search(
        SearchQuery(
          text: '项目会议',
          filters: SearchFilters(
            fromDate: DateTime(2099, 1, 1),
            recordTypes: const {'memo'},
            tags: const {'重要'},
          ),
        ),
      );

      expect(
        result.items.where((item) => item.kind == SearchResultKind.project),
        hasLength(2),
      );
    },
  );

  test(
    'Given archived and invalid target ids, then target resolution is exact',
    () {
      const ids = ['active-1', 'archived-1'];

      expect(resolveProjectTargetId(ids, 'archived-1'), 'archived-1');
      expect(resolveProjectTargetId(ids, 'missing'), isNull);
    },
  );
}
