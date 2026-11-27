// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../analyzer/standard_analyzer.dart';
import '../analyzer/text_analyzer.dart';
import '../index/bm25f_scorer.dart';
import '../index/highlighter.dart';
import '../index/inverted_index.dart';
import '../models/search_field.dart';
import '../models/search_filter.dart';
import '../models/search_options.dart';
import '../models/search_response.dart';
import '../query/query_parser.dart';
import '../query/search_query.dart';
import '../storage/sqlite_storage.dart';
import '../storage/storage_adapter.dart';
import 'isolate_worker.dart';
import 'search_core.dart';

/// Deterministic FNV-1a + DJB2 hybrid ID generator so string indexes keep
/// identical document IDs across app restarts and isolates.
String _deterministicStringId(String input) {
  int fnv = 0x811c9dc5;
  int djb2 = 5381;
  for (int i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    fnv ^= c;
    fnv = (fnv * 0x01000193) & 0xFFFFFFFF;
    djb2 = ((djb2 << 5) + djb2 + c) & 0xFFFFFFFF;
  }
  return '${fnv.toRadixString(16)}_${djb2.toRadixString(16)}_${input.length}';
}

/// The primary full-text and faceted search orchestrator for generic type [T].
class FlutterLocalSearch<T> {
  final String indexName;
  final String Function(T item) id;
  final Map<String, SearchField> Function(T item) fields;
  final Map<String, dynamic> Function(T item) toJson;
  final T Function(Map<String, dynamic> json) fromJson;

  /// Whether heavy indexing and search operations run on a background [IsolateWorker]
  /// when backed by a persistent SQLite WAL database file.
  final bool useIsolate;

  StorageAdapter? _storage;
  final TextAnalyzer _analyzer;
  final BM25FScorer _scorer;
  final String? _customDbPath;

  SearchCoreExecutor? _directExecutor;
  IsolateWorker? _isolateWorker;
  bool _isInitialized = false;

  FlutterLocalSearch({
    required this.indexName,
    required this.id,
    required this.fields,
    required this.toJson,
    required this.fromJson,
    StorageAdapter? storage,
    TextAnalyzer? analyzer,
    BM25FScorer? scorer,
    String? customDbPath,
    this.useIsolate = true,
  })  : _storage = storage,
        _analyzer = analyzer ?? const StandardAnalyzer(),
        _scorer = scorer ?? const BM25FScorer(),
        _customDbPath = customDbPath;

  /// Convenience factory for indexing dynamic JSON maps directly.
  /// Automatically indexes string keys as full-text fields, and numbers/booleans as filterable fields.
  static FlutterLocalSearch<Map<String, dynamic>> fromJsonList({
    required String indexName,
    String Function(Map<String, dynamic> map)? id,
    List<String>? facetFields,
    Map<String, double>? fieldWeights,
    StorageAdapter? storage,
    String? customDbPath,
    bool useIsolate = true,
  }) {
    final facetsSet = (facetFields ?? const []).toSet();
    final weights = fieldWeights ?? const {};

    return FlutterLocalSearch<Map<String, dynamic>>(
      indexName: indexName,
      id: id ??
          (map) {
            final possibleId = map['id'] ?? map['_id'] ?? map['uuid'];
            if (possibleId != null) return possibleId.toString();
            return _deterministicStringId(jsonEncode(map));
          },
      fields: (map) {
        final fieldMap = <String, SearchField>{};
        for (final entry in map.entries) {
          final key = entry.key;
          final val = entry.value;
          final weight = weights[key] ?? 1.0;

          if (val is String) {
            if (facetsSet.contains(key)) {
              fieldMap[key] = SearchField.facet(val, weight: weight);
            } else {
              fieldMap[key] = SearchField.text(val, weight: weight);
            }
          } else if (val is num) {
            fieldMap[key] = SearchField.number(val);
          } else if (val is bool) {
            fieldMap[key] = SearchField.boolean(val);
          }
        }
        return fieldMap;
      },
      toJson: (map) => map,
      fromJson: (json) => json,
      storage: storage,
      customDbPath: customDbPath,
      useIsolate: useIsolate,
    );
  }

