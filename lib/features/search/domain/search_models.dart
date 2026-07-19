enum SearchBackend { fts5Trigram, likeFallback }

enum SearchScope { all, records, projects }

enum SearchResultKind { record, project }

enum SearchMatchReason {
  content,
  tags,
  projectName,
  projectInfo,
  multipleFields,
}

class SearchFilters {
  const SearchFilters({
    this.scope = SearchScope.all,
    this.fromDate,
    this.toDate,
    this.recordTypes = const {},
    this.projectId,
    this.tags = const {},
  });

  final SearchScope scope;
  final DateTime? fromDate;
  final DateTime? toDate;
  final Set<String> recordTypes;
  final String? projectId;
  final Set<String> tags;

  bool get isEmpty =>
      scope == SearchScope.all &&
      fromDate == null &&
      toDate == null &&
      recordTypes.isEmpty &&
      projectId == null &&
      tags.isEmpty;

  SearchFilters copyWith({
    SearchScope? scope,
    DateTime? fromDate,
    bool clearFromDate = false,
    DateTime? toDate,
    bool clearToDate = false,
    Set<String>? recordTypes,
    String? projectId,
    bool clearProjectId = false,
    Set<String>? tags,
  }) {
    return SearchFilters(
      scope: scope ?? this.scope,
      fromDate: clearFromDate ? null : fromDate ?? this.fromDate,
      toDate: clearToDate ? null : toDate ?? this.toDate,
      recordTypes: Set.unmodifiable(recordTypes ?? this.recordTypes),
      projectId: clearProjectId ? null : projectId ?? this.projectId,
      tags: Set.unmodifiable(tags ?? this.tags),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SearchFilters &&
        other.scope == scope &&
        other.fromDate == fromDate &&
        other.toDate == toDate &&
        _setEquals(other.recordTypes, recordTypes) &&
        other.projectId == projectId &&
        _setEquals(other.tags, tags);
  }

  @override
  int get hashCode => Object.hash(
    scope,
    fromDate,
    toDate,
    Object.hashAll(recordTypes.toList()..sort()),
    projectId,
    Object.hashAll(tags.toList()..sort()),
  );
}

class SearchQuery {
  const SearchQuery({this.text = '', this.filters = const SearchFilters()});

  final String text;
  final SearchFilters filters;

  String get normalizedText => normalizeSearchText(text);
  List<String> get keywords => splitSearchKeywords(text);
  bool get isEmpty => normalizedText.isEmpty;
  bool get requiresLike => keywords.any((keyword) => keyword.runes.length < 3);

  SearchQuery copyWith({String? text, SearchFilters? filters}) {
    return SearchQuery(
      text: text ?? this.text,
      filters: filters ?? this.filters,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SearchQuery && other.text == text && other.filters == filters;

  @override
  int get hashCode => Object.hash(text, filters);
}

class SearchResultItem {
  const SearchResultItem({
    required this.kind,
    required this.stableId,
    required this.title,
    required this.matchReason,
    required this.matchLevel,
    required this.updatedAt,
    this.recordId,
    this.projectId,
    this.date,
    this.recordType,
    this.projectStatus,
    this.snippet,
    this.tags = const [],
    this.relevance = 0,
  });

  final SearchResultKind kind;
  final String stableId;
  final String title;
  final SearchMatchReason matchReason;
  final int matchLevel;
  final int updatedAt;
  final int? recordId;
  final String? projectId;
  final String? date;
  final String? recordType;
  final String? projectStatus;
  final String? snippet;
  final List<String> tags;
  final double relevance;
}

class SearchResultPage {
  const SearchResultPage({
    required this.items,
    required this.backend,
    required this.hasMore,
    this.indexBuilding = false,
  });

  final List<SearchResultItem> items;
  final SearchBackend backend;
  final bool hasMore;
  final bool indexBuilding;

  bool get isFallback => backend == SearchBackend.likeFallback;

  static const idle = SearchResultPage(
    items: [],
    backend: SearchBackend.likeFallback,
    hasMore: false,
  );
}

abstract interface class LocalSearchDataSource {
  Future<SearchResultPage> search(SearchQuery query);
}

String normalizeSearchText(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}

List<String> splitSearchKeywords(String value) {
  final normalized = normalizeSearchText(value);
  if (normalized.isEmpty) return const [];
  return normalized.split(' ');
}

String quoteFtsKeyword(String value) => '"${value.replaceAll('"', '""')}"';

String escapeLikePattern(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

bool _setEquals(Set<Object?> left, Set<Object?> right) {
  return left.length == right.length && left.containsAll(right);
}
