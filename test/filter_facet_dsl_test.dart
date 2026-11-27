import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_search/flutter_local_search.dart';

void main() {
  group('Filters, Facets, Query DSL & Empty State', () {
    late FlutterLocalSearch<Map<String, dynamic>> search;

    setUp(() async {
      search = FlutterLocalSearch.fromJsonList(
        indexName: 'dsl_test',
        facetFields: ['brand', 'category'],
        fieldWeights: {'name': 3.0},
        storage: SqliteStorage.inMemory(),
      );
      await search.initialize();

      await search.indexAll([
        {
          'id': '1',
          'name': 'Apple iPhone 15',
          'description': 'Smartphone with A16 chip',
          'brand': 'Apple',
          'category': 'phones',
          'price': 799,
          'inStock': true,
        },
        {
          'id': '2',
          'name': 'Apple MacBook Air',
          'description': 'Lightweight laptop with M3 chip',
          'brand': 'Apple',
          'category': 'laptops',
          'price': 1099,
          'inStock': true,
        },
        {
          'id': '3',
          'name': 'Samsung Galaxy Book',
          'description': 'Windows laptop with AMOLED display',
          'brand': 'Samsung',
          'category': 'laptops',
          'price': 1299,
          'inStock': false,
        },
      ]);
    });

    tearDown(() async => search.close());

    test('boolean query string supports AND, OR, NOT and -exclusion', () async {
      // Apple -MacBook excludes MacBook Air
      final excluded = await search.search('Apple -MacBook');
      expect(excluded.totalHits, 1);
      expect(excluded.hits.first.id, '1');

      // Samsung OR iPhone matches both 1 and 3
      final orRes = await search.search('Samsung OR iPhone');
      expect(orRes.totalHits, 2);
      expect(orRes.hits.map((h) => h.id), containsAll(['1', '3']));

      // laptop AND AMOLED matches only 3
      final andRes = await search.search('laptop AND AMOLED');
      expect(andRes.totalHits, 1);
      expect(andRes.hits.first.id, '3');
    });

    test('fluent SearchQuery DSL chains match, andNot, and filters', () async {
      final query = SearchQuery.match('laptop')
          .andNot(SearchQuery.match('Samsung'))
          .where(SearchFilter.gt('price', 900))
          .where(SearchFilter.inList('brand', ['Apple', 'Dell']));

      final res = await search.searchQuery(query, facets: ['brand', 'category']);
      expect(res.totalHits, 1);
      expect(res.hits.first.id, '2');
      expect(res.facetCounts['brand']?['Apple'], 1);
      expect(res.facetCounts['category']?['laptops'], 1);
    });

    test('SearchResponse exposes clean empty state when no product matches', () async {
      final res = await search.search('nonexistent_product_xyz', facets: ['brand']);
      expect(res.isEmpty, isTrue);
      expect(res.isNotEmpty, isFalse);
      expect(res.totalHits, 0);
      expect(res.hits, isEmpty);
      expect(res.query, 'nonexistent_product_xyz');
    });

    testWidgets('LocalSearchResultBuilder renders LocalSearchEmptyState on empty response',
        (tester) async {
      bool cleared = false;
      final emptyResponse = SearchResponse<String>(
        query: 'rolex watch',
        hits: const [],
        totalHits: 0,
        queryTimeMs: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalSearchResultBuilder<String>(
              response: emptyResponse,
              itemBuilder: (_, hit, _) => Text(hit.item),
              onClear: () => cleared = true,
            ),
          ),
        ),
      );

      expect(find.text('No results found'), findsOneWidget);
      expect(find.textContaining('rolex watch'), findsOneWidget);

      await tester.tap(find.text('Clear search & filters'));
      expect(cleared, isTrue);
    });
  });
}
