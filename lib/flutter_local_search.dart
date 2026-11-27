/// An embedded, offline-first full-text search engine for Flutter and Dart with
/// BM25F ranking, typo-tolerant fuzzy search, prefix autocomplete, phrase queries,
/// boolean Query DSL, faceted filtering, SQLite WAL persistence, and background
/// Isolate execution—no backend required.
library;

export 'src/analyzer/standard_analyzer.dart';
export 'src/analyzer/text_analyzer.dart';
export 'src/analyzer/token.dart';
export 'src/engine/isolate_worker.dart';
export 'src/engine/local_search_engine.dart';
export 'src/filter/facet_engine.dart';
export 'src/index/bm25f_scorer.dart';
export 'src/index/fuzzy_matcher.dart';
export 'src/index/highlighter.dart';
export 'src/index/inverted_index.dart';
export 'src/index/phrase_matcher.dart';
export 'src/index/prefix_matcher.dart';
export 'src/models/search_field.dart';
export 'src/models/search_filter.dart';
export 'src/models/search_options.dart';
export 'src/models/search_response.dart';
export 'src/query/query_parser.dart';
export 'src/query/search_query.dart';
export 'src/storage/memory_storage.dart';
export 'src/storage/sqlite_storage.dart';
export 'src/storage/storage_adapter.dart';
export 'src/storage/storage_records.dart';
export 'src/widgets/local_search_widgets.dart';
