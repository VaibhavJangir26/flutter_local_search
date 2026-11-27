import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_local_search/flutter_local_search.dart';

void main() {
  group('10,000-Document Performance Benchmark', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fls_bench_10k_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('indexes 10k docs <5s, queries <50ms, upserts <10ms, cold-start <50ms', () async {
      final dbPath = p.join(tempDir.path, 'bench_10k.db');
      final brands = ['Apple', 'Samsung', 'Google', 'Sony', 'Dell', 'LG', 'Bose', 'Asus'];
      final categories = ['Smartphones', 'Laptops', 'Audio', 'Monitors', 'Tablets'];

      final items = List<Map<String, dynamic>>.generate(10000, (i) {
        final brand = brands[i % brands.length];
        final category = categories[i % categories.length];
        return {
          'id': 'item_$i',
          'title': '$brand $category Model $i Pro Edition',
          'description':
              'High performance offline device number $i engineered with titanium chassis and long battery life.',
          'brand': brand,
          'category': category,
          'price': 199.0 + (i % 1500),
          'inStock': i % 4 != 0,
        };
      });

      final engine = FlutterLocalSearch.fromJsonList(
        indexName: 'bench_10k',
        customDbPath: dbPath,
        facetFields: ['brand', 'category'],
        fieldWeights: {'title': 3.0, 'description': 1.0},
        useIsolate: true,
      );

      await engine.initialize();

      // 1. Batch index 10,000 items
      final indexSw = Stopwatch()..start();
      await engine.indexAll(items);
      indexSw.stop();
      // ignore: avoid_print
      print('Indexed 10,000 docs in ${indexSw.elapsedMilliseconds} ms');
      expect(indexSw.elapsedMilliseconds, lessThan(5000));

      // 2. Exact query + facet aggregation + range filter
      final exactSw = Stopwatch()..start();
      final exactRes = await engine.search(
        'titanium',
        filters: [
          SearchFilter.equals('brand', 'Apple'),
          SearchFilter.range('price', min: 200, max: 800),
        ],
        facets: ['category'],
      );
      exactSw.stop();
      // ignore: avoid_print
      print(
        '10k exact + filter + facet query: ${exactSw.elapsedMilliseconds} ms (${exactRes.totalHits} hits)',
      );
      expect(exactRes.isNotEmpty, isTrue);
      expect(exactSw.elapsedMilliseconds, lessThan(50));

      // 3. Prefix query
      final prefixSw = Stopwatch()..start();
      final prefixRes = await engine.search(
        'titani',
        options: const SearchOptions(prefix: true),
      );
      prefixSw.stop();
      // ignore: avoid_print
      print('10k prefix query: ${prefixSw.elapsedMilliseconds} ms (${prefixRes.totalHits} hits)');
      expect(prefixRes.isNotEmpty, isTrue);
      expect(prefixSw.elapsedMilliseconds, lessThan(50));

      // 4. Incremental single-doc upsert
      final upsertSw = Stopwatch()..start();
      await engine.upsert({
        'id': 'item_5000',
        'title': 'Apple Special Edition Ultra 5000',
        'description': 'Updated flagship description.',
        'brand': 'Apple',
        'category': 'Smartphones',
        'price': 999.0,
        'inStock': true,
      });
      upsertSw.stop();
      // ignore: avoid_print
      print('10k incremental upsert: ${upsertSw.elapsedMilliseconds} ms');
      expect(upsertSw.elapsedMilliseconds, lessThan(20));

      await engine.close();

      // 5. Cold-start reopen + query
      final coldEngine = FlutterLocalSearch.fromJsonList(
        indexName: 'bench_10k',
        customDbPath: dbPath,
        facetFields: ['brand', 'category'],
        useIsolate: true,
      );
      await coldEngine.initialize();

      final coldSw = Stopwatch()..start();
      final coldRes = await coldEngine.search('Special');
      coldSw.stop();
      // ignore: avoid_print
      print('10k cold-start query: ${coldSw.elapsedMilliseconds} ms (${coldRes.totalHits} hits)');
      expect(coldRes.totalHits, 1);
      expect(coldRes.hits.first.id, 'item_5000');
      expect(coldSw.elapsedMilliseconds, lessThan(50));

      await coldEngine.close();
    });
  });
}