  /// Convenience factory for simple lists of strings (e.g., tags, names, queries).
  static FlutterLocalSearch<String> strings({
    required String indexName,
    StorageAdapter? storage,
    String? customDbPath,
    bool useIsolate = true,
  }) {
    return FlutterLocalSearch<String>(
      indexName: indexName,
      id: _deterministicStringId,
      fields: (s) => {'value': SearchField.text(s)},
      toJson: (s) => {'value': s},
      fromJson: (json) => json['value'] as String,
      storage: storage,
      customDbPath: customDbPath,
      useIsolate: useIsolate,
    );
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('FlutterLocalSearch must be initialized. Call initialize() first.');
    }
  }

  /// Exposes the direct [StorageAdapter] when running on the main isolate.
  /// Throws if running via [IsolateWorker] or before initialization.
  StorageAdapter get storage {
    _ensureInitialized();
    final s = _storage;
    if (s == null) {
      throw StateError(
        'Storage is managed inside the background IsolateWorker when useIsolate is enabled.',
      );
    }
    return s;
  }

  /// Initializes the storage engine or background [IsolateWorker].
  /// If no [storage] was passed, resolves the application documents directory
  /// and opens an optimized SQLite WAL database.
  Future<void> initialize() async {
    if (_isInitialized) return;

    String? fileDbPath;

    if (_storage == null) {
      if (_customDbPath != null) {
        fileDbPath = _customDbPath;
      } else {
        try {
          final dir = await getApplicationDocumentsDirectory();
          fileDbPath = p.join(dir.path, '$indexName.db');
        } catch (_) {
          // Fallback when path_provider is unavailable (pure Dart VM / CLI tests)
          fileDbPath = '$indexName.db';
        }
      }

      if (useIsolate) {
        _isolateWorker = IsolateWorker(
          dbPath: fileDbPath,
          analyzer: _analyzer,
          scorer: _scorer,
        );
        await _isolateWorker!.start();
        _isInitialized = true;
        return;
      }

      _storage = SqliteStorage(dbPath: fileDbPath);
    } else if (_storage is SqliteStorage &&
        (_storage as SqliteStorage).dbPath != null &&
        useIsolate) {
      fileDbPath = (_storage as SqliteStorage).dbPath!;
      _isolateWorker = IsolateWorker(
        dbPath: fileDbPath,
        analyzer: _analyzer,
        scorer: _scorer,
      );
      await _isolateWorker!.start();
      _isInitialized = true;
      return;
    }

    await _storage!.open();
    _directExecutor = SearchCoreExecutor(
      storage: _storage!,
      analyzer: _analyzer,
      scorer: _scorer,
    );
    _isInitialized = true;
  }

  /// Indexes a collection of items in a single atomic transaction.
  Future<void> indexAll(List<T> items) async {
    _ensureInitialized();
    if (items.isEmpty) return;

    final inputs = <RawDocumentInput>[];
    for (final item in items) {
      inputs.add(RawDocumentInput(
        docId: id(item),
        payloadJson: jsonEncode(toJson(item)),
        fields: fields(item),
      ));
    }

    if (_isolateWorker != null) {
      await _isolateWorker!.indexBatch(inputs);
    } else {
      await _directExecutor!.indexBatch(inputs);
    }
  }

  /// Inserts or updates an individual item in the search index.
  Future<void> upsert(T item) async {
    await indexAll([item]);
  }

  /// Removes an item by its unique identifier.
  Future<void> remove(String docId) async {
    _ensureInitialized();
    if (_isolateWorker != null) {
      await _isolateWorker!.remove(docId);
    } else {
      await _directExecutor!.remove(docId);
    }
  }

  /// Clears the entire index.
  Future<void> clear() async {
    _ensureInitialized();
    if (_isolateWorker != null) {
      await _isolateWorker!.clear();
    } else {
      await _directExecutor!.clear();
    }
  }

  /// Closes the underlying storage engine and stops any background isolate.
  Future<void> close() async {
    if (!_isInitialized) return;
    if (_isolateWorker != null) {
      await _isolateWorker!.stop();
      _isolateWorker = null;
    }
    if (_storage != null) {
      await _storage!.close();
    }
    _directExecutor = null;
    _isInitialized = false;
  }

  /// Executes a full-text, fuzzy, prefix, phrase, boolean, and faceted search query.
  Future<SearchResponse<T>> search(
    String query, {
    SearchOptions options = const SearchOptions(),
    List<SearchFilter> filters = const [],
    List<String> facets = const [],
  }) async {
    final parsed = QueryParser.parse(query).whereAll(filters);
    return searchQuery(
      parsed,
      rawQueryText: query,
      options: options,
      facets: facets,
    );
  }

  /// Executes a structured [SearchQuery] built via the fluent Query DSL.
  Future<SearchResponse<T>> searchQuery(
    SearchQuery query, {
    String rawQueryText = '',
    SearchOptions options = const SearchOptions(),
    List<String> facets = const [],
  }) async {
    _ensureInitialized();

    final request = RawSearchRequest(
      rawQueryText: rawQueryText,
      query: query,
      options: options,
      facets: facets,
    );

    final rawResult = _isolateWorker != null
        ? await _isolateWorker!.search(request)
        : await _directExecutor!.executeSearch(request);

    final highlighter = options.highlight
        ? Highlighter(
            preTag: options.highlightPreTag,
            postTag: options.highlightPostTag,
          )
        : null;

    final hits = <SearchHit<T>>[];
    for (final rawHit in rawResult.hits) {
      final json = jsonDecode(rawHit.payloadJson) as Map<String, dynamic>;
      final item = fromJson(json);

      final highlights = <String, List<String>>{};
      if (highlighter != null && rawResult.matchedTerms.isNotEmpty) {
        final itemFields = fields(item);
        for (final f in itemFields.entries) {
          if (f.value.isTextual) {
            final text = f.value.value.toString();
            final snippets = highlighter.highlight(text, rawResult.matchedTerms);
            if (snippets.isNotEmpty) {
              highlights[f.key] = snippets;
            }
          }
        }
      }

      hits.add(SearchHit<T>(
        item: item,
        id: rawHit.docId,
        score: rawHit.score,
        highlights: highlights,
      ));
    }

    return SearchResponse<T>(
      query: rawResult.queryText,
      hits: hits,
      totalHits: rawResult.totalHits,
      facetCounts: rawResult.facetCounts,
      queryTimeMs: rawResult.queryTimeMs,
    );
  }
}
