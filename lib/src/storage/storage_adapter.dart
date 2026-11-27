import '../models/search_filter.dart';
import 'storage_records.dart';

/// Abstract persistence contract for storing and querying documents, postings, and facets.
abstract class StorageAdapter {
  /// Opens the storage backend, creates tables/indexes, and prepares connection.
  Future<void> open();

  /// Closes the storage backend safely.
  Future<void> close();

  /// Wipes all documents, terms, postings, facets, and metadata from the index.
  Future<void> clear();

  /// Saves a key-value metadata entry (e.g., field weights or schema version).
  Future<void> saveMetadata(String key, String value);

  /// Retrieves a metadata value by key.
  Future<String?> getMetadata(String key);

  /// Saves a batch of documents, postings, and facets inside a single atomic transaction.
  Future<void> saveBatch({
    required List<DocumentRecord> documents,
    required List<PostingRecord> postings,
    required List<FacetRecord> facets,
  });

  /// Deletes a document by ID and removes its corresponding postings and facets.
  Future<void> deleteDocument(String docId);

  /// Retrieves a document by its ID.
  Future<DocumentRecord?> getDocument(String docId);

  /// Retrieves multiple documents by their IDs in batch.
  Future<List<DocumentRecord>> getDocuments(List<String> docIds);

  /// Retrieves only field token lengths for the given [docIds] (avoids fetching payloads).
  Future<Map<String, Map<String, int>>> getDocumentFieldLengths(List<String> docIds);

  /// Retrieves postings for a specific normalized term.
  Future<List<PostingRecord>> getPostingsForTerm(String term, {bool includePositions = true});

  /// Retrieves postings for multiple normalized terms.
  Future<List<PostingRecord>> getPostingsForTerms(
    List<String> terms, {
    bool includePositions = true,
  });

  /// Retrieves postings for terms matching a prefix.
  Future<List<PostingRecord>> getPostingsForPrefix(
    String prefix, {
    bool includePositions = true,
  });

  /// Retrieves postings for terms within a length window (for fuzzy search optimization).
  Future<List<PostingRecord>> getPostingsForLengthWindow(
    int minLength,
    int maxLength, {
    bool includePositions = true,
  });

  /// Retrieves document frequency (number of unique documents containing term) for given terms.
  Future<Map<String, int>> getDocFrequencies(List<String> terms);

  /// Total count of indexed documents.
  Future<int> getDocumentCount();

  /// Total token length per field across all documents (used for BM25F average field length).
  Future<Map<String, int>> getFieldTotalLengths();

  /// Evaluates structured filters and returns IDs of all documents matching the conditions.
  Future<Set<String>> filterDocIds(List<SearchFilter> filters);

  /// Aggregates facet counts for the given facet fields, optionally restricted to a set of matching doc IDs.
  Future<Map<String, Map<String, int>>> aggregateFacets({
    required List<String> facetFields,
    Set<String>? docIdFilter,
  });
}
