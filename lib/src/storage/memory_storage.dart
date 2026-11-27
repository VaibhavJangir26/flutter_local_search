import '../models/search_filter.dart';
import 'storage_adapter.dart';
import 'storage_records.dart';

/// Pure in-memory implementation of [StorageAdapter] for ultra-fast unit testing
/// and ephemeral/session-based searches without SQLite overhead.
class MemoryStorage implements StorageAdapter {
  final Map<String, DocumentRecord> _documents = {};
  final Map<String, Map<String, PostingRecord>> _termPostings = {};
  final Map<String, Set<String>> _docTerms = {};
  final Map<String, List<FacetRecord>> _docFacets = {};
  final Map<String, String> _meta = {};
  final Map<String, int> _fieldTotalLengths = {};
  bool _isOpen = false;

  /// Whether the memory storage is currently open.
  bool get isOpen => _isOpen;

  @override
  Future<void> open() async {
    _isOpen = true;
  }

  @override
  Future<void> close() async {
    _isOpen = false;
  }

  @override
  Future<void> clear() async {
    _documents.clear();
    _termPostings.clear();
    _docTerms.clear();
    _docFacets.clear();
    _meta.clear();
    _fieldTotalLengths.clear();
  }

  @override
  Future<void> saveMetadata(String key, String value) async {
    _meta[key] = value;
  }

  @override
  Future<String?> getMetadata(String key) async {
    return _meta[key];
  }

  @override
  Future<void> saveBatch({
    required List<DocumentRecord> documents,
    required List<PostingRecord> postings,
    required List<FacetRecord> facets,
  }) async {
    // 1. Remove old versions of incoming documents
    for (final doc in documents) {
      await deleteDocument(doc.docId);
    }

    // 2. Save documents and update running field length totals
    for (final doc in documents) {
      _documents[doc.docId] = doc;
      for (final entry in doc.fieldLengths.entries) {
        _fieldTotalLengths[entry.key] = (_fieldTotalLengths[entry.key] ?? 0) + entry.value;
      }
    }

    // 3. Save postings
    for (final posting in postings) {
      final key = '${posting.docId}\u0000${posting.field}';
      _termPostings.putIfAbsent(posting.term, () => {})[key] = posting;
      _docTerms.putIfAbsent(posting.docId, () => {}).add(posting.term);
    }

    // 4. Save facets
    for (final facet in facets) {
      _docFacets.putIfAbsent(facet.docId, () => []).add(facet);
    }
  }

  @override
  Future<void> deleteDocument(String docId) async {
    final existing = _documents.remove(docId);
    if (existing != null) {
      for (final entry in existing.fieldLengths.entries) {
        final next = (_fieldTotalLengths[entry.key] ?? 0) - entry.value;
        if (next <= 0) {
          _fieldTotalLengths.remove(entry.key);
        } else {
          _fieldTotalLengths[entry.key] = next;
        }
      }
    }

    // Remove postings associated with docId in O(terms_in_doc)
    final termsForDoc = _docTerms.remove(docId);
    if (termsForDoc != null) {
      for (final term in termsForDoc) {
        final postingsMap = _termPostings[term];
        if (postingsMap != null) {
          postingsMap.removeWhere((_, p) => p.docId == docId);
          if (postingsMap.isEmpty) {
            _termPostings.remove(term);
          }
        }
      }
    }

    // Remove facets
    _docFacets.remove(docId);
  }

  @override
  Future<DocumentRecord?> getDocument(String docId) async {
    return _documents[docId];
  }

  @override
  Future<List<DocumentRecord>> getDocuments(List<String> docIds) async {
    final results = <DocumentRecord>[];
    for (final id in docIds) {
      final doc = _documents[id];
      if (doc != null) {
        results.add(doc);
      }
    }
    return results;
  }

  @override
  Future<Map<String, Map<String, int>>> getDocumentFieldLengths(List<String> docIds) async {
    final result = <String, Map<String, int>>{};
    for (final id in docIds) {
      final doc = _documents[id];
      if (doc != null) {
        result[id] = doc.fieldLengths;
      }
    }
    return result;
  }

  @override
  Future<List<PostingRecord>> getPostingsForTerm(
    String term, {
    bool includePositions = true,
  }) async {
    return _termPostings[term]?.values.toList() ?? const [];
  }

  @override
  Future<List<PostingRecord>> getPostingsForTerms(
    List<String> terms, {
    bool includePositions = true,
  }) async {
    final results = <PostingRecord>[];
    for (final t in terms) {
      final postings = _termPostings[t];
      if (postings != null) {
        results.addAll(postings.values);
      }
    }
    return results;
  }

  @override
  Future<List<PostingRecord>> getPostingsForPrefix(
    String prefix, {
    bool includePositions = true,
  }) async {
    if (prefix.isEmpty) return const [];
    final results = <PostingRecord>[];
    for (final entry in _termPostings.entries) {
      if (entry.key.startsWith(prefix)) {
        results.addAll(entry.value.values);
      }
    }
    return results;
  }

  @override
  Future<List<PostingRecord>> getPostingsForLengthWindow(
    int minLength,
    int maxLength, {
    bool includePositions = true,
  }) async {
    final results = <PostingRecord>[];
    for (final entry in _termPostings.entries) {
      final len = entry.key.length;
      if (len >= minLength && len <= maxLength) {
        results.addAll(entry.value.values);
      }
    }
    return results;
  }

  @override
  Future<Map<String, int>> getDocFrequencies(List<String> terms) async {
    final map = <String, int>{};
    for (final t in terms) {
      final postings = _termPostings[t];
      if (postings == null) {
        map[t] = 0;
      } else {
        map[t] = postings.values.map((p) => p.docId).toSet().length;
      }
    }
    return map;
  }

  @override
  Future<int> getDocumentCount() async => _documents.length;

  @override
  Future<Map<String, int>> getFieldTotalLengths() async {
    return Map<String, int>.from(_fieldTotalLengths);
  }

  @override
  Future<Set<String>> filterDocIds(List<SearchFilter> filters) async {
    if (filters.isEmpty) {
      return _documents.keys.toSet();
    }

    final matched = <String>{};
    for (final entry in _documents.entries) {
      final docId = entry.key;
      final structured = entry.value.structuredData;
      bool allMatch = true;

      for (final filter in filters) {
        final val = structured[filter.field];
        if (!filter.matches(val)) {
          allMatch = false;
          break;
        }
      }

      if (allMatch) {
        matched.add(docId);
      }
    }

    return matched;
  }

  @override
  Future<Map<String, Map<String, int>>> aggregateFacets({
    required List<String> facetFields,
    Set<String>? docIdFilter,
  }) async {
    final result = <String, Map<String, int>>{};
    for (final field in facetFields) {
      result[field] = <String, int>{};
    }
    if (facetFields.isEmpty) return result;

    final fieldSet = facetFields.toSet();
    final targetDocs = docIdFilter ?? _docFacets.keys;

    for (final docId in targetDocs) {
      final docFacets = _docFacets[docId];
      if (docFacets == null) continue;
      for (final facet in docFacets) {
        if (!fieldSet.contains(facet.field)) continue;
        final counts = result[facet.field]!;
        counts[facet.value] = (counts[facet.value] ?? 0) + 1;
      }
    }

    return result;
  }
}
