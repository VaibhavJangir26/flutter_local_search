import 'search_query.dart';

enum _TokenKind { word, phrase, andOp, orOp, notOp }

class _QueryToken {
  final _TokenKind kind;
  final String text;
  const _QueryToken(this.kind, this.text);
}

/// Parses human-friendly search query strings into a structured [SearchQuery] AST.
///
/// Supports:
/// - Quoted exact phrases: `"spring boot"`
/// - Negations: `-deprecated` or `NOT deprecated`
/// - Boolean operators: `AND`, `OR` (with `AND` binding tighter than `OR`)
/// - Implicit OR between plain words so multi-word queries rank partial matches below full matches
class QueryParser {
  /// Parses [rawQuery] into a [SearchQuery].
  static SearchQuery parse(String rawQuery) {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) {
      return const SearchQuery();
    }

    final tokens = _tokenize(trimmed);
    if (tokens.isEmpty) {
      return const SearchQuery();
    }

    final parser = _AstBuilder(tokens);
    final root = parser.parseOrExpression();
    return SearchQuery(root: root);
  }

  static List<_QueryToken> _tokenize(String input) {
    final tokens = <_QueryToken>[];
    final buffer = StringBuffer();
    int i = 0;

    void flushBuffer() {
      if (buffer.isEmpty) return;
      final word = buffer.toString();
      buffer.clear();

      if (word == 'AND') {
        tokens.add(const _QueryToken(_TokenKind.andOp, 'AND'));
      } else if (word == 'OR') {
        tokens.add(const _QueryToken(_TokenKind.orOp, 'OR'));
      } else if (word == 'NOT') {
        tokens.add(const _QueryToken(_TokenKind.notOp, 'NOT'));
      } else if (word.startsWith('-') && word.length > 1) {
        tokens.add(const _QueryToken(_TokenKind.notOp, 'NOT'));
        tokens.add(_QueryToken(_TokenKind.word, word.substring(1)));
      } else {
        tokens.add(_QueryToken(_TokenKind.word, word));
      }
    }

    while (i < input.length) {
      final ch = input[i];
      if (ch == '"') {
        flushBuffer();
        i++; // skip opening quote
        final phraseBuf = StringBuffer();
        while (i < input.length && input[i] != '"') {
          phraseBuf.write(input[i]);
          i++;
        }
        if (i < input.length && input[i] == '"') {
          i++; // skip closing quote
        }
        final phrase = phraseBuf.toString().trim();
        if (phrase.isNotEmpty) {
          tokens.add(_QueryToken(_TokenKind.phrase, phrase));
        }
      } else if (ch.trim().isEmpty) {
        flushBuffer();
        i++;
      } else {
        buffer.write(ch);
        i++;
      }
    }
    flushBuffer();

    return tokens;
  }
}

class _AstBuilder {
  final List<_QueryToken> tokens;
  int _pos = 0;

  _AstBuilder(this.tokens);

  bool get _hasMore => _pos < tokens.length;
  _QueryToken get _peek => tokens[_pos];

  QueryNode? parseOrExpression() {
    final left = parseAndExpression();
    if (left == null) return null;

    final branches = <QueryNode>[left];
    while (_hasMore && _peek.kind == _TokenKind.orOp) {
      _pos++; // consume OR
      final right = parseAndExpression();
      if (right != null) {
        branches.add(right);
      }
    }

    return branches.length == 1 ? branches.first : OrQueryNode(branches);
  }

  QueryNode? parseAndExpression() {
    final first = parseTerm();
    if (first == null) return null;

    final andTerms = <QueryNode>[];
    final softTerms = <QueryNode>[first];
    bool hasExplicitAndOrNot = false;

    while (_hasMore) {
      if (_peek.kind == _TokenKind.orOp) {
        break;
      }

      if (_peek.kind == _TokenKind.andOp) {
        hasExplicitAndOrNot = true;
        _pos++; // consume AND
        final next = parseTerm();
        if (next != null) {
          if (andTerms.isEmpty) {
            andTerms.addAll(softTerms);
            softTerms.clear();
          }
          andTerms.add(next);
        }
      } else if (_peek.kind == _TokenKind.notOp) {
        hasExplicitAndOrNot = true;
        final next = parseTerm();
        if (next != null) {
          if (andTerms.isEmpty) {
            final base = softTerms.length == 1
                ? softTerms.first
                : OrQueryNode(List<QueryNode>.from(softTerms));
            softTerms.clear();
            andTerms.add(base);
          }
          andTerms.add(next);
        }
      } else {
        // Adjacent term without explicit operator
        final next = parseTerm();
        if (next != null) {
          if (hasExplicitAndOrNot) {
            andTerms.add(next);
          } else {
            softTerms.add(next);
          }
        }
      }
    }

    if (hasExplicitAndOrNot) {
      return andTerms.length == 1 ? andTerms.first : AndQueryNode(andTerms);
    }
    return softTerms.length == 1 ? softTerms.first : OrQueryNode(softTerms);
  }

  QueryNode? parseTerm() {
    if (!_hasMore) return null;
    final token = tokens[_pos];

    if (token.kind == _TokenKind.notOp) {
      _pos++;
      final target = parseTerm();
      if (target == null) return null;
      return NotQueryNode(target);
    }

    if (token.kind == _TokenKind.phrase) {
      _pos++;
      return PhraseQueryNode(token.text);
    }

    if (token.kind == _TokenKind.word) {
      _pos++;
      return MatchQueryNode(token.text);
    }

    // Unexpected operator token; skip safely
    _pos++;
    return parseTerm();
  }
}
