import 'dart:async';
import 'dart:convert';

import '../../../core/database/local_database.dart';
import '../../../core/database/repositories.dart';
import '../domain/search_models.dart';
import 'search_index_service.dart';

class SearchIndexRepository {
  SearchIndexRepository(this._database, this._indexService);

  final LocalDatabase _database;
  final SearchIndexService _indexService;

  Future<SearchResultPage> searchRecords(SearchQuery query) async {
    if (query.isEmpty || query.filters.scope == SearchScope.projects) {
      return SearchResultPage.idle;
    }

    final state = await _indexService.readState();
    final useFts = !query.requiresLike && state.isFtsReady;
    if (!useFts) {
      return _searchLike(query, indexBuilding: state.isBuilding);
    }

    try {
      return await _searchFts(query);
    } catch (error) {
      await _indexService.markQueryFailure(error);
      unawaited(_indexService.ensureReady());
      return _searchLike(query);
    }
  }

  Future<SearchResultPage> _searchFts(SearchQuery query) async {
    final database = await _database.executor;
    final match = query.keywords.map(quoteFtsKeyword).join(' AND ');
    final filters = _recordFilters(query.filters);
    final normalized = query.normalizedText;
    final prefix = '${escapeLikePattern(normalized)}%';
    final rows = await database.rawQuery(
      '''
SELECT
  r.id,
  r.date,
  r.type,
  r.content,
  r.tags,
  r.metadata,
  r.updated_at,
  CASE
    WHEN LOWER(TRIM(r.content)) = ? THEN 0
    WHEN LOWER(r.content) LIKE ? ESCAPE '\\' THEN 1
    ELSE 2
  END AS match_level,
  bm25(records_fts) AS relevance
FROM records_fts
JOIN records r ON r.id = records_fts.rowid
WHERE records_fts MATCH ?
  AND r.is_deleted = 0
  ${filters.sql}
ORDER BY match_level ASC, relevance ASC, r.updated_at DESC, r.id ASC
LIMIT 101
''',
      [normalized, prefix, match, ...filters.arguments],
    );
    return _pageFromRows(
      rows,
      SearchBackend.fts5Trigram,
      keywords: query.keywords,
    );
  }

  Future<SearchResultPage> _searchLike(
    SearchQuery query, {
    bool indexBuilding = false,
  }) async {
    final database = await _database.executor;
    final matchClauses = <String>[];
    final matchArguments = <Object?>[];
    for (final keyword in query.keywords) {
      final pattern = '%${escapeLikePattern(keyword)}%';
      matchClauses.add('''
(
  LOWER(r.content) LIKE ? ESCAPE '\\'
  OR LOWER(r.tags) LIKE ? ESCAPE '\\'
  OR LOWER(r.metadata) LIKE ? ESCAPE '\\'
)
''');
      matchArguments.addAll([pattern, pattern, pattern]);
    }
    final filters = _recordFilters(query.filters);
    final normalized = query.normalizedText;
    final prefix = '${escapeLikePattern(normalized)}%';
    final rows = await database.rawQuery(
      '''
SELECT
  r.id,
  r.date,
  r.type,
  r.content,
  r.tags,
  r.metadata,
  r.updated_at,
  CASE
    WHEN LOWER(TRIM(r.content)) = ? THEN 0
    WHEN LOWER(r.content) LIKE ? ESCAPE '\\' THEN 1
    ELSE 2
  END AS match_level,
  0.0 AS relevance
FROM records r
WHERE r.is_deleted = 0
  AND ${matchClauses.join(' AND ')}
  ${filters.sql}
ORDER BY match_level ASC, r.updated_at DESC, r.id ASC
LIMIT 101
''',
      [normalized, prefix, ...matchArguments, ...filters.arguments],
    );
    return _pageFromRows(
      rows,
      SearchBackend.likeFallback,
      keywords: query.keywords,
      indexBuilding: indexBuilding,
    );
  }

