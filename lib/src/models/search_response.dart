/// A single matching item in the search results.
class SearchHit<T> {
  /// The original hydrated entity of type [T].
  final T item;

  /// The unique document identifier.
  final String id;

  /// The relevance score computed by BM25F ranking.
  final double score;

  /// Highlighted snippets keyed by field name.
  final Map<String, List<String>> highlights;

  const SearchHit({
    required this.item,
    required this.id,
    required this.score,
    this.highlights = const {},
  });
}

/// The complete response returned from a search query.
class SearchResponse<T> {
  /// The raw query string that produced this response.
  final String query;

  /// Ordered list of search hits, ranked by relevance score descending.
  final List<SearchHit<T>> hits;

  /// Total count of documents matching the search criteria (before pagination limit).
  final int totalHits;

  /// Aggregated facet counts keyed by field name, then facet value.
  /// Example: `{'brand': {'Apple': 12, 'Samsung': 8}}`
  final Map<String, Map<String, int>> facetCounts;

  /// Search execution latency in milliseconds.
  final int queryTimeMs;

  const SearchResponse({
    this.query = '',
    required this.hits,
    required this.totalHits,
    this.facetCounts = const {},
    required this.queryTimeMs,
  });

  /// Returns `true` when no matching documents were found.
  bool get isEmpty => hits.isEmpty;

  /// Returns `true` when at least one matching document was found.
  bool get isNotEmpty => hits.isNotEmpty;

  /// Convenience getter for just the hydrated items.
  List<T> get items => hits.map((hit) => hit.item).toList();
}
