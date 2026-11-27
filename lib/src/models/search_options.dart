/// Query execution configuration options.
class SearchOptions {
  /// Whether to enable typo-tolerant fuzzy matching (Levenshtein distance).
  final bool fuzzy;

  /// Maximum edit distance for fuzzy matching (default: 2).
  final int maxEditDistance;

  /// Whether to enable prefix matching (search-as-you-type).
  final bool prefix;

  /// Whether to generate highlighted match snippets.
  final bool highlight;

  /// Pre-tag for highlighting matched terms (default: `<mark>`).
  final String highlightPreTag;

  /// Post-tag for highlighting matched terms (default: `</mark>`).
  final String highlightPostTag;

  /// Maximum number of results to return (pagination limit).
  final int limit;

  /// Pagination offset.
  final int offset;

  const SearchOptions({
    this.fuzzy = false,
    this.maxEditDistance = 2,
    this.prefix = false,
    this.highlight = false,
    this.highlightPreTag = '<mark>',
    this.highlightPostTag = '</mark>',
    this.limit = 20,
    this.offset = 0,
  });

  SearchOptions copyWith({
    bool? fuzzy,
    int? maxEditDistance,
    bool? prefix,
    bool? highlight,
    String? highlightPreTag,
    String? highlightPostTag,
    int? limit,
    int? offset,
  }) {
    return SearchOptions(
      fuzzy: fuzzy ?? this.fuzzy,
      maxEditDistance: maxEditDistance ?? this.maxEditDistance,
      prefix: prefix ?? this.prefix,
      highlight: highlight ?? this.highlight,
      highlightPreTag: highlightPreTag ?? this.highlightPreTag,
      highlightPostTag: highlightPostTag ?? this.highlightPostTag,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }
}
