import 'dart:math' as math;

/// Extracts contextual snippets and highlights matched terms with configurable tags
/// while respecting word boundaries so partial mid-word substrings are never highlighted.
class Highlighter {
  final String preTag;
  final String postTag;
  final int maxSnippetLength;

  static final RegExp _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  const Highlighter({
    this.preTag = '<mark>',
    this.postTag = '</mark>',
    this.maxSnippetLength = 120,
  });

  /// Highlights whole-word occurrences of [matchingTerms] in [sourceText]
  /// and returns contextual snippets.
  List<String> highlight(String sourceText, Set<String> matchingTerms) {
    if (sourceText.isEmpty || matchingTerms.isEmpty) return const [];

    final normalizedTerms = matchingTerms
        .map((t) => t.toLowerCase())
        .where((t) => t.isNotEmpty)
        .toSet();
    if (normalizedTerms.isEmpty) return const [];

    // Collect exact word span matches using token boundaries
    final matchSpans = <RegExpMatch>[];
    for (final m in _wordPattern.allMatches(sourceText)) {
      final word = m.group(0)!.toLowerCase();
      if (normalizedTerms.contains(word)) {
        matchSpans.add(m);
      }
    }

    if (matchSpans.isEmpty) return const [];

    final snippets = <String>[];
    int lastSnippetEnd = -1;

    for (final firstMatch in matchSpans) {
      if (firstMatch.start < lastSnippetEnd) continue;

      final snippetStart = math.max(0, firstMatch.start - 30);
      final snippetEnd = math.min(sourceText.length, firstMatch.start + maxSnippetLength);
      lastSnippetEnd = snippetEnd;

      // Build snippet by wrapping all matched word spans inside [snippetStart, snippetEnd)
      final buffer = StringBuffer();
      if (snippetStart > 0) buffer.write('...');

      int cursor = snippetStart;
      for (final m in matchSpans) {
        if (m.end <= snippetStart) continue;
        if (m.start >= snippetEnd) break;

        final clampedStart = math.max(snippetStart, m.start);
        final clampedEnd = math.min(snippetEnd, m.end);
        if (clampedStart > cursor) {
          buffer.write(sourceText.substring(cursor, clampedStart));
        }
        buffer.write(preTag);
        buffer.write(sourceText.substring(clampedStart, clampedEnd));
        buffer.write(postTag);
        cursor = clampedEnd;
      }

      if (cursor < snippetEnd) {
        buffer.write(sourceText.substring(cursor, snippetEnd));
      }
      if (snippetEnd < sourceText.length) buffer.write('...');

      snippets.add(buffer.toString());
    }

    return snippets;
  }
}
