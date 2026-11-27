import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_search/flutter_local_search.dart';

class Product {
  final String id;
  final String name;
  final String description;
  final String brand;
  final double price;
  final bool inStock;

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.brand,
    required this.price,
    required this.inStock,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'brand': brand,
        'price': price,
        'inStock': inStock,
      };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        brand: json['brand'] as String,
        price: (json['price'] as num).toDouble(),
        inStock: json['inStock'] as bool,
      );
}

void main() {
  group('FlutterLocalSearch Core Engine', () {
    late FlutterLocalSearch<Product> search;

    final sampleProducts = [
      Product(
        id: 'p1',
        name: 'Apple iPhone 15 Pro',
        description: 'Titanium design with A17 Pro chip and 48MP camera',
        brand: 'Apple',
        price: 999.0,
        inStock: true,
      ),
      Product(
        id: 'p2',
        name: 'Samsung Galaxy S24 Ultra',
        description: 'Galaxy AI with Snapdragon 8 Gen 3 and 200MP camera',
        brand: 'Samsung',
        price: 1199.0,
        inStock: true,
      ),
      Product(
        id: 'p3',
        name: 'Apple MacBook Pro 16',
        description: 'M3 Max laptop for power users and developers',
        brand: 'Apple',
        price: 2499.0,
        inStock: false,
      ),
      Product(
        id: 'p4',
        name: 'Google Pixel 8 Pro',
        description: 'Google Tensor G3 smartphone with advanced computational photography',
        brand: 'Google',
        price: 899.0,
        inStock: true,
      ),
    ];

    setUp(() async {
      search = FlutterLocalSearch<Product>(
        indexName: 'products_test',
        id: (p) => p.id,
        fields: (p) => {
          'name': SearchField.text(p.name, weight: 3.0),
          'description': SearchField.text(p.description, weight: 1.0),
          'brand': SearchField.facet(p.brand, weight: 2.0),
          'price': SearchField.number(p.price),
          'inStock': SearchField.boolean(p.inStock),
        },
        toJson: (p) => p.toJson(),
        fromJson: (json) => Product.fromJson(json),
        storage: SqliteStorage.inMemory(),
      );

      await search.initialize();
      await search.indexAll(sampleProducts);
    });

    tearDown(() async {
      await search.close();
    });

    test('exact search matches target product and scores accurately', () async {
      final res = await search.search('iPhone');
      expect(res.totalHits, 1);
      expect(res.hits.first.id, 'p1');
      expect(res.hits.first.item.name, 'Apple iPhone 15 Pro');
      expect(res.hits.first.score, greaterThan(0));
    });

    test('field boosting prioritizes title match over description match', () async {
      // Both p1 and p3 are Apple, but searching 'Apple' ranks them
      final res = await search.search('camera');
      // Both p1 and p2 have 'camera' in description
      expect(res.totalHits, 2);
      expect(res.hits.map((h) => h.id), containsAll(['p1', 'p2']));
    });

    test('prefix search finds products with incomplete typing', () async {
      final res = await search.search(
        'sam',
        options: const SearchOptions(prefix: true),
      );
      expect(res.totalHits, 1);
      expect(res.hits.first.id, 'p2');
      expect(res.hits.first.item.brand, 'Samsung');
    });

    test('fuzzy search tolerates typos in query', () async {
      // Typo 'galxy' instead of 'galaxy'
      final res = await search.search(
        'galxy',
        options: const SearchOptions(fuzzy: true, maxEditDistance: 2),
      );
      expect(res.totalHits, 1);
      expect(res.hits.first.id, 'p2');
    });

    test('highlights matching terms in results', () async {
      final res = await search.search(
        'titanium',
        options: const SearchOptions(highlight: true),
      );
      expect(res.totalHits, 1);
      final highlights = res.hits.first.highlights;
      expect(highlights['description'], isNotNull);
      expect(highlights['description']!.first, contains('<mark>Titanium</mark>'));
    });

    test('faceted filtering by equals and range', () async {
      // Apple products with price < 1500
      final res = await search.search(
        '',
        filters: [
          SearchFilter.equals('brand', 'Apple'),
          SearchFilter.range('price', max: 1500),
        ],
        facets: ['brand'],
      );

      expect(res.totalHits, 1);
      expect(res.hits.first.id, 'p1');
      expect(res.facetCounts['brand']?['Apple'], 1);
    });

    test('live facet counting aggregates across all matches', () async {
      final res = await search.search(
        '',
        facets: ['brand'],
      );

      expect(res.totalHits, 4);
      expect(res.facetCounts['brand']?['Apple'], 2);
      expect(res.facetCounts['brand']?['Samsung'], 1);
      expect(res.facetCounts['brand']?['Google'], 1);
    });

    test('incremental upsert and remove update search results immediately', () async {
      final newProduct = Product(
        id: 'p5',
        name: 'OnePlus 12',
        description: 'Flagship killer with Hasselblad camera',
        brand: 'OnePlus',
        price: 799.0,
        inStock: true,
      );

      await search.upsert(newProduct);

      var res = await search.search('OnePlus');
      expect(res.totalHits, 1);
      expect(res.hits.first.id, 'p5');

      await search.remove('p5');

      res = await search.search('OnePlus');
      expect(res.totalHits, 0);
    });
  });

  group('Dummy API JSON Direct Search (FlutterLocalSearch.fromJsonList)', () {
    test('indexes and searches raw API JSON response without custom model', () async {
      // Simulating a raw JSON payload from an API like dummyjson.com/products
      final dummyApiJson = [
        {
          'id': 101,
          'title': 'Wireless Noise-Canceling Headphones',
          'description': 'Over-ear headphones with 40-hour battery life and quick charging',
          'category': 'audio',
          'price': 149.99,
          'rating': 4.7,
          'inStock': true,
        },
        {
          'id': 102,
          'title': 'Mechanical Gaming Keyboard',
          'description': 'RGB backlit mechanical keyboard with tactile blue switches',
          'category': 'peripherals',
          'price': 89.50,
          'rating': 4.5,
          'inStock': true,
        },
        {
          'id': 103,
          'title': '4K Ultra HD Monitor 27-inch',
          'description': 'IPS display with HDR400 and USB-C connectivity for Mac and PC',
          'category': 'monitors',
          'price': 349.00,
          'rating': 4.8,
          'inStock': false,
        },
      ];

      final apiSearch = FlutterLocalSearch.fromJsonList(
        indexName: 'dummy_api_products',
        facetFields: ['category'],
        storage: MemoryStorage(),
      );

      await apiSearch.initialize();
      await apiSearch.indexAll(dummyApiJson);

      // 1. Search by text
      final textRes = await apiSearch.search('keyboard');
      expect(textRes.totalHits, 1);
      expect(textRes.hits.first.item['id'], 102);

      // 2. Search with filters
      final filterRes = await apiSearch.search(
        '',
        filters: [
          SearchFilter.range('price', min: 100, max: 200),
          SearchFilter.boolean('inStock', true),
        ],
        facets: ['category'],
      );
      expect(filterRes.totalHits, 1);
      expect(filterRes.hits.first.item['id'], 101);
      expect(filterRes.facetCounts['category']?['audio'], 1);

      // 3. Typo fuzzy search
      final typoRes = await apiSearch.search(
        'headfones', // Typo
        options: const SearchOptions(fuzzy: true, maxEditDistance: 2),
      );
      expect(typoRes.totalHits, 1);
      expect(typoRes.hits.first.item['id'], 101);

      await apiSearch.close();
    });
  });
}
