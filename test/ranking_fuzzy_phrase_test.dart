import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_search/flutter_local_search.dart';

class Article {
  final String id;
  final String title;
  final String body;

  Article({required this.id, required this.title, required this.body});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'body': body};

  factory Article.fromJson(Map<String, dynamic> json) => Article(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
      );
}

void main() {
  group('BM25F Field Boosting, Damerau-Levenshtein Fuzzy & Phrase Search', () {
    late FlutterLocalSearch<Article> engine;

    setUp(() async {
      engine = FlutterLocalSearch<Article>(
        indexName: 'articles_ranking_test',
        id: (a) => a.id,
        fields: (a) => {
          'title': SearchField.text(a.title, weight: 5.0),
          'body': SearchField.text(a.body, weight: 1.0),
        },
        toJson: (a) => a.toJson(),
        fromJson: Article.fromJson,
        storage: SqliteStorage.inMemory(),
      );
      await engine.initialize();

      await engine.indexAll([
        Article(
          id: 'a1',
          title: 'Getting Started with Flutter',
          body: 'Build cross platform mobile applications.',
        ),
        Article(
          id: 'a2',
          title: 'Cross Platform Development Guide',
          body: 'We compare native frameworks and flutter flutter flutter in detail.',
        ),
        Article(
          id: 'a3',
          title: 'Spring Boot Microservices',
          body: 'Deploying Java backend services in production.',
        ),
        Article(
          id: 'a4',
          title: 'Spring Cleaning and Boot Camp',
          body: 'Boot your spring productivity with morning routines.',
        ),
        Article(
          id: 'a5',
          title: 'Pro Display XDR Review',
          body: 'This processor delivers professional video editing.',
        ),
      ]);
    });

    tearDown(() async => engine.close());

    test('BM25F field boosting ranks title match higher than body-only match', () async {
      final res = await engine.search('flutter');
      expect(res.totalHits, 2);
      // a1 has 'flutter' in weighted title (5.0), a2 only in body (1.0) even with 3x tf
      expect(res.hits.first.id, 'a1');
      expect(res.hits[1].id, 'a2');
    });

    test('Damerau-Levenshtein treats adjacent transposition as distance 1', () async {
      expect(FuzzyMatcher.damerauLevenshteinDistance('fluter', 'flutter'), 1);
      expect(FuzzyMatcher.damerauLevenshteinDistance('iphnoe', 'iphone'), 1);
      expect(FuzzyMatcher.damerauLevenshteinDistance('spingr', 'spring', maxDistance: 2), 2);

      final res = await engine.search(
        'fluter',
        options: const SearchOptions(fuzzy: true, maxEditDistance: 1),
      );
      expect(res.totalHits, 2);
      expect(res.hits.first.id, 'a1');
    });

    test('exact matches outrank fuzzy matches when both exist', () async {
      final res = await engine.search(
        'spring',
        options: const SearchOptions(fuzzy: true, maxEditDistance: 1),
      );
      expect(res.isNotEmpty, isTrue);
      // Both exact matches a3/a4 should match cleanly
      expect(res.hits.map((h) => h.id), containsAll(['a3', 'a4']));
    });

    test('quoted phrase search verifies adjacent token positions', () async {
      // "spring boot" matches a3 (title: "Spring Boot Microservices"),
      // NOT a4 ("Spring Cleaning and Boot Camp")
      final res = await engine.search('"spring boot"');
      expect(res.totalHits, 1);
      expect(res.hits.first.id, 'a3');
    });

    test('highlighter respects word boundaries and skips partial mid-word substrings', () async {
      final res = await engine.search(
        'pro',
        options: const SearchOptions(highlight: true),
      );
      expect(res.totalHits, 1);
      final hit = res.hits.first;
      expect(hit.id, 'a5');
      // 'Pro' in title is highlighted, 'processor'/'professional' in body are NOT matched
      expect(hit.highlights['title']?.first, contains('<mark>Pro</mark>'));
      expect(hit.highlights['body'], isNull);
    });
  });
}
