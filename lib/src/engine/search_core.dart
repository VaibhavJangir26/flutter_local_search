import 'dart:convert';
import '../analyzer/text_analyzer.dart';
import '../filter/facet_engine.dart';
import '../index/bm25f_scorer.dart';
import '../index/fuzzy_matcher.dart';
import '../index/inverted_index.dart';
import '../index/phrase_matcher.dart';
import '../index/prefix_matcher.dart';
import '../models/search_options.dart';
import '../query/search_query.dart';
import '../storage/storage_adapter.dart';
import '../storage/storage_records.dart';

/// Serializable search request passed into [SearchCoreExecutor] or [IsolateWorker].
class RawSearchRequest {
  final String rawQueryText;
  final SearchQuery query;
  final SearchOptions options;
  final List<String> facets;

  const RawSearchRequest({
    required this.rawQueryText,
    required this.query,
    required this.options,
    required this.facets,
  });
}

/// Serializable search hit returned by [SearchCoreExecutor].
class RawSearchHit {
  final String docId;
  final String payloadJson;
  final double score;

  const RawSearchHit({
    required this.docId,
    required this.payloadJson,
    required this.score,
  });
}

/// Serializable search result returned by [SearchCoreExecutor].
class RawSearchResult {
  final String queryText;
  final List<RawSearchHit> hits;
  final int totalHits;
  final Map<String, Map<String, int>> facetCounts;
  final Set<String> matchedTerms;
  final int queryTimeMs;

  const RawSearchResult({
    required this.queryText,
    required this.hits,
    required this.totalHits,
    required this.facetCounts,
    required this.matchedTerms,
    required this.queryTimeMs,
  });
}

class _NodeEvaluation {
  final Map<String, double> scores;
  final Set<String> matchedTerms;

  const _NodeEvaluation(this.scores, this.matchedTerms);
}

/// Shared, storage-agnostic indexing and query execution engine.
/// Used identically on the main isolate (for memory/test adapters) and inside
/// the background [IsolateWorker] (for persistent SQLite WAL files).
class SearchCoreExecutor {
  static const String _metaFieldWeightsKey = '_internal_field_weights';

  final StorageAdapter storage;
  final TextAnalyzer analyzer;
  final BM25FScorer scorer;
  final PrefixMatcher prefixMatcher;
  final PhraseMatcher phraseMatcher;
  final FacetEngine facetEngine;

  Map<String, double>? _cachedFieldWeights;

  SearchCoreExecutor({
    required this.storage,
    required this.analyzer,
    required this.scorer,
    this.prefixMatcher = const PrefixMatcher(),
    this.phraseMatcher = const PhraseMatcher(),
    this.facetEngine = const FacetEngine(),
  });

  /// Indexes a batch of [RawDocumentInput]s atomically and persists field weights.
  Future<void> indexBatch(List<RawDocumentInput> inputs) async {
    if (inputs.isEmpty) return;

    final builder = InvertedIndexBuilder(analyzer);
    final built = builder.buildBatch(inputs);

    await storage.saveBatch(
      documents: built.documents,
      postings: built.postings,
      facets: built.facets,
    );

    if (built.fieldWeights.isNotEmpty) {
      final existing = await _loadFieldWeights();
      final merged = Map<String, double>.from(existing)..addAll(built.fieldWeights);
      _cachedFieldWeights = merged;
      await storage.saveMetadata(_metaFieldWeightsKey, jsonEncode(merged));
    }
  }

  /// Removes a single document by ID.
  Future<void> remove(String docId) => storage.deleteDocument(docId);

  /// Clears all documents, index terms, postings, and cached field weights.
  Future<void> clear() async {
    _cachedFieldWeights = null;
    await storage.clear();
  }

