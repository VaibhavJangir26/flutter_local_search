/// Represents an individual analyzed token with positional and character offsets.
class Token {
  /// The normalized term string.
  final String term;

  /// The 0-based token position in the document/field stream (used for phrase queries).
  final int position;

  /// The character start offset in the original input string.
  final int startOffset;

  /// The character end offset in the original input string.
  final int endOffset;

  const Token({
    required this.term,
    required this.position,
    required this.startOffset,
    required this.endOffset,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Token &&
          runtimeType == other.runtimeType &&
          term == other.term &&
          position == other.position &&
          startOffset == other.startOffset &&
          endOffset == other.endOffset;

  @override
  int get hashCode => Object.hash(term, position, startOffset, endOffset);

  @override
  String toString() => 'Token("$term", pos: $position, [$startOffset:$endOffset])';
}
