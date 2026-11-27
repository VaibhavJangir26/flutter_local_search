import 'dart:math' as math;
import '../storage/storage_records.dart';

/// BM25F relevance scorer that computes field-weighted Okapi BM25 scores
/// taking into account individual field weights, term match multipliers (exact/prefix/fuzzy),
/// and document field length normalization.
class BM25FScorer {
  /// Controls non-linear term frequency saturation (typically between 1.2 and 2.0).
  final double k1;

  /// Default length normalization parameter b (0 = no length normalization, 1 = full normalization).
  final double b;

  const BM25FScorer({
    this.k1 = 1.2,
    this.b = 0.75,
  });

  /// Calculates the Inverse Document Frequency (IDF) for a term.
  /// IDF = ln(1 + (N - df + 0.5) / (df + 0.5))
  double computeIdf(int totalDocs, int docFrequency) {
    if (totalDocs <= 0 || docFrequency <= 0) return 0.0;
    final numerator = totalDocs - docFrequency + 0.5;
    final denominator = docFrequency + 0.5;
    return math.log(1.0 + (numerator / denominator));
  }

  /// Scores matching documents using BM25F across all fields.
  ///
  /// - [queryTerms]: Matched index terms to score.
  /// - [postings]: Postings for those terms across candidate documents.
  /// - [docLengths]: Map of `docId -> (field -> tokenCount)`.
  /// - [avgFieldLengths]: Map of `field -> averageTokenCount`.
  /// - [fieldWeights]: Map of `field -> weight` (e.g. `{'name': 3.0}`).
  /// - [docFrequencies]: Map of `term -> documentFrequency`.
  /// - [totalDocs]: Total number of indexed documents.
  /// - [termMultipliers]: Optional `term -> multiplier` (1.0 exact, 0.85 prefix, 0.7/0.4 fuzzy).
  Map<String, double> scoreDocuments({
    required List<String> queryTerms,
    required List<PostingRecord> postings,
    required Map<String, Map<String, int>> docLengths,
    required Map<String, double> avgFieldLengths,
    required Map<String, double> fieldWeights,
    required Map<String, int> docFrequencies,
    required int totalDocs,
    Map<String, double> termMultipliers = const {},
  }) {
    if (postings.isEmpty || totalDocs <= 0) return const {};

    // Group postings by docId -> term -> postings across fields
    final docTermPostings = <String, Map<String, List<PostingRecord>>>{};
    for (final p in postings) {
      docTermPostings
          .putIfAbsent(p.docId, () => {})
          .putIfAbsent(p.term, () => [])
          .add(p);
    }

    final scores = <String, double>{};

    for (final docEntry in docTermPostings.entries) {
      final docId = docEntry.key;
      final termMap = docEntry.value;
      final lengths = docLengths[docId] ?? const {};

      double totalDocScore = 0.0;

      for (final queryTerm in queryTerms) {
        final termOccurrences = termMap[queryTerm];
        if (termOccurrences == null || termOccurrences.isEmpty) continue;

        final df = docFrequencies[queryTerm] ?? 0;
        final idf = computeIdf(totalDocs, df);
        if (idf <= 0.0) continue;

        final matchMultiplier = termMultipliers[queryTerm] ?? 1.0;

        // Compute normalized weighted term frequency across all fields for this doc
        double weightedTf = 0.0;
        for (final p in termOccurrences) {
          final field = p.field;
          final weight = fieldWeights[field] ?? 1.0;
          final fieldLen = (lengths[field] ?? p.termFrequency).toDouble();
          final avgLen = avgFieldLengths[field] ?? 1.0;

          final lenNorm = (avgLen > 0) ? (1.0 - b + b * (fieldLen / avgLen)) : 1.0;
          final normFactor = lenNorm <= 0 ? 1.0 : lenNorm;

          weightedTf += weight * (p.termFrequency / normFactor);
        }

        final termScore = matchMultiplier * idf * (weightedTf / (k1 + weightedTf));
        totalDocScore += termScore;
      }

      if (totalDocScore > 0) {
        scores[docId] = totalDocScore;
      }
    }

    return scores;
  }
}
