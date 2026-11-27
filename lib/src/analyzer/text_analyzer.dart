import 'token.dart';

/// Contract for text tokenization, normalization, and linguistic processing.
abstract class TextAnalyzer {
  /// Analyzes the input [text] into a list of normalized [Token]s.
  List<Token> analyze(String text);
}
