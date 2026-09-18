import '../../projects/project_store.dart';
import '../domain/search_models.dart';
import 'search_index_repository.dart';

typedef ProjectSummaryLoader = Future<List<ProjectSearchSummary>> Function();

class LocalSearchRepository implements LocalSearchDataSource {
  LocalSearchRepository(
    this._recordsRepository, {
    required ProjectSummaryLoader projectLoader,
  }) : _projectLoader = projectLoader;

  final SearchIndexRepository _recordsRepository;
  final ProjectSummaryLoader _projectLoader;

  @override
  Future<SearchResultPage> search(SearchQuery query) async {
    if (query.isEmpty) return SearchResultPage.idle;

    final recordPage = await _recordsRepository.searchRecords(query);
    final projects = query.filters.scope == SearchScope.records
        ? const <SearchResultItem>[]
        : await _searchProjects(query);
    final combined = [...recordPage.items, ...projects]..sort(_compareResults);
    final hasMore = recordPage.hasMore || combined.length > 100;

    return SearchResultPage(
      items: combined.take(100).toList(growable: false),
      backend: recordPage.backend,
      hasMore: hasMore,
      indexBuilding: recordPage.indexBuilding,
    );
  }

  Future<List<SearchResultItem>> _searchProjects(SearchQuery query) async {
    final keywords = query.keywords;
    final normalizedQuery = query.normalizedText;
    final summaries = await _projectLoader();
    final matches = <SearchResultItem>[];
    for (final project in summaries) {
      if (query.filters.projectId != null &&
          query.filters.projectId != project.id) {
        continue;
      }
      final normalizedName = normalizeSearchText(project.name);
      if (!keywords.every(normalizedName.contains)) continue;
      final level = normalizedName == normalizedQuery
          ? 0
          : normalizedName.startsWith(normalizedQuery)
          ? 1
          : 2;
      matches.add(
        SearchResultItem(
          kind: SearchResultKind.project,
          stableId: 'project-${project.id}',
          projectId: project.id,
          title: project.name,
          projectStatus: project.status,
          matchReason: SearchMatchReason.projectName,
          matchLevel: level,
          updatedAt: project.updatedAt,
        ),
      );
    }
    return matches;
  }
}

int _compareResults(SearchResultItem left, SearchResultItem right) {
  final level = left.matchLevel.compareTo(right.matchLevel);
  if (level != 0) return level;
  if (left.kind == SearchResultKind.record &&
      right.kind == SearchResultKind.record) {
    final relevance = left.relevance.compareTo(right.relevance);
    if (relevance != 0) return relevance;
  }
  final updated = right.updatedAt.compareTo(left.updatedAt);
  if (updated != 0) return updated;
  return left.stableId.compareTo(right.stableId);
}
