import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_local_search/flutter_local_search.dart';

void main() {
  group('Disk SQLite Persistence, Cold-Start & Background Isolate', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fls_persistence_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('persists index, field weights, and survives cold-start reopen with IsolateWorker',
        () async {
      final dbPath = p.join(tempDir.path, 'cold_start.db');

      // Session 1: Create, index, and close
      final engine1 = FlutterLocalSearch.fromJsonList(
        indexName: 'cold_start',
        customDbPath: dbPath,
        facetFields: ['category'],
        fieldWeights: {'title': 4.0, 'body': 1.0},
        useIsolate: true,
      );

      await engine1.initialize();
      await engine1.indexAll([
        {
          'id': 'doc1',
          'title': 'Dart Concurrency with Isolates',
          'body': 'Background worker processing.',
          'category': 'dart',
          'views': 150,
        },
        {
          'id': 'doc2',
          'title': 'Flutter Animations Guide',
          'body': 'Learn dart isolate animations and custom painters.',
          'category': 'flutter',
          'views': 300,
        },
      ]);
      await engine1.close();

      // Session 2: Reopen cold from disk in a fresh instance & isolate
      final engine2 = FlutterLocalSearch.fromJsonList(
        indexName: 'cold_start',
        customDbPath: dbPath,
        facetFields: ['category'],
        useIsolate: true,
      );
      await engine2.initialize();

      // Verify persisted field weights keep title match 'doc1' ranked above body match 'doc2'
      final res = await engine2.search('isolates', options: const SearchOptions(fuzzy: true));
      expect(res.totalHits, 2);
      expect(res.hits.first.id, 'doc1');

      // Incremental upsert
      await engine2.upsert({
        'id': 'doc3',
        'title': 'SQLite WAL Mode Deep Dive',
        'body': 'Fast concurrent local storage.',
        'category': 'database',
        'views': 500,
      });

      final walRes = await engine2.search('SQLite');
      expect(walRes.totalHits, 1);
      expect(walRes.hits.first.id, 'doc3');

      // Incremental remove cleans up doc and updates counts
      await engine2.remove('doc3');
      final afterRemove = await engine2.search('SQLite');
      expect(afterRemove.isEmpty, isTrue);

      await engine2.close();
    });

    test('strings() factory produces deterministic IDs across restarts', () async {
      final dbPath = p.join(tempDir.path, 'strings_persist.db');

      final s1 = FlutterLocalSearch.strings(
        indexName: 'tags',
        customDbPath: dbPath,
        useIsolate: false,
      );
      await s1.initialize();
      await s1.indexAll(['flutter', 'dart', 'sqlite']);
      await s1.close();

      final s2 = FlutterLocalSearch.strings(
        indexName: 'tags',
        customDbPath: dbPath,
        useIsolate: false,
      );
      await s2.initialize();
      // Upserting the same string must overwrite same deterministic docId, not duplicate!
      await s2.upsert('flutter');
      final res = await s2.search('flutter');
      expect(res.totalHits, 1);
      await s2.close();
    });
  });
}
