import 'dart:math' as math;

/// Fast typo-tolerant fuzzy matching utilizing Optimal String Alignment
/// (restricted Damerau-Levenshtein distance) with string length pruning.
///
/// Adjacent character transpositions (e.g. `"fluter"` -> `"flutter"` or
/// `"iphnoe"` -> `"iphone"`) count as a single edit (distance 1).
class FuzzyMatcher {
  /// Computes the Damerau-Levenshtein distance between [source] and [target].
  /// Returns `maxDistance + 1` early if the distance is guaranteed to exceed [maxDistance].
  static int damerauLevenshteinDistance(
    String source,
    String target, {
    int maxDistance = 2,
  }) {
    if (source == target) return 0;
    if ((source.length - target.length).abs() > maxDistance) {
      return maxDistance + 1;
    }

    final sLen = source.length;
    final tLen = target.length;

    if (sLen == 0) return tLen <= maxDistance ? tLen : maxDistance + 1;
    if (tLen == 0) return sLen <= maxDistance ? sLen : maxDistance + 1;

    var prev2 = List<int>.filled(tLen + 1, 0);
    var prev1 = List<int>.generate(tLen + 1, (j) => j);
    var curr = List<int>.filled(tLen + 1, 0);

    var prev1Min = 0;

    for (int i = 1; i <= sLen; i++) {
      curr[0] = i;
      int currMin = curr[0];
      final sChar = source.codeUnitAt(i - 1);

      for (int j = 1; j <= tLen; j++) {
        final tChar = target.codeUnitAt(j - 1);
        final cost = (sChar == tChar) ? 0 : 1;

        var d = math.min(
          prev1[j] + 1, // deletion
          math.min(
            curr[j - 1] + 1, // insertion
            prev1[j - 1] + cost, // substitution
          ),
        );

        // Adjacent transposition
        if (i > 1 &&
            j > 1 &&
            sChar == target.codeUnitAt(j - 2) &&
            source.codeUnitAt(i - 2) == tChar) {
          d = math.min(d, prev2[j - 2] + 1);
        }

        curr[j] = d;
        if (d < currMin) {
          currMin = d;
        }
      }

      if (currMin > maxDistance && prev1Min > maxDistance) {
        return maxDistance + 1;
      }

      final temp = prev2;
      prev2 = prev1;
      prev1 = curr;
      curr = temp;
      prev1Min = currMin;
    }

    return prev1[tLen] <= maxDistance ? prev1[tLen] : maxDistance + 1;
  }

  /// Backward-compatible alias for [damerauLevenshteinDistance].
  static int levenshteinDistance(
    String source,
    String target, {
    int maxDistance = 2,
  }) =>
      damerauLevenshteinDistance(source, target, maxDistance: maxDistance);

  /// Returns the edit distance if [candidate] matches [queryTerm] within [maxDistance],
  /// or `null` if it does not match.
  static int? matchDistance(
    String queryTerm,
    String candidate, {
    int maxDistance = 2,
  }) {
    if ((candidate.length - queryTerm.length).abs() > maxDistance) {
      return null;
    }
    final dist = damerauLevenshteinDistance(
      queryTerm,
      candidate,
      maxDistance: maxDistance,
    );
    return dist <= maxDistance ? dist : null;
  }

  /// Checks if [candidate] is within [maxDistance] of [queryTerm].
  static bool isMatch(String queryTerm, String candidate, {int maxDistance = 2}) {
    return matchDistance(queryTerm, candidate, maxDistance: maxDistance) != null;
  }

  /// Relevance score multiplier based on edit distance so exact matches always
  /// outrank 1-typo matches, which outrank 2-typo matches.
  static double weightForDistance(int distance) {
    if (distance <= 0) return 1.0;
    if (distance == 1) return 0.7;
    return 0.4;
  }
}
