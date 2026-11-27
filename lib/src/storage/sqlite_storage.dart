import 'dart:convert';
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart';
import '../models/search_filter.dart';
import 'storage_adapter.dart';
import 'storage_records.dart';

/// Persistent SQLite implementation of [StorageAdapter] running in WAL mode
/// with immediate transactions, foreign keys, O(1) index metadata caching,
/// chunked parameter batching, and SQL-level structured filtering.
class SqliteStorage implements StorageAdapter {
  static const String _metaTotalDocsKey = '_internal_total_docs';
  static const String _metaFieldTotalsKey = '_internal_field_totals';
  static const int _sqliteChunkSize = 450;

  final String? dbPath;
  Database? _db;

  SqliteStorage({this.dbPath});

  /// Factory for an in-memory SQLite database (useful for testing SQLite dialect without disk IO).
  factory SqliteStorage.inMemory() => SqliteStorage(dbPath: null);

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('SqliteStorage is not open. Call open() first.');
    }
    return database;
  }

  @override
  Future<void> open() async {
    if (_db != null) return;

    if (dbPath == null) {
      _db = sqlite3.openInMemory();
    } else {
      _db = sqlite3.open(dbPath!);
    }

    // High performance pragmas
    _db!.execute('PRAGMA journal_mode = WAL;');
    _db!.execute('PRAGMA synchronous = NORMAL;');
    _db!.execute('PRAGMA foreign_keys = ON;');

    _initSchema();
  }

  void _initSchema() {
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        doc_id TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        structured_json TEXT NOT NULL,
        field_lengths_json TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS terms (
        term_id INTEGER PRIMARY KEY AUTOINCREMENT,
        term TEXT NOT NULL UNIQUE,
        term_length INTEGER NOT NULL,
        doc_frequency INTEGER NOT NULL DEFAULT 0
      );

      CREATE INDEX IF NOT EXISTS idx_terms_term ON terms(term);
      CREATE INDEX IF NOT EXISTS idx_terms_len ON terms(term_length);

      CREATE TABLE IF NOT EXISTS postings (
        term_id INTEGER NOT NULL,
        doc_id TEXT NOT NULL,
        field TEXT NOT NULL,
        term_frequency INTEGER NOT NULL,
        positions_blob BLOB NOT NULL,
        PRIMARY KEY (term_id, doc_id, field),
        FOREIGN KEY (doc_id) REFERENCES documents(doc_id) ON DELETE CASCADE
      );

      CREATE INDEX IF NOT EXISTS idx_postings_doc ON postings(doc_id);

      CREATE TABLE IF NOT EXISTS facets (
        field TEXT NOT NULL,
        value TEXT NOT NULL,
        doc_id TEXT NOT NULL,
        PRIMARY KEY (field, value, doc_id),
        FOREIGN KEY (doc_id) REFERENCES documents(doc_id) ON DELETE CASCADE
      );

      CREATE INDEX IF NOT EXISTS idx_facets_lookup ON facets(field, value);

      CREATE TABLE IF NOT EXISTS index_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');
  }

  @override
  Future<void> close() async {
    _db?.close();
    _db = null;
  }

  @override
  Future<void> clear() async {
    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      db.execute('DELETE FROM postings;');
      db.execute('DELETE FROM facets;');
      db.execute('DELETE FROM terms;');
      db.execute('DELETE FROM documents;');
      db.execute('DELETE FROM index_meta;');
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<void> saveMetadata(String key, String value) async {
    db.execute(
      '''
      INSERT INTO index_meta(key, value) VALUES(?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value;
      ''',
      [key, value],
    );
  }

  @override
  Future<String?> getMetadata(String key) async {
    final rows = db.select('SELECT value FROM index_meta WHERE key = ?;', [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  int _readTotalDocsSync() {
    final rows = db.select('SELECT value FROM index_meta WHERE key = ?;', [_metaTotalDocsKey]);
    if (rows.isNotEmpty) {
      return int.tryParse(rows.first['value'] as String) ?? 0;
    }
    final countRows = db.select('SELECT COUNT(*) as count FROM documents;');
    return countRows.first['count'] as int;
  }

  Map<String, int> _readFieldTotalsSync() {
    final rows = db.select('SELECT value FROM index_meta WHERE key = ?;', [_metaFieldTotalsKey]);
    if (rows.isNotEmpty) {
      final decoded = jsonDecode(rows.first['value'] as String) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as int));
    }
    final docRows = db.select('SELECT field_lengths_json FROM documents;');
    final totals = <String, int>{};
    for (final row in docRows) {
      final json = jsonDecode(row['field_lengths_json'] as String) as Map<String, dynamic>;
      for (final entry in json.entries) {
        totals[entry.key] = (totals[entry.key] ?? 0) + (entry.value as int);
      }
    }
    return totals;
  }

  void _writeTotalsSync(int totalDocs, Map<String, int> fieldTotals) {
    final upsertMeta = db.prepare('''
      INSERT INTO index_meta(key, value) VALUES(?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value;
    ''');
    upsertMeta.execute([_metaTotalDocsKey, totalDocs.toString()]);
    upsertMeta.execute([_metaFieldTotalsKey, jsonEncode(fieldTotals)]);
    upsertMeta.close();
  }

  @override
  Future<void> saveBatch({
    required List<DocumentRecord> documents,
    required List<PostingRecord> postings,
    required List<FacetRecord> facets,
  }) async {
    if (documents.isEmpty && postings.isEmpty && facets.isEmpty) return;

    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      int totalDocs = _readTotalDocsSync();
      final fieldTotals = _readFieldTotalsSync();
      final affectedTermIds = <int>{};

      // 1. Collect old field lengths & term_ids for any documents being replaced
      if (documents.isNotEmpty) {
        final docIds = documents.map((d) => d.docId).toList();
        for (int i = 0; i < docIds.length; i += _sqliteChunkSize) {
          final chunk = docIds.sublist(
            i,
            (i + _sqliteChunkSize > docIds.length) ? docIds.length : i + _sqliteChunkSize,
          );
          final placeholders = List.filled(chunk.length, '?').join(',');

          // Subtract old field lengths and count removed docs
          final oldDocs = db.select(
            'SELECT doc_id, field_lengths_json FROM documents WHERE doc_id IN ($placeholders);',
            chunk,
          );
          for (final row in oldDocs) {
            totalDocs--;
            final oldLengths = jsonDecode(row['field_lengths_json'] as String) as Map<String, dynamic>;
            for (final entry in oldLengths.entries) {
              final next = (fieldTotals[entry.key] ?? 0) - (entry.value as int);
              if (next <= 0) {
                fieldTotals.remove(entry.key);
              } else {
                fieldTotals[entry.key] = next;
              }
            }
          }

          // Track old terms whose doc_frequency might decrease
          final oldTermRows = db.select(
            'SELECT DISTINCT term_id FROM postings WHERE doc_id IN ($placeholders);',
            chunk,
          );
          for (final row in oldTermRows) {
            affectedTermIds.add(row['term_id'] as int);
          }

          // Delete old documents (cascades to postings and facets)
          db.execute('DELETE FROM documents WHERE doc_id IN ($placeholders);', chunk);
        }
      }

      // 2. Insert new documents and update totals
      final insertDocStmt = db.prepare('''
        INSERT INTO documents(doc_id, payload_json, structured_json, field_lengths_json)
        VALUES(?, ?, ?, ?);
      ''');
      for (final doc in documents) {
        totalDocs++;
        for (final entry in doc.fieldLengths.entries) {
          fieldTotals[entry.key] = (fieldTotals[entry.key] ?? 0) + entry.value;
        }
        insertDocStmt.execute([
          doc.docId,
          doc.payloadJson,
          jsonEncode(doc.structuredData),
          jsonEncode(doc.fieldLengths),
        ]);
      }
      insertDocStmt.close();

      // 3. Collect unique terms and upsert into terms table
      final uniqueTerms = <String>{for (final p in postings) p.term};
      final termIdMap = <String, int>{};

      if (uniqueTerms.isNotEmpty) {
        final insertTermStmt = db.prepare('''
          INSERT INTO terms(term, term_length, doc_frequency)
          VALUES(?, ?, 0)
          ON CONFLICT(term) DO NOTHING;
        ''');
        for (final term in uniqueTerms) {
          insertTermStmt.execute([term, term.length]);
        }
        insertTermStmt.close();

        final termsList = uniqueTerms.toList();
        for (int i = 0; i < termsList.length; i += _sqliteChunkSize) {
          final chunk = termsList.sublist(
            i,
            (i + _sqliteChunkSize > termsList.length) ? termsList.length : i + _sqliteChunkSize,
          );
          final placeholders = List.filled(chunk.length, '?').join(',');
          final rows = db.select(
            'SELECT term_id, term FROM terms WHERE term IN ($placeholders);',
            chunk,
          );
          for (final row in rows) {
            final termId = row['term_id'] as int;
            termIdMap[row['term'] as String] = termId;
            affectedTermIds.add(termId);
          }
        }
      }

      // 4. Insert postings
      if (postings.isNotEmpty) {
        final insertPostingStmt = db.prepare('''
          INSERT OR REPLACE INTO postings(term_id, doc_id, field, term_frequency, positions_blob)
          VALUES(?, ?, ?, ?, ?);
        ''');
        for (final p in postings) {
          final termId = termIdMap[p.term];
          if (termId == null) continue;
          final blob = PostingRecord.packPositions(p.positions);
          insertPostingStmt.execute([
            termId,
            p.docId,
            p.field,
            p.termFrequency,
            blob,
          ]);
        }
        insertPostingStmt.close();
      }

      // 5. Update doc_frequency for all affected term_ids and prune zero-df terms
      if (affectedTermIds.isNotEmpty) {
        final updateFreqStmt = db.prepare('''
          UPDATE terms SET doc_frequency = (
            SELECT COUNT(DISTINCT doc_id) FROM postings WHERE postings.term_id = terms.term_id
          ) WHERE term_id = ?;
        ''');
        for (final termId in affectedTermIds) {
          updateFreqStmt.execute([termId]);
        }
        updateFreqStmt.close();

        final affectedList = affectedTermIds.toList();
        for (int i = 0; i < affectedList.length; i += _sqliteChunkSize) {
          final chunk = affectedList.sublist(
            i,
            (i + _sqliteChunkSize > affectedList.length)
                ? affectedList.length
                : i + _sqliteChunkSize,
          );
          final placeholders = List.filled(chunk.length, '?').join(',');
          db.execute(
            'DELETE FROM terms WHERE term_id IN ($placeholders) AND doc_frequency <= 0;',
            chunk,
          );
        }
      }

      // 6. Insert facets
      if (facets.isNotEmpty) {
        final insertFacetStmt = db.prepare('''
          INSERT OR REPLACE INTO facets(field, value, doc_id)
          VALUES(?, ?, ?);
        ''');
        for (final f in facets) {
          insertFacetStmt.execute([f.field, f.value, f.docId]);
        }
        insertFacetStmt.close();
      }

      // 7. Persist cached document count and field totals in index_meta
      _writeTotalsSync(totalDocs < 0 ? 0 : totalDocs, fieldTotals);

      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<void> deleteDocument(String docId) async {
    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final oldDocs = db.select(
        'SELECT field_lengths_json FROM documents WHERE doc_id = ?;',
        [docId],
      );
      if (oldDocs.isEmpty) {
        db.execute('COMMIT;');
        return;
      }

      int totalDocs = _readTotalDocsSync() - 1;
      final fieldTotals = _readFieldTotalsSync();
      final oldLengths = jsonDecode(oldDocs.first['field_lengths_json'] as String) as Map<String, dynamic>;
      for (final entry in oldLengths.entries) {
        final next = (fieldTotals[entry.key] ?? 0) - (entry.value as int);
        if (next <= 0) {
          fieldTotals.remove(entry.key);
        } else {
          fieldTotals[entry.key] = next;
        }
      }

      final oldTermRows = db.select(
        'SELECT DISTINCT term_id FROM postings WHERE doc_id = ?;',
        [docId],
      );
      final affectedTermIds = oldTermRows.map((r) => r['term_id'] as int).toList();

      db.execute('DELETE FROM documents WHERE doc_id = ?;', [docId]);

      if (affectedTermIds.isNotEmpty) {
        final updateFreqStmt = db.prepare('''
          UPDATE terms SET doc_frequency = (
            SELECT COUNT(DISTINCT doc_id) FROM postings WHERE postings.term_id = terms.term_id
          ) WHERE term_id = ?;
        ''');
        for (final termId in affectedTermIds) {
          updateFreqStmt.execute([termId]);
        }
        updateFreqStmt.close();

        for (int i = 0; i < affectedTermIds.length; i += _sqliteChunkSize) {
          final chunk = affectedTermIds.sublist(
            i,
            (i + _sqliteChunkSize > affectedTermIds.length)
                ? affectedTermIds.length
                : i + _sqliteChunkSize,
          );
          final placeholders = List.filled(chunk.length, '?').join(',');
          db.execute(
            'DELETE FROM terms WHERE term_id IN ($placeholders) AND doc_frequency <= 0;',
            chunk,
          );
        }
      }

      _writeTotalsSync(totalDocs < 0 ? 0 : totalDocs, fieldTotals);
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<DocumentRecord?> getDocument(String docId) async {
    final rows = db.select('SELECT * FROM documents WHERE doc_id = ?;', [docId]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return DocumentRecord(
      docId: row['doc_id'] as String,
      payloadJson: row['payload_json'] as String,
      structuredData: jsonDecode(row['structured_json'] as String) as Map<String, dynamic>,
      fieldLengths: (jsonDecode(row['field_lengths_json'] as String) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as int)),
    );
  }

  @override
  Future<List<DocumentRecord>> getDocuments(List<String> docIds) async {
    if (docIds.isEmpty) return const [];
    final results = <DocumentRecord>[];
    for (int i = 0; i < docIds.length; i += _sqliteChunkSize) {
      final chunk = docIds.sublist(
        i,
        (i + _sqliteChunkSize > docIds.length) ? docIds.length : i + _sqliteChunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = db.select('SELECT * FROM documents WHERE doc_id IN ($placeholders);', chunk);
      for (final row in rows) {
        results.add(DocumentRecord(
          docId: row['doc_id'] as String,
          payloadJson: row['payload_json'] as String,
          structuredData: jsonDecode(row['structured_json'] as String) as Map<String, dynamic>,
          fieldLengths: (jsonDecode(row['field_lengths_json'] as String) as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as int)),
        ));
      }
    }
    return results;
  }

  @override
  Future<Map<String, Map<String, int>>> getDocumentFieldLengths(List<String> docIds) async {
    if (docIds.isEmpty) return const {};
    final result = <String, Map<String, int>>{};
    for (int i = 0; i < docIds.length; i += _sqliteChunkSize) {
      final chunk = docIds.sublist(
        i,
        (i + _sqliteChunkSize > docIds.length) ? docIds.length : i + _sqliteChunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = db.select(
        'SELECT doc_id, field_lengths_json FROM documents WHERE doc_id IN ($placeholders);',
        chunk,
      );
      for (final row in rows) {
        final decoded = jsonDecode(row['field_lengths_json'] as String) as Map<String, dynamic>;
        result[row['doc_id'] as String] = decoded.map((k, v) => MapEntry(k, v as int));
      }
    }
    return result;
  }

  List<PostingRecord> _mapPostingRows(ResultSet rows, {bool includePositions = true}) {
    return rows.map((row) {
      final positions = includePositions
          ? PostingRecord.unpackPositions(row['positions_blob'] as Uint8List)
          : const <int>[];
      return PostingRecord(
        term: row['term'] as String,
        docId: row['doc_id'] as String,
        field: row['field'] as String,
        termFrequency: row['term_frequency'] as int,
        positions: positions,
      );
    }).toList();
  }

  @override
  Future<List<PostingRecord>> getPostingsForTerm(
    String term, {
    bool includePositions = true,
  }) async {
    final posSelect = includePositions ? ', p.positions_blob' : '';
    final rows = db.select('''
      SELECT t.term, p.doc_id, p.field, p.term_frequency$posSelect
      FROM postings p
      JOIN terms t ON p.term_id = t.term_id
      WHERE t.term = ?;
    ''', [term]);
    return _mapPostingRows(rows, includePositions: includePositions);
  }

  @override
  Future<List<PostingRecord>> getPostingsForTerms(
    List<String> terms, {
    bool includePositions = true,
  }) async {
    if (terms.isEmpty) return const [];
    final posSelect = includePositions ? ', p.positions_blob' : '';
    final results = <PostingRecord>[];
    for (int i = 0; i < terms.length; i += _sqliteChunkSize) {
      final chunk = terms.sublist(
        i,
        (i + _sqliteChunkSize > terms.length) ? terms.length : i + _sqliteChunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = db.select('''
        SELECT t.term, p.doc_id, p.field, p.term_frequency$posSelect
        FROM postings p
        JOIN terms t ON p.term_id = t.term_id
        WHERE t.term IN ($placeholders);
      ''', chunk);
      results.addAll(_mapPostingRows(rows, includePositions: includePositions));
    }
    return results;
  }

  @override
  Future<List<PostingRecord>> getPostingsForPrefix(
    String prefix, {
    bool includePositions = true,
  }) async {
    if (prefix.isEmpty) return const [];
    final posSelect = includePositions ? ', p.positions_blob' : '';
    final lastUnit = prefix.codeUnitAt(prefix.length - 1);
    if (lastUnit < 0xFFFF) {
      // B-tree range scan using idx_terms_term
      final upperBound = '${prefix.substring(0, prefix.length - 1)}${String.fromCharCode(lastUnit + 1)}';
      final rows = db.select('''
        SELECT t.term, p.doc_id, p.field, p.term_frequency$posSelect
        FROM postings p
        JOIN terms t ON p.term_id = t.term_id
        WHERE t.term >= ? AND t.term < ?;
      ''', [prefix, upperBound]);
      return _mapPostingRows(rows, includePositions: includePositions);
    }
    final rows = db.select('''
      SELECT t.term, p.doc_id, p.field, p.term_frequency$posSelect
      FROM postings p
      JOIN terms t ON p.term_id = t.term_id
      WHERE t.term LIKE ?;
    ''', ['$prefix%']);
    return _mapPostingRows(rows, includePositions: includePositions);
  }

  @override
  Future<List<PostingRecord>> getPostingsForLengthWindow(
    int minLength,
    int maxLength, {
    bool includePositions = true,
  }) async {
    final posSelect = includePositions ? ', p.positions_blob' : '';
    final rows = db.select('''
      SELECT t.term, p.doc_id, p.field, p.term_frequency$posSelect
      FROM postings p
      JOIN terms t ON p.term_id = t.term_id
      WHERE t.term_length BETWEEN ? AND ?;
    ''', [minLength, maxLength]);
    return _mapPostingRows(rows, includePositions: includePositions);
  }

  @override
  Future<Map<String, int>> getDocFrequencies(List<String> terms) async {
    if (terms.isEmpty) return const {};
    final result = <String, int>{for (final t in terms) t: 0};
    for (int i = 0; i < terms.length; i += _sqliteChunkSize) {
      final chunk = terms.sublist(
        i,
        (i + _sqliteChunkSize > terms.length) ? terms.length : i + _sqliteChunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = db.select('''
        SELECT term, doc_frequency FROM terms WHERE term IN ($placeholders);
      ''', chunk);
      for (final row in rows) {
        result[row['term'] as String] = row['doc_frequency'] as int;
      }
    }
    return result;
  }

  @override
  Future<int> getDocumentCount() async {
    return _readTotalDocsSync();
  }

  @override
  Future<Map<String, int>> getFieldTotalLengths() async {
    return _readFieldTotalsSync();
  }

  String _jsonPath(String field) {
    final escaped = field.replaceAll('"', '\\"');
    return '\$."$escaped"';
  }

  @override
  Future<Set<String>> filterDocIds(List<SearchFilter> filters) async {
    if (filters.isEmpty) {
      final rows = db.select('SELECT doc_id FROM documents;');
      return rows.map((r) => r['doc_id'] as String).toSet();
    }

    final whereClauses = <String>[];
    final params = <dynamic>[];

    for (final filter in filters) {
      final path = _jsonPath(filter.field);
      switch (filter.operator) {
        case FilterOperator.equals:
          final val = filter.value;
          if (val is bool) {
            whereClauses.add('json_extract(structured_json, ?) = ?');
            params.addAll([path, val ? 1 : 0]);
          } else if (val is num) {
            whereClauses.add(
              "json_type(structured_json, ?) IN ('integer', 'real') AND CAST(json_extract(structured_json, ?) AS REAL) = ?",
            );
            params.addAll([path, path, val.toDouble()]);
          } else {
            whereClauses.add('LOWER(CAST(json_extract(structured_json, ?) AS TEXT)) = LOWER(?)');
            params.addAll([path, val.toString()]);
          }
        case FilterOperator.inList:
          final values = (filter.value is Iterable) ? (filter.value as Iterable).toList() : const [];
          if (values.isEmpty) return const <String>{};
          final placeholders = List.filled(values.length, 'LOWER(?)').join(',');
          whereClauses.add('LOWER(CAST(json_extract(structured_json, ?) AS TEXT)) IN ($placeholders)');
          params.add(path);
          for (final v in values) {
            params.add(v.toString());
          }
        case FilterOperator.range:
          whereClauses.add("json_type(structured_json, ?) IN ('integer', 'real')");
          params.add(path);
          if (filter.min != null) {
            whereClauses.add('CAST(json_extract(structured_json, ?) AS REAL) >= ?');
            params.addAll([path, filter.min!.toDouble()]);
          }
          if (filter.max != null) {
            whereClauses.add('CAST(json_extract(structured_json, ?) AS REAL) <= ?');
            params.addAll([path, filter.max!.toDouble()]);
          }
        case FilterOperator.gt:
          whereClauses.add(
            "json_type(structured_json, ?) IN ('integer', 'real') AND CAST(json_extract(structured_json, ?) AS REAL) > ?",
          );
          params.addAll([path, path, (filter.value as num).toDouble()]);
        case FilterOperator.gte:
          whereClauses.add(
            "json_type(structured_json, ?) IN ('integer', 'real') AND CAST(json_extract(structured_json, ?) AS REAL) >= ?",
          );
          params.addAll([path, path, (filter.value as num).toDouble()]);
        case FilterOperator.lt:
          whereClauses.add(
            "json_type(structured_json, ?) IN ('integer', 'real') AND CAST(json_extract(structured_json, ?) AS REAL) < ?",
          );
          params.addAll([path, path, (filter.value as num).toDouble()]);
        case FilterOperator.lte:
          whereClauses.add(
            "json_type(structured_json, ?) IN ('integer', 'real') AND CAST(json_extract(structured_json, ?) AS REAL) <= ?",
          );
          params.addAll([path, path, (filter.value as num).toDouble()]);
        case FilterOperator.boolean:
          whereClauses.add(
            "json_type(structured_json, ?) IN ('true', 'false') AND json_extract(structured_json, ?) = ?",
          );
          params.addAll([path, path, (filter.value == true) ? 1 : 0]);
      }
    }

    final sql = 'SELECT doc_id FROM documents WHERE ${whereClauses.join(' AND ')};';
    final rows = db.select(sql, params);
    return rows.map((r) => r['doc_id'] as String).toSet();
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
    if (docIdFilter != null && docIdFilter.isEmpty) return result;

    final fieldPlaceholders = List.filled(facetFields.length, '?').join(',');

    if (docIdFilter == null) {
      final rows = db.select('''
        SELECT field, value, COUNT(DISTINCT doc_id) as count
        FROM facets
        WHERE field IN ($fieldPlaceholders)
        GROUP BY field, value;
      ''', facetFields);
      for (final row in rows) {
        final field = row['field'] as String;
        final value = row['value'] as String;
        final count = row['count'] as int;
        result[field]?[value] = count;
      }
      return result;
    }

    // Chunk docIdFilter safely to stay under SQLITE_MAX_VARIABLE_NUMBER
    final docList = docIdFilter.toList();
    final maxDocsPerChunk = (_sqliteChunkSize - facetFields.length).clamp(50, _sqliteChunkSize);
    for (int i = 0; i < docList.length; i += maxDocsPerChunk) {
      final chunk = docList.sublist(
        i,
        (i + maxDocsPerChunk > docList.length) ? docList.length : i + maxDocsPerChunk,
      );
      final docPlaceholders = List.filled(chunk.length, '?').join(',');
      final params = <dynamic>[...facetFields, ...chunk];

      final rows = db.select('''
        SELECT field, value, COUNT(DISTINCT doc_id) as count
        FROM facets
        WHERE field IN ($fieldPlaceholders) AND doc_id IN ($docPlaceholders)
        GROUP BY field, value;
      ''', params);

      for (final row in rows) {
        final field = row['field'] as String;
        final value = row['value'] as String;
        final count = row['count'] as int;
        final fieldMap = result[field];
        if (fieldMap != null) {
          fieldMap[value] = (fieldMap[value] ?? 0) + count;
        }
      }
    }

    return result;
  }
}
