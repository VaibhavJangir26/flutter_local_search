import 'dart:typed_data';

/// Stored document representation containing JSON payload and structured fields.
class DocumentRecord {
  final String docId;
  final String payloadJson;
  final Map<String, dynamic> structuredData;
  final Map<String, int> fieldLengths;

  const DocumentRecord({
    required this.docId,
    required this.payloadJson,
    required this.structuredData,
    required this.fieldLengths,
  });
}

/// A posting entry connecting a term to an occurrence in a document field.
class PostingRecord {
  final String term;
  final String docId;
  final String field;
  final int termFrequency;
  final List<int> positions;

  const PostingRecord({
    required this.term,
    required this.docId,
    required this.field,
    required this.termFrequency,
    required this.positions,
  });

  /// Packs positions into a portable little-endian Uint8List byte blob.
  static Uint8List packPositions(List<int> positions) {
    final byteData = ByteData(positions.length * 4);
    for (int i = 0; i < positions.length; i++) {
      byteData.setUint32(i * 4, positions[i], Endian.little);
    }
    return byteData.buffer.asUint8List();
  }

  /// Unpacks positions from a little-endian Uint8List byte blob.
  static List<int> unpackPositions(Uint8List bytes) {
    if (bytes.isEmpty) return const [];
    final byteData = ByteData.sublistView(bytes);
    final count = bytes.lengthInBytes ~/ 4;
    final list = List<int>.filled(count, 0);
    for (int i = 0; i < count; i++) {
      list[i] = byteData.getUint32(i * 4, Endian.little);
    }
    return list;
  }
}

/// Stored categorical facet entry for filtering and aggregations.
class FacetRecord {
  final String field;
  final String value;
  final String docId;

  const FacetRecord({
    required this.field,
    required this.value,
    required this.docId,
  });
}
