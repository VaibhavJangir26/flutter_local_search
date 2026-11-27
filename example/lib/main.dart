import 'dart:io';

import 'package:flutter_local_search/flutter_local_search.dart';

/// Example product model — swap this for any Dart model in your app
/// (Notes, Contacts, Articles, Tasks, Catalog Items, etc.).
class Product {
  final String id;
  final String name;
  final String description;
  final String brand;
  final String category;
  final double price;
  final bool inStock;

  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.brand,
    required this.category,
    required this.price,
    required this.inStock,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'brand': brand,
        'category': category,
        'price': price,
        'inStock': inStock,
      };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        brand: json['brand'] as String,
        category: json['category'] as String,
        price: (json['price'] as num).toDouble(),
        inStock: json['inStock'] as bool,
      );
}

Future<void> main() async {
  // 1. Initialize the search engine (omit `storage` in Flutter apps to use
  //    persistent on-device SQLite WAL storage in a background Isolate).
  final search = FlutterLocalSearch<Product>(
    indexName: 'products_example',
    storage: MemoryStorage(),
    useIsolate: false,
    id: (p) => p.id,
    fields: (p) => {
      'name': SearchField.text(p.name, weight: 3.0), // 3x BM25F title boost
      'description': SearchField.text(p.description),
      'brand': SearchField.facet(p.brand, weight: 2.0), // Searchable + facet
      'category': SearchField.facet(p.category),
      'price': SearchField.number(p.price), // Numeric range filtering
      'inStock': SearchField.boolean(p.inStock),
    },
    toJson: (p) => p.toJson(),
    fromJson: Product.fromJson,
  );

  await search.initialize();

  // 2. Index a batch of products
  await search.indexAll(const [
    Product(
      id: 'p1',
      name: 'Apple iPhone 15 Pro',
      description: 'Flagship smartphone with titanium design and A17 Pro chip.',
      brand: 'Apple',
      category: 'Smartphones',
      price: 999,
      inStock: true,
    ),
    Product(
      id: 'p2',
      name: 'Apple MacBook Air M3',
      description: 'Ultra-thin laptop with 18-hour battery life.',
      brand: 'Apple',
      category: 'Laptops',
      price: 1099,
      inStock: true,
    ),
    Product(
      id: 'p3',
      name: 'Samsung Galaxy S24 Ultra',
      description: 'Titanium smartphone with S Pen and 200MP camera.',
      brand: 'Samsung',
      category: 'Smartphones',
      price: 1199,
      inStock: false,
    ),
  ]);

  // 3. Search with typo tolerance, prefix autocomplete, filters, facets & highlights
  final response = await search.search(
    'titnium', // Typo matches "titanium" via Damerau-Levenshtein fuzzy search
    options: const SearchOptions(
      fuzzy: true,
      prefix: true,
      highlight: true,
    ),
    filters: [
      SearchFilter.boolean('inStock', true),
      SearchFilter.range('price', min: 500, max: 1500),
    ],
    facets: ['brand', 'category'],
  );

  stdout.writeln(
    'Found ${response.totalHits} matching products in ${response.queryTimeMs} ms',
  );
  stdout.writeln('Brand facet counts: ${response.facetCounts['brand']}');

  for (final hit in response.hits) {
    stdout.writeln(
      '- ${hit.item.name} (\$${hit.item.price}) | BM25F score: ${hit.score.toStringAsFixed(2)}',
    );
    if (hit.highlights['description'] != null) {
      stdout.writeln('  Snippet: ${hit.highlights['description']!.first}');
    }
  }

  // 4. Clean empty-state check when nothing matches
  final empty = await search.search('nonexistent_item');
  if (empty.isEmpty) {
    stdout.writeln('No products matched "${empty.query}".');
  }

  await search.close();
}

