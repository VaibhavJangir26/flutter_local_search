import '../storage/storage_records.dart';

/// Verifies positional token proximity within document fields for quoted phrase queries.
class PhraseMatcher {
  const PhraseMatcher();

  /// Returns the set of `docId`s where [phraseTerms] appear sequentially in the same field
  /// within the allowed [slop] (0 = exact contiguous sequence).
  Set<String> matchPhraseDocIds({
    required List<String> phraseTerms,
    required List<PostingRecord> postings,
    int slop = 0,
  }) {
    if (phraseTerms.isEmpty || postings.isEmpty) return const {};

    if (phraseTerms.length == 1) {
      final target = phraseTerms.first;
      return postings
          .where((p) => p.term == target)
          .map((p) => p.docId)
          .toSet();
    }

    // Group postings by docId -> field -> term -> positions
    final byDocField = <String, Map<String, Map<String, List<int>>>>{};
    for (final p in postings) {
      byDocField
          .putIfAbsent(p.docId, () => {})
          .putIfAbsent(p.field, () => {})[p.term] = p.positions;
    }

    final matchedDocIds = <String>{};

    for (final docEntry in byDocField.entries) {
      final docId = docEntry.key;
      for (final termPosMap in docEntry.value.values) {
        if (_matchesInField(phraseTerms, termPosMap, slop)) {
          matchedDocIds.add(docId);
          break;
        }
      }
    }

    return matchedDocIds;
  }

  bool _matchesInField(
    List<String> phraseTerms,
    Map<String, List<int>> termPosMap,
    int slop,
  ) {
    // Quick bail if any phrase term is missing from this field
    final positionLists = <List<int>>[];
    for (final term in phraseTerms) {
      final pos = termPosMap[term];
      if (pos == null || pos.isEmpty) return false;
      positionLists.add(pos);
    }

    // Backtrack from each start position of the first term
    for (final startPos in positionLists.first) {
      if (_canCompletePhrase(positionLists, 1, startPos, slop)) {
        return true;
      }
    }
    return false;
  }

  bool _canCompletePhrase(
    List<List<int>> positionLists,
    int termIndex,
    int prevPos,
    int remainingSlop,
  ) {
    if (termIndex >= positionLists.length) return true;

    final candidates = positionLists[termIndex];
    for (final pos in candidates) {
      if (pos <= prevPos) continue;
      final gap = pos - prevPos - 1;
      if (gap <= remainingSlop) {
        if (_canCompletePhrase(
          positionLists,
          termIndex + 1,
          pos,
          remainingSlop - gap,
        )) {
          return true;
        }
      } else if (pos > prevPos + 1 + remainingSlop) {
        // Positions are sorted ascending; no later position can match
        break;
      }
    }
    return false;
  }
}
