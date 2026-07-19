import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/local_database.dart';
import 'package:liflow_app/core/database/repositories.dart';
import 'package:liflow_app/features/search/data/search_index_repository.dart';
import 'package:liflow_app/features/search/data/search_index_service.dart';
import 'package:liflow_app/features/search/domain/search_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late LocalDatabase database;
  late RecordsRepository records;
  late SearchIndexService indexService;
  late SearchIndexRepository repository;

  setUp(() {
    database = LocalDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    records = RecordsRepository(database);
    indexService = SearchIndexService(database);
    repository = SearchIndexRepository(database, indexService);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'Given empty text, when searched, then no database query is required',
    () async {
      final result = await repository.searchRecords(const SearchQuery());

      expect(result.items, isEmpty);
      expect(result.hasMore, isFalse);
    },
  );

  test(
    'Given one or two Unicode characters, when searched, then LIKE is used',
    () async {
      final id = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: '中文短词记录',
      );
      await indexService.ensureReady();

      final one = await repository.searchRecords(const SearchQuery(text: '中'));
      final two = await repository.searchRecords(const SearchQuery(text: '中文'));

      expect(one.backend, SearchBackend.likeFallback);
      expect(two.backend, SearchBackend.likeFallback);
      expect(one.items.single.recordId, id);
      expect(two.items.single.recordId, id);
    },
  );

  test(
    'Given ready FTS, when searched, then exact precedes prefix and contains',
    () async {
      final exact = await records.create(
        date: DateTime(2026, 7, 17),
        type: 'memo',
        content: '项目会议',
        createdAt: DateTime(2026, 7, 17),
      );
      final prefix = await records.create(
        date: DateTime(2026, 7, 18),
        type: 'memo',
        content: '项目会议安排',
        createdAt: DateTime(2026, 7, 18),
      );
      final contains = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: '今天讨论项目会议安排',
        createdAt: DateTime(2026, 7, 19),
      );
      await indexService.ensureReady();

      final result = await repository.searchRecords(
        const SearchQuery(text: '项目会议'),
      );

      expect(result.backend, SearchBackend.fts5Trigram);
      expect(result.items.map((item) => item.recordId), [
        exact,
        prefix,
        contains,
      ]);
      expect(result.items.map((item) => item.matchLevel), [0, 1, 2]);
    },
  );

  test(
    'Given multiple words and operator text, then app-generated AND stays literal',
    () async {
      final both = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: 'alpha NOTHING omega',
      );
      await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: 'alpha only',
      );
      await indexService.ensureReady();

      final result = await repository.searchRecords(
        const SearchQuery(text: 'alpha NOTHING'),
      );

      expect(result.items.map((item) => item.recordId), [both]);
    },
  );

  test(
    'Given keywords across content and tags, then match reason is multi-field',
    () async {
      final id = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: 'alpha in content',
        tags: const ['beta-tag'],
      );
      await indexService.ensureReady();

      final result = await repository.searchRecords(
        const SearchQuery(text: 'alpha beta'),
      );

      expect(result.items.single.recordId, id);
      expect(result.items.single.matchReason, SearchMatchReason.multipleFields);
    },
  );

  test(
    'Given non-name project metadata, then match reason is project info',
    () async {
      final id = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: 'ordinary content',
        metadata: const {'projectId': '关联编码'},
      );
      await indexService.ensureReady();

      final result = await repository.searchRecords(
        const SearchQuery(text: '关联编码'),
      );

      expect(result.items.single.recordId, id);
      expect(result.items.single.matchReason, SearchMatchReason.projectInfo);
    },
  );

  test(
    'Given LIKE wildcard characters, when searched, then they stay literal',
    () async {
      final percent = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: 'progress 50% complete',
      );
      final underscore = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: 'literal_name',
      );
      await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: 'no wildcard here',
      );

      final percentResult = await repository.searchRecords(
        const SearchQuery(text: '%'),
      );
      final underscoreResult = await repository.searchRecords(
        const SearchQuery(text: '_'),
      );

      expect(percentResult.items.map((item) => item.recordId), [percent]);
      expect(underscoreResult.items.map((item) => item.recordId), [underscore]);
    },
  );

  test(
    'Given quotes, slashes, colons, case, and FTS words, then all stay literal',
    () async {
      final id = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: r'Say"Yes path\local key:value literal NEAR token',
      );
      await indexService.ensureReady();

      for (final query in const [
        'say"yes',
        r'\',
        'key:value',
        'NEAR',
        'TOKEN',
      ]) {
        final result = await repository.searchRecords(SearchQuery(text: query));
        expect(
          result.items.map((item) => item.recordId),
          [id],
          reason: 'Query must remain literal: $query',
        );
      }
    },
  );

  test(
    'Given filters, when FTS and LIKE search, then both return the same row',
    () async {
      final included = await records.create(
        date: DateTime(2026, 7, 19),
        type: 'memo',
        content: '中文搜索目标',
        tags: const ['重要'],
        metadata: const {'projectId': 'project-1'},
      );
      await records.create(
        date: DateTime(2026, 7, 18),
        type: 'long_note',
        content: '中文搜索排除',
        tags: const ['其他'],
        metadata: const {'projectId': 'project-2'},
      );
      await indexService.ensureReady();
      const filters = SearchFilters(
        fromDate: null,
        recordTypes: {'memo'},
        projectId: 'project-1',
        tags: {'重要'},
      );

      final fts = await repository.searchRecords(
        SearchQuery(
          text: '中文搜',
          filters: filters.copyWith(fromDate: DateTime(2026, 7, 19)),
        ),
      );
      final like = await repository.searchRecords(
        SearchQuery(
          text: '中文',
          filters: filters.copyWith(fromDate: DateTime(2026, 7, 19)),
        ),
      );

      expect(fts.items.map((item) => item.recordId), [included]);
      expect(like.items.map((item) => item.recordId), [included]);
    },
  );

  test(
    'Given 101 matching rows, when searched, then 100 are shown with hasMore',
    () async {
      for (var index = 0; index < 101; index++) {
        await records.create(
          date: DateTime(2026, 7, 19),
          type: 'memo',
          content: '批量搜索记录 $index',
          createdAt: DateTime.fromMillisecondsSinceEpoch(index + 1),
        );
      }
      await indexService.ensureReady();

      final result = await repository.searchRecords(
        const SearchQuery(text: '批量搜索'),
      );

      expect(result.items, hasLength(100));
      expect(result.hasMore, isTrue);
    },
  );
}
