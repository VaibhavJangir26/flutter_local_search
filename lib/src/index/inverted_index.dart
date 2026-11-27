import 'dart:convert';
import '../analyzer/text_analyzer.dart';
import '../models/search_field.dart';
import '../storage/storage_records.dart';

/// Serializable batch output produced by [InvertedIndexBuilder].
class BuiltIndexBatch {
  final List<DocumentRecord> documents;
  final List<PostingRecord> postings;
  final List<FacetRecord> facets;
  final Map<String, double> fieldWeights;

  const BuiltIndexBatch({
    required this.documents,
    required this.postings,
    required this.facets,
    required this.fieldWeights,
  });
}

/// Converts raw extracted document fields into storage-ready documents,
/// inverted index postings (with term frequency & positions), and facet records.
class InvertedIndexBuilder {
  final TextAnalyzer analyzer;

  const InvertedIndexBuilder(this.analyzer);

  /// Analyzes a batch of pre-extracted document payloads into inverted index records.
  BuiltIndexBatch buildBatch(List<RawDocumentInput> inputs) {
    final documents = <DocumentRecord>[];
    final postings = <PostingRecord>[];
    final facets = <FacetRecord>[];
    final fieldWeights = <String, double>{};

    for (final input in inputs) {
      final structured = <String, dynamic>{};
      final fieldLengths = <String, int>{};

      for (final entry in input.fields.entries) {
        final fieldName = entry.key;
        final field = entry.value;

        if (field.isTextual) {
          fieldWeights[fieldName] = field.weight;
        }

        if (field.isNumeric || field.isBoolean) {
          structured[fieldName] = field.value;
        } else if (field.isFacetable) {
          final strVal = field.value.toString();
          structured[fieldName] = strVal;
          facets.add(FacetRecord(
            field: fieldName,
            value: strVal,
            docId: input.docId,
          ));
        }

        if (field.isTextual) {
          final text = field.value.toString();
          final tokens = analyzer.analyze(text);
          fieldLengths[fieldName] = tokens.length;

          final termPositions = <String, List<int>>{};
          for (final token in tokens) {
            termPositions.putIfAbsent(token.term, () => []).add(token.position);
          }

          for (final tp in termPositions.entries) {
            postings.add(PostingRecord(
              term: tp.key,
              docId: input.docId,
              field: fieldName,
              termFrequency: tp.value.length,
              positions: tp.value,
            ));
          }
        }
      }

      documents.add(DocumentRecord(
        docId: input.docId,
        payloadJson: input.payloadJson,
        structuredData: structured,
        fieldLengths: fieldLengths,
      ));
    }

    return BuiltIndexBatch(
      documents: documents,
      postings: postings,
      facets: facets,
      fieldWeights: fieldWeights,
    );
  }
}

/// Pure data transfer input for indexing a document (safe to send across Dart Isolates).
class RawDocumentInput {
  final String docId;
  final String payloadJson;
  final Map<String, SearchField> fields;

  RawDocumentInput({
    required this.docId,
    required this.payloadJson,
    required this.fields,
  });

  factory RawDocumentInput.fromMap({
    required String docId,
    required Map<String, dynamic> jsonMap,
    required Map<String, SearchField> fields,
  }) {
    return RawDocumentInput(
      docId: docId,
      payloadJson: jsonEncode(jsonMap),
      fields: fields,
    );
  }
}
