import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../models/search_response.dart';

/// Production-ready empty state widget shown when no items match a search query or filters.
///
/// Built purely on `package:flutter/widgets.dart` so it adapts cleanly to Material,
/// Cupertino, and custom widget trees without extra package dependencies.
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
    final baseStyle = DefaultTextStyle.of(context).style;
    final foreground = baseStyle.color ?? const Color(0xFF1F2937);
    final muted = foreground.withValues(alpha: 0.65);
    final outline = foreground.withValues(alpha: 0.35);

    final trimmedQuery = query?.trim() ?? '';
    final resolvedSubtitle =
        subtitle ??
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
                CustomPaint(
                  size: const Size.square(56),
                  painter: _SearchOffIconPainter(color: muted),
                ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: baseStyle.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              resolvedSubtitle,
              textAlign: TextAlign.center,
              style: baseStyle.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: muted,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(height: 16),
              _ClearFiltersButton(
                label: clearButtonLabel,
                textStyle: baseStyle.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: foreground,
                ),
                borderColor: outline,
                onTap: onClear!,
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
  final Widget Function(BuildContext context, SearchHit<T> hit, int index)
  itemBuilder;

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
      if (loadingBuilder != null) {
        return loadingBuilder!(context);
      }
      final baseStyle = DefaultTextStyle.of(context).style;
      final muted = (baseStyle.color ?? const Color(0xFF1F2937)).withValues(
        alpha: 0.65,
      );
      return Center(
        child: Text(
          'Searching...',
          style: baseStyle.copyWith(fontSize: 14, color: muted),
        ),
      );
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
      itemBuilder: (context, index) =>
          itemBuilder(context, current.hits[index], index),
    );
  }
}

class _ClearFiltersButton extends StatelessWidget {
  final String label;
  final TextStyle textStyle;
  final Color borderColor;
  final VoidCallback onTap;

  const _ClearFiltersButton({
    required this.label,
    required this.textStyle,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(label, style: textStyle),
          ),
        ),
      ),
    );
  }
}

/// Paints a crisp magnifying glass with a diagonal slash without Material icon fonts.
class _SearchOffIconPainter extends CustomPainter {
  final Color color;

  const _SearchOffIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width * 0.42, size.height * 0.42);
    final radius = size.width * 0.25;
    canvas.drawCircle(center, radius, stroke);

    final handleStart =
        center +
        Offset(math.cos(math.pi / 4) * radius, math.sin(math.pi / 4) * radius);
    final handleEnd = Offset(size.width * 0.84, size.height * 0.84);
    canvas.drawLine(handleStart, handleEnd, stroke);

    // Diagonal slash across the lens
    canvas.drawLine(
      Offset(size.width * 0.16, size.height * 0.68),
      Offset(size.width * 0.68, size.height * 0.16),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_SearchOffIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
