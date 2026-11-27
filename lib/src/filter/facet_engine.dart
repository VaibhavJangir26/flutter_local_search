import '../models/search_filter.dart';
import '../storage/storage_adapter.dart';

/// Evaluates structured [SearchFilter] conditions and aggregates live facet counts.
class FacetEngine {
  const FacetEngine();

  /// Returns the set of document IDs matching all [filters].
  Future<Set<String>> evaluateFilters(
    StorageAdapter storage,
    List<SearchFilter> filters,
  ) {
    return storage.filterDocIds(filters);
  }

  /// Computes facet counts for [facetFields] over [matchingDocIds] (or entire index if null).
  Future<Map<String, Map<String, int>>> aggregate(
    StorageAdapter storage,
    List<String> facetFields, {
    Set<String>? matchingDocIds,
  }) {
    if (facetFields.isEmpty) return Future.value(const {});
    return storage.aggregateFacets(
      facetFields: facetFields,
      docIdFilter: matchingDocIds,
    );
  }
}
