import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_search/src/models/search_filter.dart';
import 'package:flutter_local_search/src/storage/memory_storage.dart';
import 'package:flutter_local_search/src/storage/sqlite_storage.dart';
import 'package:flutter_local_search/src/storage/storage_adapter.dart';
import 'package:flutter_local_search/src/storage/storage_records.dart';

void main() {
  group('Storage Adapters', () {
    final adapters = <String, StorageAdapter Function()>{
      'MemoryStorage': () => MemoryStorage(),
      'SqliteStorage': () => SqliteStorage.inMemory(),
    };

    for (final entry in adapters.entries) {
      group(entry.key, () {
        late StorageAdapter storage;

        setUp(() async {
          storage = entry.value();
          await storage.open();
        });

        tearDown(() async {
          await storage.close();
        });

        test('saveBatch and getDocument works correctly', () async {
          final doc = DocumentRecord(
            docId: 'doc_1',
            payloadJson: jsonEncode({'id': 'doc_1', 'name': 'MacBook Pro'}),
            structuredData: {'price': 1999, 'inStock': true, 'brand': 'Apple'},
            fieldLengths: {'name': 2},
          );

          final posting1 = PostingRecord(
            term: 'macbook',
            docId: 'doc_1',
            field: 'name',
            termFrequency: 1,
            positions: [0],
          );
          final posting2 = PostingRecord(
            term: 'pro',
            docId: 'doc_1',
            field: 'name',
            termFrequency: 1,
            positions: [1],
          );

          final facet = FacetRecord(field: 'brand', value: 'Apple', docId: 'doc_1');

          await storage.saveBatch(
            documents: [doc],
            postings: [posting1, posting2],
            facets: [facet],
          );

          expect(await storage.getDocumentCount(), 1);

          final fetched = await storage.getDocument('doc_1');
          expect(fetched, isNotNull);
          expect(fetched!.docId, 'doc_1');
          expect(fetched.structuredData['price'], 1999);
          expect(fetched.structuredData['inStock'], true);

          final postings = await storage.getPostingsForTerm('macbook');
          expect(postings.length, 1);
          expect(postings.first.docId, 'doc_1');
          expect(postings.first.positions, [0]);

          final prefixPostings = await storage.getPostingsForPrefix('mac');
          expect(prefixPostings.length, 1);
          expect(prefixPostings.first.term, 'macbook');

          final facetCounts = await storage.aggregateFacets(facetFields: ['brand']);
          expect(facetCounts['brand']?['Apple'], 1);
        });

        test('filterDocIds evaluates ranges, equals, and boolean filters', () async {
          final docs = [
            DocumentRecord(
              docId: 'd1',
              payloadJson: '{}',
              structuredData: {'price': 100, 'brand': 'Apple', 'inStock': true},
              fieldLengths: {},
            ),
            DocumentRecord(
              docId: 'd2',
              payloadJson: '{}',
              structuredData: {'price': 250, 'brand': 'Samsung', 'inStock': false},
              fieldLengths: {},
            ),
            DocumentRecord(
              docId: 'd3',
              payloadJson: '{}',
              structuredData: {'price': 500, 'brand': 'Apple', 'inStock': false},
              fieldLengths: {},
            ),
          ];

          await storage.saveBatch(documents: docs, postings: [], facets: []);

          // Filter by brand == 'Apple'
          final appleDocs = await storage.filterDocIds([SearchFilter.equals('brand', 'Apple')]);
          expect(appleDocs, containsAll(['d1', 'd3']));
          expect(appleDocs.contains('d2'), isFalse);

          // Filter by range price <= 300 AND inStock == true
          final inStockBudget = await storage.filterDocIds([
            SearchFilter.range('price', max: 300),
            SearchFilter.boolean('inStock', true),
          ]);
          expect(inStockBudget, {'d1'});
        });

        test('deleteDocument cleans up documents, postings, and facets', () async {
          final doc = DocumentRecord(
            docId: 'doc_del',
            payloadJson: '{}',
            structuredData: {'brand': 'Sony'},
            fieldLengths: {},
          );
          final posting = PostingRecord(
            term: 'sony',
            docId: 'doc_del',
            field: 'name',
            termFrequency: 1,
            positions: [0],
          );
          final facet = FacetRecord(field: 'brand', value: 'Sony', docId: 'doc_del');

          await storage.saveBatch(
            documents: [doc],
            postings: [posting],
            facets: [facet],
          );

          expect(await storage.getDocumentCount(), 1);
          expect(await storage.getPostingsForTerm('sony'), isNotEmpty);

          await storage.deleteDocument('doc_del');

          expect(await storage.getDocumentCount(), 0);
          expect(await storage.getPostingsForTerm('sony'), isEmpty);
          final facetCounts = await storage.aggregateFacets(facetFields: ['brand']);
          expect(facetCounts['brand']?['Sony'], isNull);
        });
      });
    }
  });
}
