enum FieldType {
  text,
  facet,
  number,
  boolean,
}

/// Defines a searchable, filterable, or facetable field on an entity.
class SearchField {
  final FieldType type;
  final dynamic value;
  final double weight;

  const SearchField._({
    required this.type,
    required this.value,
    this.weight = 1.0,
  });

  /// Full-text searchable field with optional relevance boosting weight.
  factory SearchField.text(String? value, {double weight = 1.0}) {
    return SearchField._(
      type: FieldType.text,
      value: value ?? '',
      weight: weight,
    );
  }

  /// Searchable full-text and categorical facet field with optional weight.
  factory SearchField.facet(String? value, {double weight = 1.0}) {
    return SearchField._(
      type: FieldType.facet,
      value: value ?? '',
      weight: weight,
    );
  }

  /// Numeric field for range queries (<, >, <=, >=, between).
  factory SearchField.number(num? value) {
    return SearchField._(
      type: FieldType.number,
      value: value ?? 0,
      weight: 1.0,
    );
  }

  /// Boolean field for exact flag filtering.
  factory SearchField.boolean(bool? value) {
    return SearchField._(
      type: FieldType.boolean,
      value: value ?? false,
      weight: 1.0,
    );
  }

  bool get isTextual => type == FieldType.text || type == FieldType.facet;
  bool get isFacetable => type == FieldType.facet;
  bool get isNumeric => type == FieldType.number;
  bool get isBoolean => type == FieldType.boolean;
}
