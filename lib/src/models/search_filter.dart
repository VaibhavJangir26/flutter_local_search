enum FilterOperator {
  equals,
  inList,
  range,
  gt,
  gte,
  lt,
  lte,
  boolean,
}

/// Filter condition applied to structured/numeric/facet fields.
class SearchFilter {
  final String field;
  final FilterOperator operator;
  final dynamic value;
  final num? min;
  final num? max;

  const SearchFilter._({
    required this.field,
    required this.operator,
    this.value,
    this.min,
    this.max,
  });

  /// Exact equality filter for strings, numbers, or booleans.
  factory SearchFilter.equals(String field, dynamic value) {
    return SearchFilter._(
      field: field,
      operator: FilterOperator.equals,
      value: value,
    );
  }

  /// Matches any value in the provided list.
  factory SearchFilter.inList(String field, List<dynamic> values) {
    return SearchFilter._(
      field: field,
      operator: FilterOperator.inList,
      value: values,
    );
  }

  /// Numeric range filter with optional min (inclusive) and max (inclusive).
  factory SearchFilter.range(String field, {num? min, num? max}) {
    return SearchFilter._(
      field: field,
      operator: FilterOperator.range,
      min: min,
      max: max,
    );
  }

  /// Greater than filter.
  factory SearchFilter.gt(String field, num value) {
    return SearchFilter._(
      field: field,
      operator: FilterOperator.gt,
      value: value,
    );
  }

  /// Greater than or equal to filter.
  factory SearchFilter.gte(String field, num value) {
    return SearchFilter._(
      field: field,
      operator: FilterOperator.gte,
      value: value,
    );
  }

  /// Less than filter.
  factory SearchFilter.lt(String field, num value) {
    return SearchFilter._(
      field: field,
      operator: FilterOperator.lt,
      value: value,
    );
  }

  /// Less than or equal to filter.
  factory SearchFilter.lte(String field, num value) {
    return SearchFilter._(
      field: field,
      operator: FilterOperator.lte,
      value: value,
    );
  }

  /// Exact boolean filter.
  factory SearchFilter.boolean(String field, bool value) {
    return SearchFilter._(
      field: field,
      operator: FilterOperator.boolean,
      value: value,
    );
  }

  /// Evaluates whether a structured document value matches this filter.
  bool matches(dynamic docValue) {
    if (docValue == null) return false;

    switch (operator) {
      case FilterOperator.equals:
        return docValue.toString().toLowerCase() == value.toString().toLowerCase();

      case FilterOperator.inList:
        if (value is! Iterable) return false;
        final docStr = docValue.toString().toLowerCase();
        return (value as Iterable).any((v) => v.toString().toLowerCase() == docStr);

      case FilterOperator.range:
        if (docValue is! num) return false;
        if (min != null && docValue < min!) return false;
        if (max != null && docValue > max!) return false;
        return true;

      case FilterOperator.gt:
        if (docValue is! num || value is! num) return false;
        return docValue > (value as num);

      case FilterOperator.gte:
        if (docValue is! num || value is! num) return false;
        return docValue >= (value as num);

      case FilterOperator.lt:
        if (docValue is! num || value is! num) return false;
        return docValue < (value as num);

      case FilterOperator.lte:
        if (docValue is! num || value is! num) return false;
        return docValue <= (value as num);

      case FilterOperator.boolean:
        return docValue == value;
    }
  }
}