  Future<Map<String, double>> _loadFieldWeights() async {
    if (_cachedFieldWeights != null) return _cachedFieldWeights!;
    final raw = await storage.getMetadata(_metaFieldWeightsKey);
    if (raw == null || raw.isEmpty) {
      _cachedFieldWeights = {};
      return _cachedFieldWeights!;
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _cachedFieldWeights = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    return _cachedFieldWeights!;
  }

  /// Executes a structured [RawSearchRequest] and returns ranked raw hits + facets.
  Future<RawSearchResult> executeSearch(RawSearchRequest request) async {
    final stopwatch = Stopwatch()..start();

    final filters = request.query.filters;
    final matchingFilterIds = await facetEngine.evaluateFilters(storage, filters);
    final totalDocs = await storage.getDocumentCount();

    if (totalDocs == 0 || (filters.isNotEmpty && matchingFilterIds.isEmpty)) {
      stopwatch.stop();
      return RawSearchResult(
        queryText: request.rawQueryText,
        hits: const [],
        totalHits: 0,
        facetCounts: {for (final f in request.facets) f: const {}},
        matchedTerms: const {},
        queryTimeMs: stopwatch.elapsedMilliseconds,
      );
    }

    final fieldWeights = await _loadFieldWeights();
    final totalFieldLengths = await storage.getFieldTotalLengths();
    final avgFieldLengths = <String, double>{
      for (final entry in totalFieldLengths.entries)
        entry.key: totalDocs > 0 ? entry.value / totalDocs : 1.0,
    };

    final root = request.query.root;
    late Map<String, double> docScores;
    final matchedTerms = <String>{};

    if (root == null) {
      // No text query: return all documents matching filters
      docScores = {for (final id in matchingFilterIds) id: 1.0};
    } else {
      final evaluation = await _evaluateNode(
        node: root,
        options: request.options,
        allowedDocIds: filters.isNotEmpty ? matchingFilterIds : null,
        allFilterMatchedIds: matchingFilterIds,
        totalDocs: totalDocs,
        avgFieldLengths: avgFieldLengths,
        fieldWeights: fieldWeights,
      );
      docScores = evaluation.scores;
      matchedTerms.addAll(evaluation.matchedTerms);
    }

    // Apply structured filter boundary
    if (filters.isNotEmpty) {
      docScores.removeWhere((docId, _) => !matchingFilterIds.contains(docId));
    }

    // Sort descending by BM25F score
    final sortedEntries = docScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalHits = sortedEntries.length;

    // Paginate
    final pagedEntries = sortedEntries
        .skip(request.options.offset)
        .take(request.options.limit)
        .toList();

    final pagedIds = pagedEntries.map((e) => e.key).toList();
    final docs = await storage.getDocuments(pagedIds);
    final docMap = {for (final d in docs) d.docId: d};

    final hits = <RawSearchHit>[];
    for (final entry in pagedEntries) {
      final doc = docMap[entry.key];
      if (doc == null) continue;
      hits.add(RawSearchHit(
        docId: entry.key,
        payloadJson: doc.payloadJson,
        score: entry.value,
      ));
    }

    // Aggregate facets across matching documents
    Map<String, Map<String, int>> facetCounts = const {};
    if (request.facets.isNotEmpty) {
      facetCounts = await facetEngine.aggregate(
        storage,
        request.facets,
        matchingDocIds: docScores.keys.toSet(),
      );
    }

    stopwatch.stop();

    return RawSearchResult(
      queryText: request.rawQueryText,
      hits: hits,
      totalHits: totalHits,
      facetCounts: facetCounts,
      matchedTerms: matchedTerms,
      queryTimeMs: stopwatch.elapsedMilliseconds,
    );
  }

  Future<_NodeEvaluation> _evaluateNode({
    required QueryNode node,
    required SearchOptions options,
    required Set<String>? allowedDocIds,
    required Set<String> allFilterMatchedIds,
    required int totalDocs,
    required Map<String, double> avgFieldLengths,
    required Map<String, double> fieldWeights,
  }) async {
    switch (node) {
      case MatchQueryNode(:final text):
        return _evaluateMatch(
          text: text,
          options: options,
          allowedDocIds: allowedDocIds,
          totalDocs: totalDocs,
          avgFieldLengths: avgFieldLengths,
          fieldWeights: fieldWeights,
        );

      case PhraseQueryNode(:final phrase, :final slop):
        return _evaluatePhrase(
          phrase: phrase,
          slop: slop,
          allowedDocIds: allowedDocIds,
          totalDocs: totalDocs,
          avgFieldLengths: avgFieldLengths,
          fieldWeights: fieldWeights,
        );

      case OrQueryNode(:final children):
        final combinedScores = <String, double>{};
        final combinedTerms = <String>{};
        for (final child in children) {
          final res = await _evaluateNode(
            node: child,
            options: options,
            allowedDocIds: allowedDocIds,
            allFilterMatchedIds: allFilterMatchedIds,
            totalDocs: totalDocs,
            avgFieldLengths: avgFieldLengths,
            fieldWeights: fieldWeights,
          );
          combinedTerms.addAll(res.matchedTerms);
          for (final entry in res.scores.entries) {
            combinedScores[entry.key] = (combinedScores[entry.key] ?? 0.0) + entry.value;
          }
        }
        return _NodeEvaluation(combinedScores, combinedTerms);

      case AndQueryNode(:final children):
        final positiveNodes = children.where((c) => c is! NotQueryNode).toList();
        final notNodes = children.whereType<NotQueryNode>().toList();

        Map<String, double>? currentScores;
        final combinedTerms = <String>{};

        if (positiveNodes.isEmpty) {
          currentScores = {for (final id in allFilterMatchedIds) id: 1.0};
        } else {
          for (final child in positiveNodes) {
            final res = await _evaluateNode(
              node: child,
              options: options,
              allowedDocIds: currentScores == null
                  ? allowedDocIds
                  : currentScores.keys.toSet(),
              allFilterMatchedIds: allFilterMatchedIds,
              totalDocs: totalDocs,
              avgFieldLengths: avgFieldLengths,
              fieldWeights: fieldWeights,
            );
            combinedTerms.addAll(res.matchedTerms);

            if (currentScores == null) {
              currentScores = Map<String, double>.from(res.scores);
            } else {
              // Intersect and sum scores
              currentScores.removeWhere((docId, _) => !res.scores.containsKey(docId));
              for (final docId in currentScores.keys.toList()) {
                currentScores[docId] = currentScores[docId]! + res.scores[docId]!;
              }
            }

            if (currentScores.isEmpty) {
              return const _NodeEvaluation({}, {});
            }
          }
        }

        final resolvedScores = currentScores ?? <String, double>{};

        // Apply NOT exclusions
        for (final notNode in notNodes) {
          final excludedRes = await _evaluateNode(
            node: notNode.child,
            options: options,
            allowedDocIds: resolvedScores.keys.toSet(),
            allFilterMatchedIds: allFilterMatchedIds,
            totalDocs: totalDocs,
            avgFieldLengths: avgFieldLengths,
            fieldWeights: fieldWeights,
          );
          for (final excludedId in excludedRes.scores.keys) {
            resolvedScores.remove(excludedId);
          }
        }

        return _NodeEvaluation(resolvedScores, combinedTerms);

      case NotQueryNode(:final child):
        final excludedRes = await _evaluateNode(
          node: child,
          options: options,
          allowedDocIds: allowedDocIds,
          allFilterMatchedIds: allFilterMatchedIds,
          totalDocs: totalDocs,
          avgFieldLengths: avgFieldLengths,
          fieldWeights: fieldWeights,
        );
        final surviving = <String, double>{};
        for (final id in allFilterMatchedIds) {
          if (!excludedRes.scores.containsKey(id)) {
            surviving[id] = 1.0;
          }
        }
        return _NodeEvaluation(surviving, const {});
    }
  }

  Future<_NodeEvaluation> _evaluateMatch({
    required String text,
    required SearchOptions options,
    required Set<String>? allowedDocIds,
    required int totalDocs,
    required Map<String, double> avgFieldLengths,
    required Map<String, double> fieldWeights,
  }) async {
    final tokens = analyzer.analyze(text);
    final queryTerms = tokens.map((t) => t.term).toSet().toList();
    if (queryTerms.isEmpty) {
      return const _NodeEvaluation({}, {});
    }

    final matchedPostings = <PostingRecord>[];
    final termMultipliers = <String, double>{};

    void recordMultiplier(String term, double multiplier) {
      final existing = termMultipliers[term];
      if (existing == null || multiplier > existing) {
        termMultipliers[term] = multiplier;
      }
    }

    // 1. Exact matches (weight = 1.0)
    final exactPostings = await storage.getPostingsForTerms(
      queryTerms,
      includePositions: false,
    );
    for (final p in exactPostings) {
      matchedPostings.add(p);
      recordMultiplier(p.term, 1.0);
    }

    // 2. Prefix matches (weight = 0.85)
    if (options.prefix) {
      for (final qTerm in queryTerms) {
        final prefixPostings = await prefixMatcher.matchPrefix(
          storage,
          qTerm,
          includePositions: false,
        );
        for (final p in prefixPostings) {
          if (p.term == qTerm) continue; // Already scored as exact
          matchedPostings.add(p);
          recordMultiplier(p.term, PrefixMatcher.defaultPrefixWeight);
        }
      }
    }

    // 3. Fuzzy matches (Damerau-Levenshtein with length window pruning)
    if (options.fuzzy) {
      for (final qTerm in queryTerms) {
        final minLen = (qTerm.length - options.maxEditDistance).clamp(1, 256);
        final maxLen = qTerm.length + options.maxEditDistance;
        final windowPostings = await storage.getPostingsForLengthWindow(
          minLen,
          maxLen,
          includePositions: false,
        );

        for (final p in windowPostings) {
          if (p.term == qTerm) continue;
          final dist = FuzzyMatcher.matchDistance(
            qTerm,
            p.term,
            maxDistance: options.maxEditDistance,
          );
          if (dist != null) {
            matchedPostings.add(p);
            recordMultiplier(p.term, FuzzyMatcher.weightForDistance(dist));
          }
        }
      }
    }

    if (matchedPostings.isEmpty) {
      return const _NodeEvaluation({}, {});
    }

    final filteredPostings = allowedDocIds != null
        ? matchedPostings.where((p) => allowedDocIds.contains(p.docId)).toList()
        : matchedPostings;

    if (filteredPostings.isEmpty) {
      return const _NodeEvaluation({}, {});
    }

    // Deduplicate postings per (term, docId, field) in case prefix & fuzzy hit the same term
    final seenPostings = <String>{};
    final dedupedPostings = <PostingRecord>[];
    for (final p in filteredPostings) {
      final key = '${p.term}\u0000${p.docId}\u0000${p.field}';
      if (seenPostings.add(key)) {
        dedupedPostings.add(p);
      }
    }

    final candidateIds = dedupedPostings.map((p) => p.docId).toSet().toList();
    final docLengths = await storage.getDocumentFieldLengths(candidateIds);

    final matchedTerms = termMultipliers.keys.toList();
    final docFrequencies = await storage.getDocFrequencies(matchedTerms);

    final scores = scorer.scoreDocuments(
      queryTerms: matchedTerms,
      postings: dedupedPostings,
      docLengths: docLengths,
      avgFieldLengths: avgFieldLengths,
      fieldWeights: fieldWeights,
      docFrequencies: docFrequencies,
      totalDocs: totalDocs,
      termMultipliers: termMultipliers,
    );

    return _NodeEvaluation(scores, termMultipliers.keys.toSet());
  }

  Future<_NodeEvaluation> _evaluatePhrase({
    required String phrase,
    required int slop,
    required Set<String>? allowedDocIds,
    required int totalDocs,
    required Map<String, double> avgFieldLengths,
    required Map<String, double> fieldWeights,
  }) async {
    final tokens = analyzer.analyze(phrase);
    final orderedTerms = tokens.map((t) => t.term).toList();
    if (orderedTerms.isEmpty) {
      return const _NodeEvaluation({}, {});
    }

    final uniqueTerms = orderedTerms.toSet().toList();
    final postings = await storage.getPostingsForTerms(uniqueTerms);

    final filteredPostings = allowedDocIds != null
        ? postings.where((p) => allowedDocIds.contains(p.docId)).toList()
        : postings;

    final matchedDocIds = phraseMatcher.matchPhraseDocIds(
      phraseTerms: orderedTerms,
      postings: filteredPostings,
      slop: slop,
    );

    if (matchedDocIds.isEmpty) {
      return const _NodeEvaluation({}, {});
    }

    final phrasePostings = filteredPostings
        .where((p) => matchedDocIds.contains(p.docId))
        .toList();

    final docLengths = await storage.getDocumentFieldLengths(matchedDocIds.toList());

    final docFrequencies = await storage.getDocFrequencies(uniqueTerms);

    final scores = scorer.scoreDocuments(
      queryTerms: uniqueTerms,
      postings: phrasePostings,
      docLengths: docLengths,
      avgFieldLengths: avgFieldLengths,
      fieldWeights: fieldWeights,
      docFrequencies: docFrequencies,
      totalDocs: totalDocs,
    );

    return _NodeEvaluation(scores, uniqueTerms.toSet());
  }
}