  ({String sql, List<Object?> arguments}) _recordFilters(
    SearchFilters filters,
  ) {
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (filters.fromDate != null) {
      clauses.add('r.date >= ?');
      arguments.add(dateKey(filters.fromDate!));
    }
    if (filters.toDate != null) {
      clauses.add('r.date <= ?');
      arguments.add(dateKey(filters.toDate!));
    }
    if (filters.recordTypes.isNotEmpty) {
      final values = filters.recordTypes.toList()..sort();
      clauses.add('r.type IN (${List.filled(values.length, '?').join(', ')})');
      arguments.addAll(values);
    }
    if (filters.projectId != null) {
      final encodedId = escapeLikePattern(jsonEncode(filters.projectId));
      clauses.add('''
(
  r.metadata LIKE ? ESCAPE '\\'
  OR r.metadata LIKE ? ESCAPE '\\'
  OR r.metadata LIKE ? ESCAPE '\\'
  OR r.metadata LIKE ? ESCAPE '\\'
)
''');
      arguments.addAll([
        '%"projectId":$encodedId%',
        '%"projectId": $encodedId%',
        '%"project_id":$encodedId%',
        '%"project_id": $encodedId%',
      ]);
    }
    for (final tag in filters.tags.toList()..sort()) {
      clauses.add("r.tags LIKE ? ESCAPE '\\'");
      arguments.add('%${escapeLikePattern(jsonEncode(tag))}%');
    }
    if (clauses.isEmpty) return (sql: '', arguments: arguments);
    return (sql: 'AND ${clauses.join(' AND ')}', arguments: arguments);
  }

  SearchResultPage _pageFromRows(
    List<Map<String, Object?>> rows,
    SearchBackend backend, {
    required List<String> keywords,
    bool indexBuilding = false,
  }) {
    final hasMore = rows.length > 100;
    final visible = rows
        .take(100)
        .map((row) => _recordFromRow(row, keywords))
        .toList();
    return SearchResultPage(
      items: visible,
      backend: backend,
      hasMore: hasMore,
      indexBuilding: indexBuilding,
    );
  }

  SearchResultItem _recordFromRow(
    Map<String, Object?> row,
    List<String> keywords,
  ) {
    final content = row['content'] as String;
    final tags = _decodeTags(row['tags']);
    final metadata = _decodeMap(row['metadata']);
    final rawMetadata = row['metadata'] as String? ?? '';
    return SearchResultItem(
      kind: SearchResultKind.record,
      stableId: 'record-${row['id']}',
      recordId: row['id'] as int,
      projectId:
          metadata['projectId'] as String? ?? metadata['project_id'] as String?,
      date: row['date'] as String,
      recordType: row['type'] as String,
      title: _oneLine(content),
      snippet: content,
      tags: tags,
      matchReason: _matchReason(content, tags, metadata, rawMetadata, keywords),
      matchLevel: row['match_level'] as int,
      relevance: (row['relevance'] as num?)?.toDouble() ?? 0,
      updatedAt: row['updated_at'] as int,
    );
  }

  SearchMatchReason _matchReason(
    String content,
    List<String> tags,
    Map<String, Object?> metadata,
    String rawMetadata,
    List<String> keywords,
  ) {
    final normalizedContent = normalizeSearchText(content);
    if (keywords.every(normalizedContent.contains)) {
      return SearchMatchReason.content;
    }
    final normalizedTags = normalizeSearchText(tags.join(' '));
    if (keywords.every(normalizedTags.contains)) {
      return SearchMatchReason.tags;
    }
    final normalizedProjectName = normalizeSearchText(
      [
        metadata['projectName'],
        metadata['project_name'],
      ].whereType<String>().join(' '),
    );
    if (normalizedProjectName.isNotEmpty &&
        keywords.every(normalizedProjectName.contains)) {
      return SearchMatchReason.projectName;
    }
    final normalizedMetadata = normalizeSearchText(rawMetadata);
    if (keywords.every(normalizedMetadata.contains)) {
      return SearchMatchReason.projectInfo;
    }
    return SearchMatchReason.multipleFields;
  }
}

List<String> _decodeTags(Object? raw) {
  if (raw is! String || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.whereType<String>().toList(growable: false);
  } catch (_) {
    return const [];
  }
}

Map<String, Object?> _decodeMap(Object? raw) {
  if (raw is! String || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return decoded.cast<String, Object?>();
  } catch (_) {}
  return const {};
}

String _oneLine(String value) {
  final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= 80) return compact;
  return '${compact.substring(0, 80)}...';
}
