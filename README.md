# flutter_local_search

[![pub package](https://img.shields.io/pub/v/flutter_local_search.svg)](https://pub.dev/packages/flutter_local_search)
[![pub points](https://img.shields.io/pub/points/flutter_local_search)](https://pub.dev/packages/flutter_local_search/score)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/vaibhavjangir/flutter_local_search/blob/main/LICENSE)
[![platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-lightgrey.svg)](https://pub.dev/packages/flutter_local_search)

An embedded, offline-first **full-text search engine for Flutter and Dart**—no backend, cloud API key, or internet connection required. Index any `List<T>`, raw JSON array, or `List<String>` on-device with **BM25F field-weighted ranking**, **typo-tolerant fuzzy search**, **prefix autocomplete**, **exact phrase queries**, **boolean Query DSL**, **faceted filtering**, **SQLite WAL persistence**, and **background Isolate execution**.

---

## When to Use `flutter_local_search`

Choose `flutter_local_search` when your Flutter or Dart app needs instant, smart client-side search over local or cached datasets—such as **notes & knowledge bases**, **contacts & directories**, **offline articles & documentation**, **task managers**, **patient/student records**, or **synced REST/GraphQL catalogs**—without paying for cloud search or blocking the UI thread.

### How It Compares

| Capability | `List.where` / `.contains()` | Raw SQLite (`LIKE` / FTS5) | Cloud (Algolia / Typesense) | `flutter_local_search` |
|---|---|---|---|---|
| **100% Offline / Zero Backend** | Yes | Yes | No (network + keys) | **Yes (embedded SQLite WAL)** |
| **Any Dart Model `List<T>`** | Manual loop | Manual SQL & schema | JSON over HTTP | **Typed `List<T>` + `fromJsonList`** |
| **Relevance Ranking (BM25F)** | None | Manual / basic weights | Yes | **Field-weighted BM25F** |
| **Typo-Tolerant Fuzzy Search** | None | None | Yes | **Damerau-Levenshtein (1-2 edits)** |
| **Search-As-You-Type Prefix** | `.startsWith()` | `GLOB` / prefix | Yes | **B-tree term range scan** |
| **Exact Phrase Proximity** | None | Complex SQL | Yes | **Quoted phrases + positional blobs** |
| **Facet Counts & Range Filters** | Manual grouping | Manual `GROUP BY` | Yes | **Live `facetCounts` + filters** |
| **UI Thread Safety (60/120 FPS)** | Main thread | Main thread unless wrapped | Network async | **Dedicated background `IsolateWorker`** |
| **Empty-State & Result Widgets** | None | None | Separate UI SDK | **`LocalSearchResultBuilder<T>` included** |

---

## Installation

```bash
flutter pub add flutter_local_search
```

```dart
import 'package:flutter_local_search/flutter_local_search.dart';
```

> **Requirements:** Dart `^3.12.0` · Flutter `>=3.29.0` · Works on iOS, Android, macOS, Windows, and Linux via SQLite WAL (plus `MemoryStorage` for pure in-memory or test usage).

---

## Quickstart (Domain-Agnostic)

`flutter_local_search` adapts to whatever data model your app already uses. Pick the setup style that fits your project:

### 1. Typed Model `FlutterLocalSearch<T>` (Recommended for Apps)

Example using a generic `Note` model—swap `Note` for `Contact`, `Article`, `Task`, `Book`, or any custom class:

```dart
class Note {
  final String id;
  final String title;
  final String body;
  final String folder;
  final int wordCount;
  final bool pinned;

  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.folder,
    required this.wordCount,
    required this.pinned,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'folder': folder,
        'wordCount': wordCount,
        'pinned': pinned,
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        folder: json['folder'] as String,
        wordCount: json['wordCount'] as int,
        pinned: json['pinned'] as bool,
      );
}

// 1. Configure your index once
final search = FlutterLocalSearch<Note>(
  indexName: 'notes',
  id: (note) => note.id,
  fields: (note) => {
    'title': SearchField.text(note.title, weight: 3.0), // 3x relevance boost
    'body': SearchField.text(note.body),
    'folder': SearchField.facet(note.folder, weight: 2.0), // Searchable + facetable
    'wordCount': SearchField.number(note.wordCount), // Numeric range filtering
    'pinned': SearchField.boolean(note.pinned), // Boolean filtering
  },
  toJson: (note) => note.toJson(),
  fromJson: Note.fromJson,
);

await search.initialize();

// 2. Index a batch in a single atomic SQLite WAL transaction
await search.indexAll(myNotes);

// 3. Search with typo tolerance, prefix autocomplete, highlights, filters & facets
final response = await search.search(
  'archtecture', // Typo matches "architecture"
  options: const SearchOptions(fuzzy: true, prefix: true, highlight: true),
  filters: [
    SearchFilter.equals('folder', 'Engineering'),
    SearchFilter.range('wordCount', min: 100, max: 2000),
  ],
  facets: ['folder', 'pinned'],
);

print('Found ${response.totalHits} matches in ${response.queryTimeMs} ms');
for (final hit in response.hits) {
  print('${hit.item.title} (score: ${hit.score.toStringAsFixed(2)})');
  print('Snippet: ${hit.highlights['body']?.first}');
}
```

### 2. Dynamic JSON Lists (`FlutterLocalSearch.fromJsonList`)

Index `List<Map<String, dynamic>>` directly from a REST API, local JSON file, or cache without writing model boilerplate:

```dart
final directorySearch = FlutterLocalSearch.fromJsonList(
  indexName: 'directory_records',
  facetFields: ['department', 'location'],
  fieldWeights: {'name': 3.0, 'bio': 1.0},
);

await directorySearch.initialize();
await directorySearch.indexAll(jsonRecords);

final res = await directorySearch.search(
  'engneer',
  options: const SearchOptions(fuzzy: true),
  facets: ['department'],
);
```

### 3. Plain String Lists (`FlutterLocalSearch.strings`)

For tags, cities, commands, categories, or recent search suggestions:

```dart
final topicSearch = FlutterLocalSearch.strings(indexName: 'topics');
await topicSearch.initialize();
await topicSearch.indexAll(['architecture', 'animations', 'accessibility', 'sqlite']);

final res = await topicSearch.search('archtect', options: const SearchOptions(fuzzy: true, prefix: true));
print(res.items); // ['architecture']
```

---

## Core Capabilities

### 1. Field-Weighted BM25F Relevance Ranking
Assign custom weights per field (`SearchField.text(value, weight: 3.0)` or `SearchField.facet(...)`). BM25F normalizes by field length and persists weights across restarts so important fields like `title` or `name` naturally outrank long body text.

### 2. Typo-Tolerant Fuzzy Search (Damerau-Levenshtein)
Handles substitutions, insertions, deletions, and **adjacent character transpositions** (`"fluter"` → `"flutter"`, `"recpie"` → `"recipe"`) as a single edit with length-window pruning and score decay (exact matches rank above 1-edit matches, which rank above 2-edit matches):

```dart
final res = await search.search(
  'algoritm',
  options: const SearchOptions(fuzzy: true, maxEditDistance: 2),
);
```

### 3. Prefix Autocomplete (Search-As-You-Type)
Uses an indexed SQLite B-tree term range scan (`term >= prefix AND term < upperBound`) for responsive keystroke-by-keystroke suggestions:

```dart
final res = await search.search(
  'arch',
  options: const SearchOptions(prefix: true, limit: 10),
);
```

### 4. Exact Phrase & Positional Queries
Quoted strings and `SearchQuery.phrase` verify sequential token positions stored as packed `Uint32List` position blobs:

```dart
final res = await search.search('"offline first"');
// Or with optional positional slop via Query DSL:
final sloppy = await search.searchQuery(SearchQuery.phrase('offline sync', slop: 1));
```

### 5. Structured Filtering (`SearchFilter`)
Filter numeric, boolean, and facet fields inside SQLite using JSON extraction (`json_extract`):

```dart
final res = await search.search(
  'meeting',
  filters: [
    SearchFilter.equals('folder', 'Work'),
    SearchFilter.inList('status', ['active', 'review']),
    SearchFilter.range('wordCount', min: 50, max: 1500),
    SearchFilter.gte('priority', 2),
    SearchFilter.boolean('pinned', true),
  ],
);
```

Available filters: `equals`, `inList`, `range`, `gt`, `gte`, `lt`, `lte`, `boolean`.

### 6. Live Faceted Aggregations
Compute live category counts across matching hits in a single query:

```dart
final res = await search.search('roadmap', facets: ['folder', 'pinned']);
print(res.facetCounts['folder']); // e.g., {'Work': 12, 'Personal': 3}
```

### 7. Word-Boundary Snippet Highlighting
Wraps matched terms cleanly at word boundaries without breaking words mid-token:

```dart
final res = await search.search(
  'offline',
  options: const SearchOptions(
    highlight: true,
    highlightPreTag: '<mark>',
    highlightPostTag: '</mark>',
  ),
);
```

### 8. Boolean Query Parser & Fluent AST DSL
Supports human-readable operators (`AND`, `OR`, `NOT`, `-exclude`, `"exact phrase"`) as well as a composable Dart AST builder (`SearchQuery`):

```dart
// Human query string
final resA = await search.search('flutter AND sqlite -deprecated');

// Fluent Query DSL
final query = SearchQuery.match('flutter')
    .and(SearchQuery.phrase('local search'))
    .andNot(SearchQuery.match('deprecated'))
    .where(SearchFilter.boolean('archived', false));

final resB = await search.searchQuery(query);
```

### 9. Non-Blocking Background Isolate Execution
With `useIsolate: true` (the default for file-backed SQLite), indexing and search run on a dedicated background `IsolateWorker` so animations and scrolling stay smooth.

### 10. Persistent SQLite WAL & Fast Cold Reopen
Databases run in SQLite Write-Ahead Logging (`WAL`) mode with persisted metadata and field length statistics for instant reopen across app restarts:

```dart
await search.close();

// On next app launch with the same indexName:
final reopened = FlutterLocalSearch<Note>(/* same configuration */);
await reopened.initialize();
final res = await reopened.search('architecture');
```

### 11. Incremental Upsert, Delete & Clear
Update individual records in milliseconds without rebuilding the entire index:

```dart
await search.upsert(updatedNote);
await search.remove('note_42');
await search.clear();
```

### 12. Ready-to-Use Flutter Result & Empty-State Widgets
Use `LocalSearchResultBuilder<T>` and `LocalSearchEmptyState`—or build custom UI using `response.isEmpty` / `response.isNotEmpty`:

```dart
LocalSearchResultBuilder<Note>(
  response: response,
  isLoading: isSearching,
  onClear: () {
    controller.clear();
    resetFilters();
  },
  itemBuilder: (context, hit, index) {
    return ListTile(
      title: Text(hit.item.title),
      subtitle: Text('Relevance: ${hit.score.toStringAsFixed(2)}'),
    );
  },
)
```

---

## Storage Options

| Mode | Configuration | Best For |
|---|---|---|
| **SQLite WAL + Background Isolate** *(default)* | `FlutterLocalSearch(..., useIsolate: true)` | Production apps, persistence across restarts, large datasets |
| **SQLite WAL (Direct / Custom Path)** | `customDbPath: '/path/to/idx.db', useIsolate: false` | Single-isolate CLI scripts or custom storage lifecycle |
| **Pure In-Memory (`MemoryStorage`)** | `storage: MemoryStorage(), useIsolate: false` | Ephemeral session search, unit tests, zero disk I/O |

---

## Performance Benchmark (10,000 Documents)

Measured via `flutter test test/benchmark_10k_test.dart` using disk-persisted SQLite WAL storage and the background `IsolateWorker`:

| Operation | Dataset Size | Measured Latency |
|---|---|---|
| Batch `indexAll` (single WAL transaction) | 10,000 docs | **859 ms** |
| Exact query + filter + facet counts | 10,000 docs | **32 ms** |
| Prefix autocomplete (matching all 10,000 docs) | 10,000 docs | **44 ms** |
| Incremental single-document `upsert` | 10,000 docs | **8 ms** |
| Cold-start database reopen + query | 10,000 docs | **3 ms** |

---

## API Summary

* **Engine:** `FlutterLocalSearch<T>`, `FlutterLocalSearch.fromJsonList(...)`, `FlutterLocalSearch.strings(...)`
* **Schema:** `SearchField.text`, `SearchField.facet`, `SearchField.number`, `SearchField.boolean`
* **Query & Options:** `SearchOptions`, `SearchQuery`, `SearchFilter`, `StandardAnalyzer`, `BM25FScorer`
* **Results:** `SearchResponse<T>` (`hits`, `items`, `totalHits`, `facetCounts`, `queryTimeMs`, `isEmpty`, `isNotEmpty`), `SearchHit<T>`
* **Widgets:** `LocalSearchResultBuilder<T>`, `LocalSearchEmptyState`
* **Storage:** `SqliteStorage`, `MemoryStorage`, `StorageAdapter`

---

## License

MIT License — see [LICENSE](https://github.com/vaibhavjangir/flutter_local_search/blob/main/LICENSE).
