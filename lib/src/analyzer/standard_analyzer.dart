import 'text_analyzer.dart';
import 'token.dart';

/// Standard analyzer that lowercases, extracts word tokens, removes punctuation,
/// optionally filters common stop words, and tracks token positions and offsets.
class StandardAnalyzer implements TextAnalyzer {
  /// Common English stop words.
  static const Set<String> defaultStopWords = {
    'a', 'an', 'and', 'are', 'as', 'at', 'be', 'but', 'by', 'for', 'if', 'in',
    'into', 'is', 'it', 'no', 'not', 'of', 'on', 'or', 'such', 'that', 'the',
    'their', 'then', 'there', 'these', 'they', 'this', 'to', 'was', 'will', 'with'
  };

  final bool lowercase;
  final Set<String> stopWords;
  final bool removeStopWords;

  // Matches sequences of alphanumeric characters and underscores/digits.
  // Supports Unicode word characters where possible.
  static final RegExp _wordPattern = RegExp(r"[\p{L}\p{N}]+", unicode: true);

  const StandardAnalyzer({
    this.lowercase = true,
    this.stopWords = defaultStopWords,
    this.removeStopWords = true,
  });

  @override
  List<Token> analyze(String text) {
    if (text.isEmpty) return const [];

    final tokens = <Token>[];
    int currentPosition = 0;

    final matches = _wordPattern.allMatches(text);
    for (final match in matches) {
      String rawWord = match.group(0)!;
      final term = lowercase ? rawWord.toLowerCase() : rawWord;

      if (removeStopWords && stopWords.contains(term)) {
        // Skip stop words while advancing position gap for phrase precision if desired
        continue;
      }

      tokens.add(Token(
        term: term,
        position: currentPosition++,
        startOffset: match.start,
        endOffset: match.end,
      ));
    }

    return tokens;
  }
}
