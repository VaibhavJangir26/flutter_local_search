import '../models/search_filter.dart';
import 'query_parser.dart';

/// Base node in the search query Abstract Syntax Tree (AST).
sealed class QueryNode {
  const QueryNode();
}

/// Matches a text term or multi-word string.
class MatchQueryNode extends QueryNode {
  final String text;
  const MatchQueryNode(this.text);
}

/// Matches an exact ordered phrase with optional positional slop.
class PhraseQueryNode extends QueryNode {
  final String phrase;
  final int slop;
  const PhraseQueryNode(this.phrase, {this.slop = 0});
}

/// Logical conjunction (all children must match).
class AndQueryNode extends QueryNode {
  final List<QueryNode> children;
  const AndQueryNode(this.children);
}

/// Logical disjunction (any child may match).
class OrQueryNode extends QueryNode {
  final List<QueryNode> children;
  const OrQueryNode(this.children);
}

/// Logical negation (excludes documents matching child).
class NotQueryNode extends QueryNode {
  final QueryNode child;
  const NotQueryNode(this.child);
}

/// Fluent Query DSL for building structured boolean, phrase, and filtered searches.
class SearchQuery {
  final QueryNode? root;
  final List<SearchFilter> filters;

  const SearchQuery({
    this.root,
    this.filters = const [],
  });

  /// Matches text terms (analyzed with [TextAnalyzer]).
  factory SearchQuery.match(String text) {
    return SearchQuery(root: MatchQueryNode(text));
  }

  /// Matches an exact ordered sequence of words (with optional positional [slop]).
  factory SearchQuery.phrase(String phrase, {int slop = 0}) {
    return SearchQuery(root: PhraseQueryNode(phrase, slop: slop));
  }

  /// Requires all sub-queries to match.
  factory SearchQuery.and(List<SearchQuery> queries) {
    final nodes = queries.map((q) => q.root).whereType<QueryNode>().toList();
    final combinedFilters = [for (final q in queries) ...q.filters];
    return SearchQuery(
      root: nodes.isEmpty ? null : (nodes.length == 1 ? nodes.first : AndQueryNode(nodes)),
      filters: combinedFilters,
    );
  }

  /// Matches if any sub-query matches.
  factory SearchQuery.or(List<SearchQuery> queries) {
    final nodes = queries.map((q) => q.root).whereType<QueryNode>().toList();
    final combinedFilters = [for (final q in queries) ...q.filters];
    return SearchQuery(
      root: nodes.isEmpty ? null : (nodes.length == 1 ? nodes.first : OrQueryNode(nodes)),
      filters: combinedFilters,
    );
  }

  /// Excludes documents matching [query].
  factory SearchQuery.not(SearchQuery query) {
    if (query.root == null) return SearchQuery(filters: query.filters);
    return SearchQuery(
      root: NotQueryNode(query.root!),
      filters: query.filters,
    );
  }

  /// Parses a search string supporting quoted phrases (`"spring boot"`),
  /// boolean operators (`AND`, `OR`, `NOT`), and exclusions (`-term`).
  factory SearchQuery.parse(String rawQuery) {
    return QueryParser.parse(rawQuery);
  }

  /// Combines this query with [other] using logical AND.
  SearchQuery and(SearchQuery other) => SearchQuery.and([this, other]);

  /// Combines this query with [other] using logical OR.
  SearchQuery or(SearchQuery other) => SearchQuery.or([this, other]);

  /// Excludes documents matching [excluded] using logical AND NOT.
  SearchQuery andNot(SearchQuery excluded) =>
      SearchQuery.and([this, SearchQuery.not(excluded)]);

  /// Appends a structured [SearchFilter] to this query.
  SearchQuery where(SearchFilter filter) {
    return SearchQuery(
      root: root,
      filters: [...filters, filter],
    );
  }

  /// Appends multiple structured [SearchFilter]s to this query.
  SearchQuery whereAll(List<SearchFilter> newFilters) {
    return SearchQuery(
      root: root,
      filters: [...filters, ...newFilters],
    );
  }
}
