import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_search/src/analyzer/standard_analyzer.dart';

void main() {
  group('StandardAnalyzer', () {
    const analyzer = StandardAnalyzer();

    test('tokenizes and lowercases text', () {
      final tokens = analyzer.analyze('iPhone 15 Pro Max!');
      expect(tokens.map((t) => t.term).toList(), ['iphone', '15', 'pro', 'max']);
      expect(tokens[0].position, 0);
      expect(tokens[1].position, 1);
      expect(tokens[2].position, 2);
      expect(tokens[3].position, 3);
    });

    test('preserves correct character offsets for highlighting', () {
      const input = 'Hello World';
      final tokens = analyzer.analyze(input);
      expect(tokens.length, 2);
      expect(tokens[0].startOffset, 0);
      expect(tokens[0].endOffset, 5);
      expect(input.substring(tokens[0].startOffset, tokens[0].endOffset), 'Hello');

      expect(tokens[1].startOffset, 6);
      expect(tokens[1].endOffset, 11);
      expect(input.substring(tokens[1].startOffset, tokens[1].endOffset), 'World');
    });

    test('removes stop words by default', () {
      final tokens = analyzer.analyze('This is a great laptop with fast speed');
      // 'this', 'is', 'a', 'with' are stop words
      expect(tokens.map((t) => t.term).toList(), ['great', 'laptop', 'fast', 'speed']);
    });

    test('handles empty or punctuation-only strings cleanly', () {
      expect(analyzer.analyze(''), isEmpty);
      expect(analyzer.analyze('   ... ,,, !!! ???   '), isEmpty);
    });
  });
}
