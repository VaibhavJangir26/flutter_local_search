import 'package:flutter/material.dart';
import '../models/search_response.dart';

/// Production-ready empty state widget shown when no items match a search query or filters.
class LocalSearchEmptyState extends StatelessWidget {
  /// The search query that produced zero results (used in the default subtitle).
  final String? query;

  /// Primary headline text.
  final String title;

  /// Optional custom subtitle. When omitted, generates a helpful message using [query].
  final String? subtitle;

  /// Optional leading icon widget.
  final Widget? icon;

  /// Optional callback invoked when the user taps the clear/reset action button.
  final VoidCallback? onClear;

  /// Label for the clear/reset button when [onClear] is provided.
  final String clearButtonLabel;

  /// Padding around the empty state content.
  final EdgeInsetsGeometry padding;

  const LocalSearchEmptyState({
    super.key,
    this.query,
    this.title = 'No results found',
    this.subtitle,
    this.icon,
    this.onClear,
    this.clearButtonLabel = 'Clear search & filters',
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmedQuery = query?.trim() ?? '';
    final resolvedSubtitle = subtitle ??
        (trimmedQuery.isNotEmpty
            ? 'No items matched "$trimmedQuery". Try checking for typos or clearing filters.'
            : 'No items match the current filters.');

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon ??
                Icon(
                  Icons.search_off_rounded,
                  size: 56,
                  color: theme.colorScheme.outline,
                ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              resolvedSubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(clearButtonLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reactive widget that handles loading, empty state, and result rendering for a [SearchResponse].
class LocalSearchResultBuilder<T> extends StatelessWidget {
  /// The latest search response from [FlutterLocalSearch.search].
  final SearchResponse<T>? response;

  /// Whether a search or indexing operation is currently in progress.
  final bool isLoading;

  /// Builder invoked for each [SearchHit] when results are present.
  final Widget Function(BuildContext context, SearchHit<T> hit, int index) itemBuilder;

  /// Optional custom widget shown while [isLoading] is true.
  final WidgetBuilder? loadingBuilder;

  /// Optional custom widget shown when [response] is empty (`response.isEmpty`).
  final Widget Function(BuildContext context, String query)? emptyBuilder;

  /// Passed to the default [LocalSearchEmptyState] when [emptyBuilder] is omitted.
  final VoidCallback? onClear;

  /// Padding applied to the underlying [ListView].
  final EdgeInsetsGeometry? listPadding;

  const LocalSearchResultBuilder({
    super.key,
    required this.response,
    required this.itemBuilder,
    this.isLoading = false,
    this.loadingBuilder,
    this.emptyBuilder,
    this.onClear,
    this.listPadding,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator());
    }

    final current = response;
    if (current == null || current.isEmpty) {
      final q = current?.query ?? '';
      return emptyBuilder?.call(context, q) ??
          LocalSearchEmptyState(query: q, onClear: onClear);
    }

    return ListView.builder(
      padding: listPadding,
      itemCount: current.hits.length,
      itemBuilder: (context, index) => itemBuilder(context, current.hits[index], index),
    );
  }
}
