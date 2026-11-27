## 0.1.0

* Initial production release of `flutter_local_search`.
* **Typed & Zero-Boilerplate Indexing**: Generic `FlutterLocalSearch<T>` with field weights, plus `fromJsonList` and `strings` factories.
* **BM25F Relevance Ranking**: Field-weighted Okapi BM25F scoring with persisted field weights and document-length normalization.
* **Typo-Tolerant Fuzzy Search**: Restricted Damerau-Levenshtein matching with term-length window pruning and relevance decay.
* **Prefix Autocomplete & Exact Phrase Search**: B-tree range prefix lookups and positional token proximity verification (`positions_blob`).
* **Query DSL & Boolean Parser**: Fluent `SearchQuery` builder and parser supporting quoted phrases, `AND`, `OR`, `NOT`, and `-term` exclusions.
* **Structured Filtering & Faceting**: SQLite JSON1 filters (`equals`, `inList`, `range`, `gt`, `gte`, `lt`, `lte`, `boolean`) with live facet counts.
* **Persistent SQLite WAL & Background Isolate Worker**: Non-blocking indexing and querying on iOS, Android, and desktop.
* **Built-in Empty State Widgets**: `LocalSearchEmptyState` and `LocalSearchResultBuilder<T>` plus `SearchResponse.isEmpty` helpers.
