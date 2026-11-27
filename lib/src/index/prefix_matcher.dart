import '../storage/storage_adapter.dart';
import '../storage/storage_records.dart';

/// Handles fast B-tree indexed prefix lookups for search-as-you-type autocomplete.
class PrefixMatcher {
  /// Default relevance discount for prefix matches compared to exact matches.
  static const double defaultPrefixWeight = 0.85;

  const PrefixMatcher();

  /// Fetches postings for all terms starting with [prefix] from [storage].
  Future<List<PostingRecord>> matchPrefix(
    StorageAdapter storage,
    String prefix, {
    bool includePositions = false,
  }) async {
    if (prefix.isEmpty) return const [];
    return storage.getPostingsForPrefix(prefix, includePositions: includePositions);
  }
}
