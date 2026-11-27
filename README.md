# 🔍 flutter_local_search

[![pub package](https://img.shields.io/pub/v/flutter_local_search.svg)](https://pub.dev/packages/flutter_local_search)
[![pub points](https://img.shields.io/pub/points/flutter_local_search)](https://pub.dev/packages/flutter_local_search/score)
[![pub likes](https://img.shields.io/pub/likes/flutter_local_search)](https://pub.dev/packages/flutter_local_search/score)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/VaibhavJangir26/flutter_local_search/blob/main/LICENSE)
[![platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-lightgrey.svg)](https://pub.dev/packages/flutter_local_search)

⚡ **An embedded, offline-first full-text search engine for Flutter and Dart**—with **BM25F relevance ranking**, **typo-tolerant fuzzy search**, **prefix autocomplete**, **exact phrase queries**, **boolean Query DSL**, **live faceted filtering**, **SQLite WAL persistence**, and **background Isolate execution**. Zero backend server, cloud API key, or internet required.

>  **Enjoying `flutter_local_search`?** Tap the **Like** button on [pub.dev](https://pub.dev/packages/flutter_local_search), ⭐ **Star** the repo on [GitHub](https://github.com/VaibhavJangir26/flutter_local_search), and share it with fellow Flutter developers!

---

## Why `flutter_local_search`?

Most Flutter apps need fast client-side search—for **e-commerce catalogs & products**, **offline notes**, **contacts & directories**, **articles**, **tasks**, or **cached REST API JSON**—without paying monthly cloud search bills or writing brittle `list.where((x) => x.contains(q))` loops.

| Capability | `List.where` / `.contains()` | Raw SQLite (`LIKE` / FTS5) | Cloud (Algolia / Typesense) | `flutter_local_search`                     |
|---|---|---|---|--------------------------------------------|
|  **100% Offline / Zero Backend** | ✅ Yes | ✅ Yes | ❌ Cloud + API keys | ✅ **On-Device SQLite WAL**                 |
|  **Typed Models (`List<T>`) & JSON** | ⚠️ Manual loop | ❌ Manual SQL schema | ⚠️ HTTP JSON | ✅ **`List<T>`, `fromJsonList`, `strings`** |
|  **BM25F Field-Weighted Ranking** | ❌ None | ⚠️ Manual / basic | ✅ Yes | ✅ **Field Weights + Length Norm**          |
|  **Typo-Tolerant Fuzzy Search** | ❌ None | ❌ None | ✅ Yes | ✅ **Damerau-Levenshtein (1–2 edits)**      |
| **Search-As-You-Type Prefix** | ⚠️ `.startsWith()` | ⚠️ `GLOB` / prefix | ✅ Yes | ✅ **Indexed B-Tree Term Scan**             |
|  **Exact Phrase Proximity** | ❌ None | ⚠️ Complex SQL | ✅ Yes | ✅ **Quoted Phrases (`positions_blob`)**    |
|  **Live Facets & Range Filters** | ⚠️ Manual Dart code | ⚠️ Manual `GROUP BY` | ✅ Yes | ✅ **Live `facetCounts` + `json_extract`**  |
|  **UI Thread Safety (60/120 FPS)** | ❌ Main thread | ❌ Blocks unless wrapped | ⚠️ Network async | ✅ **Background `IsolateWorker`**           |
|  **Ready Empty-State UI Widgets** | ❌ None | ❌ None | ⚠️ Separate UI SDK | ✅ **`LocalSearchResultBuilder<T>`**        |

---

## Installation

Add `flutter_local_search` to your `pubspec.yaml`:

```bash
flutter pub add flutter_local_search
```

Import it in Dart:

```dart
import 'package:flutter_local_search/flutter_local_search.dart';
```

> **Requirements:** Dart `^3.12.0` · Flutter `>=3.29.0` · Supports **Android, iOS, macOS, Windows, and Linux** (plus `MemoryStorage` for pure in-memory & unit tests).

---

## Quickstart with Product Example

Here is a complete production setup indexing a `Product` catalog with weighted fields, typo tolerance, prefix autocomplete, range filtering, live facet counts, and highlighted snippets:

```dart
class Product {
  final String id;
  final String name;
  final String description;
  final String brand;
  final double price;
  final bool inStock;

  const Product({
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

// Initialize once (uses SQLite WAL + background Isolate by default)
final search = FlutterLocalSearch<Product>(
  indexName: 'products',
  id: (p) => p.id,
  fields: (p) => {
    'name': SearchField.text(p.name, weight: 3.0),     // 3x BM25F title boost
    'description': SearchField.text(p.description),    // Standard full-text
    'brand': SearchField.facet(p.brand, weight: 2.0),  // Searchable + facetable
    'price': SearchField.number(p.price),              // Numeric range filters
    'inStock': SearchField.boolean(p.inStock),         // Boolean flag filter
  },
  toJson: (p) => p.toJson(),
  fromJson: Product.fromJson,
);

await search.initialize();

// Index any List<Product> in a single atomic WAL transaction
await search.indexAll(products);

// Search with fuzzy typos, prefix autocomplete, filters, facets & highlights
final response = await search.search(
  'iphon 15', // Typo automatically matches "iPhone 15"
  options: const SearchOptions(
    fuzzy: true,
    prefix: true,
    highlight: true,
  ),
  filters: [
    SearchFilter.equals('brand', 'Apple'),
    SearchFilter.range('price', min: 400, max: 1500),
    SearchFilter.boolean('inStock', true),
  ],
  facets: ['brand', 'inStock'],
);

print('Found ${response.totalHits} products in ${response.queryTimeMs} ms');
print('Brand counts: ${response.facetCounts['brand']}');

for (final hit in response.hits) {
  print('${hit.item.name} (\$${hit.item.price}) | Score: ${hit.score.toStringAsFixed(2)}');
  print('Highlight: ${hit.highlights['description']}');
}
```

---

## Works with Any Domain, Raw API JSON, or String Lists

Swap `Product` for **any** model (`Note`, `Contact`, `Article`, `Task`, `Course`, `Record`)—or skip writing a model class altogether:

### Zero-Boilerplate Raw API JSON (`fromJsonList`)
Ideal for `dummyjson.com`, REST APIs, GraphQL responses, or cached JSON payloads:

```dart
final apiSearch = FlutterLocalSearch.fromJsonList(
  indexName: 'api_catalog',
  facetFields: ['category', 'brand'],
  fieldWeights: {'title': 3.0, 'description': 1.0},
);

await apiSearch.initialize();
await apiSearch.indexAll(apiJsonList);

final res = await apiSearch.search(
  'headfones',
  options: const SearchOptions(fuzzy: true, highlight: true),
  facets: ['category'],
);
```

### Plain String Lists (`strings`)
Perfect for tags, city pickers, categories, commands, or recent search history:

```dart
final tagSearch = FlutterLocalSearch.strings(indexName: 'tags');
await tagSearch.initialize();
await tagSearch.indexAll(['flutter', 'sqlite', 'offline-first', 'full-text-search']);

final res = await tagSearch.search('fluter', options: const SearchOptions(fuzzy: true));
print(res.items); // ['flutter']
```

---

## 12 Core Capabilities of flutter_local_search

### 1. Field-Weighted BM25F Relevance Ranking
Boost high-signal fields (`SearchField.text(p.name, weight: 3.0)`) above body/description fields (`weight: 1.0`). Field weights and length normalization statistics are persisted across app restarts.

### 2. Typo-Tolerant Fuzzy Search (Damerau-Levenshtein)
Treats adjacent character transpositions (`"fluter"` → `"flutter"`, `"iphnoe"` → `"iphone"`) as **1 edit** with length-window pruning and relevance decay (exact matches outrank 1-typo matches, which outrank 2-typo matches):

```dart
final res = await search.search(
  'galxy',
  options: const SearchOptions(fuzzy: true, maxEditDistance: 2),
);
```

### 3. ⚡ B-Tree Prefix Autocomplete (Search-As-You-Type)
Uses a fast SQLite B-tree term range scan (`term >= prefix AND term < upperBound`) for instant keystroke-by-keystroke suggestions:

```dart
final res = await search.search('sam', options: const SearchOptions(prefix: true, limit: 10));
```

### 4. Quoted Exact Phrase & Proximity Search
Verifies sequential token positions stored as compact `Uint32List` position blobs:

```dart
final exact = await search.search('"noise canceling"');
final nearby = await search.searchQuery(SearchQuery.phrase('titanium pro', slop: 1));
```

### 5. Structured & Range Filtering (`SearchFilter`)
Executes filters inside SQLite using JSON extraction (`json_extract`):
`equals`, `inList`, `range`, `gt`, `gte`, `lt`, `lte`, and `boolean`.

```dart
final res = await search.search(
  'laptop',
  filters: [
    SearchFilter.inList('brand', ['Apple', 'Dell']),
    SearchFilter.range('price', min: 800, max: 2200),
    SearchFilter.boolean('inStock', true),
  ],
);
```

### 6. Live Faceted Aggregations
Aggregate live category/attribute counts across all matching items:

```dart
final res = await search.search('pro', facets: ['brand', 'inStock']);
print(res.facetCounts['brand']); // {'Apple': 12, 'Samsung': 4}
```

### 7. Word-Boundary Snippet Highlighting
Wraps matched tokens in `<mark>` (or custom `highlightPreTag` / `highlightPostTag`) while strictly respecting word boundaries:

```dart
final res = await search.search(
  'titanium',
  options: const SearchOptions(
    highlight: true,
    highlightPreTag: '<mark>',
    highlightPostTag: '</mark>',
  ),
);
```

### 8. Boolean Query Parser & Fluent AST DSL
Supports human-readable queries (`AND`, `OR`, `NOT`, `-exclude`, `"quoted phrase"`) and composable Dart AST queries (`SearchQuery`):

```dart
// Option A: Query string
final resA = await search.search('laptop AND AMOLED -refurbished');

// Option B: Fluent Query DSL
final query = SearchQuery.match('laptop')
    .andNot(SearchQuery.match('refurbished'))
    .where(SearchFilter.lte('price', 1500));

final resB = await search.searchQuery(query);
```

### 9. Background Isolate Worker (Zero UI Jank)
With `useIsolate: true` (default for disk-backed SQLite), indexing and searching run on a dedicated background `IsolateWorker` so scrolling and animations never drop frames.

### 10. Persistent SQLite WAL & Fast Cold Reopen
Runs SQLite in **Write-Ahead Logging (WAL)** mode and persists corpus metadata/lengths so reopening an indexed database on cold launch is near-instant.

### 11. Incremental Upsert, Remove & Clear
Update individual records without reindexing the entire dataset:

```dart
await search.upsert(updatedProduct);
await search.remove('product_123');
await search.clear();
```

### 12. Built-In Reactive & Empty-State Flutter Widgets
Handles loading states, empty searches, and filter resets out of the box—or check `response.isEmpty` / `response.isNotEmpty` in your own UI:

```dart
LocalSearchResultBuilder<Product>(
  response: searchResponse,
  isLoading: isSearching,
  onClear: () {
    searchController.clear();
    resetFilters();
  },
  itemBuilder: (context, hit, index) {
    return ListTile(
      title: Text(hit.item.name),
      subtitle: Text(hit.highlights['description']?.first ?? hit.item.description),
      trailing: Text('\$${hit.item.price.toStringAsFixed(2)}'),
    );
  },
)
```

---

##  Storage Modes

| Mode                                    | Configuration | Best Use Case |
|-----------------------------------------|---|---|
| **SQLite WAL + Isolate** *(default)*    | `FlutterLocalSearch(..., useIsolate: true)` | Production Flutter apps, persistence across restarts |
| **SQLite WAL (Direct)**                 | `customDbPath: '/path/to/idx.db', useIsolate: false` | Single-isolate CLI scripts or custom storage path |
| **In-Memory (`MemoryStorage`)**         | `storage: MemoryStorage(), useIsolate: false` | Ephemeral session search, unit tests, zero disk I/O |

---

## 10,000-Document Verified Benchmark

Measured via `flutter test test/benchmark_10k_test.dart` with disk-persisted SQLite WAL storage and the background `IsolateWorker`:

| Operation                                    | Dataset Size | Measured Latency |
|----------------------------------------------|---|---|
| Batch `indexAll` (single WAL transaction)    | 10,000 docs | **859 ms** |
| Exact Query + Range Filter + Facets          | 10,000 docs | **32 ms** |
| Prefix Autocomplete (10,000 matches)         | 10,000 docs | **44 ms** |
| Incremental Single-Doc `upsert`              | 10,000 docs | **8 ms** |
| Cold-Start Reopen + Query                    | 10,000 docs | **3 ms** |

---

## Developer & AI Search FAQ

* **How do I implement offline full-text search in Flutter without a backend or Algolia?**
  Use `flutter_local_search`: pass your `List<T>` or `List<Map<String, dynamic>>` via `FlutterLocalSearch<T>` or `FlutterLocalSearch.fromJsonList()`, and search offline using SQLite WAL in a background Isolate.
* **How do I add typo-tolerant fuzzy search and autocomplete to Flutter?**
  Enable `SearchOptions(fuzzy: true, maxEditDistance: 2, prefix: true)` to combine Damerau-Levenshtein typo matching with SQLite B-tree prefix scanning.
* **How is `flutter_local_search` different from SQLite `LIKE '%term%'` or raw FTS5?**
  Unlike `LIKE`, `flutter_local_search` uses an inverted index with BM25F field boosting, typo tolerance, positional phrases, live facet counts, snippet highlighting, and direct hydration back into typed Dart objects `T`.

---

## ❤️ Like & Share

If **`flutter_local_search`** helped your app ship fast, offline, cloud-free search:
* 👍 **Like** the package on **[pub.dev/packages/flutter_local_search](https://pub.dev/packages/flutter_local_search)**
* 📣 **Share** it with fellow Flutter developers and teams!

Bug reports and feature requests are welcome via [GitHub Issues](https://github.com/VaibhavJangir26/flutter_local_search/issues).

---

## 📄 License

MIT License — see [LICENSE](https://github.com/VaibhavJangir26/flutter_local_search/blob/main/LICENSE).

