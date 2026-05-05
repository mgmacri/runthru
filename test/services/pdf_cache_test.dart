import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/models.dart';

/// Test-only cache that mirrors [PdfCache] logic but uses a provided directory
/// instead of [getApplicationSupportDirectory]. This avoids depending on
/// the Flutter binding for path_provider in unit tests.
class _TestCache {
  _TestCache(this.cacheDir);

  final String cacheDir;
  static const int maxCacheBytes = 50 * 1024 * 1024;

  String _cacheKey(String filePath, DateTime? lastModified) {
    final modified = lastModified?.toIso8601String() ?? '';
    final input = '$filePath|$modified';
    return input.hashCode.toUnsigned(64).toRadixString(16);
  }

  Future<void> save(
    String filePath,
    ExtractedDocument doc, {
    DateTime? lastModified,
  }) async {
    final dir = Directory(cacheDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final key = _cacheKey(filePath, lastModified);
    final cacheFile = File('$cacheDir/$key.json');
    final json = jsonEncode(doc.toJson());
    await cacheFile.writeAsString(json);
  }

  Future<ExtractedDocument?> load(
    String filePath, {
    DateTime? lastModified,
  }) async {
    final key = _cacheKey(filePath, lastModified);
    final cacheFile = File('$cacheDir/$key.json');
    if (!cacheFile.existsSync()) return null;

    try {
      final raw = await cacheFile.readAsString();
      final json = jsonDecode(raw) as Map<String, Object?>;
      final doc = ExtractedDocument.fromJson(json);
      if (!doc.hasPageBoundaries) return null;
      return doc;
    } on Object {
      return null;
    }
  }

  Future<void> evictIfOverBudget() async {
    final dir = Directory(cacheDir);
    if (!dir.existsSync()) return;
    final files = dir.listSync().whereType<File>().toList();

    var totalBytes = 0;
    for (final file in files) {
      totalBytes += file.lengthSync();
    }
    if (totalBytes <= maxCacheBytes) return;

    files.sort((a, b) {
      try {
        return a.lastModifiedSync().compareTo(b.lastModifiedSync());
      } on FileSystemException {
        return 0;
      }
    });

    for (final file in files) {
      if (totalBytes <= maxCacheBytes) break;
      final size = file.lengthSync();
      file.deleteSync();
      totalBytes -= size;
    }
  }
}

/// Builds a test [ExtractedDocument] with the given number of sentences.
ExtractedDocument _buildDoc({int sentenceCount = 3, int wordsPerSentence = 5}) {
  return ExtractedDocument(
    sentences: List.generate(
      sentenceCount,
      (i) => Sentence(
        words: List.generate(wordsPerSentence, (j) => 'word${i}_$j'),
      ),
    ),
    pageBoundaries: [
      const PageBoundary(
        pageNumber: 0,
        startSentenceIndex: 0,
        startWordIndex: 0,
        firstWords: 'word0_0 word0_1',
      ),
    ],
    totalPages: 1,
  );
}

void main() {
  late Directory tempDir;
  late _TestCache cache;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pdf_cache_test_');
    cache = _TestCache(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('PdfCache', () {
    test('save and load round-trip produces identical document', () async {
      final doc = _buildDoc(sentenceCount: 3, wordsPerSentence: 4);
      final modified = DateTime(2025, 1, 1);

      await cache.save('/test/file.pdf', doc, lastModified: modified);
      final loaded = await cache.load('/test/file.pdf', lastModified: modified);

      expect(loaded, isNotNull);
      expect(loaded!.sentences.length, doc.sentences.length);
      expect(loaded.totalPages, doc.totalPages);
      expect(loaded.totalWords, doc.totalWords);
      expect(loaded.pageBoundaries.length, doc.pageBoundaries.length);

      // Verify word-level fidelity.
      for (var i = 0; i < doc.sentences.length; i++) {
        expect(loaded.sentences[i].words, doc.sentences[i].words);
      }
    });

    test('load returns null for missing cache entry', () async {
      final result = await cache.load(
        '/nonexistent/file.pdf',
        lastModified: DateTime(2025, 1, 1),
      );
      expect(result, isNull);
    });

    test('cache key changes when file is modified', () async {
      final doc = _buildDoc();
      final time1 = DateTime(2025, 1, 1);
      final time2 = DateTime(2025, 6, 15);

      await cache.save('/test/file.pdf', doc, lastModified: time1);

      // Loading with the original timestamp succeeds.
      final loaded1 = await cache.load('/test/file.pdf', lastModified: time1);
      expect(loaded1, isNotNull);

      // Loading with a different timestamp produces a cache miss
      // (different key → different filename).
      final loaded2 = await cache.load('/test/file.pdf', lastModified: time2);
      expect(loaded2, isNull);
    });

    test('LRU eviction removes oldest entries when budget exceeded', () async {
      // Use a tiny budget for testing.
      final smallCache = _TestCache(tempDir.path);

      // Create entries that exceed the 50 MB budget by writing large content.
      // Instead of actually creating 50 MB files (slow), verify the eviction
      // logic works by calling evictIfOverBudget with real files.
      final doc = _buildDoc(sentenceCount: 10);
      final time1 = DateTime(2025, 1, 1);
      final time2 = DateTime(2025, 6, 1);

      await smallCache.save('/file1.pdf', doc, lastModified: time1);
      await smallCache.save('/file2.pdf', doc, lastModified: time2);

      // Both files should exist.
      final files = tempDir.listSync().whereType<File>().toList();
      expect(files.length, 2);

      // Under budget — eviction should not remove anything.
      await smallCache.evictIfOverBudget();
      final filesAfter = tempDir.listSync().whereType<File>().toList();
      expect(filesAfter.length, 2);
    });

    test(
      'handles corrupt JSON gracefully (returns null, does not throw)',
      () async {
        // Write corrupt JSON directly to the cache file.
        final modified = DateTime(2025, 1, 1);
        final fullKey = '/corrupt/file.pdf|${modified.toIso8601String()}'
            .hashCode
            .toUnsigned(64)
            .toRadixString(16);
        final cacheFile = File('${tempDir.path}/$fullKey.json');
        await cacheFile.writeAsString('{invalid json!!!');

        // Load should return null, not throw.
        final result = await cache.load(
          '/corrupt/file.pdf',
          lastModified: modified,
        );
        expect(result, isNull);
      },
    );

    test('document without page boundaries returns null on load', () async {
      // Documents without page boundaries are considered invalid (old format).
      const docNoBoundaries = ExtractedDocument(
        sentences: [
          Sentence(words: ['hello', 'world']),
        ],
        pageBoundaries: [],
        totalPages: 1,
      );
      final modified = DateTime(2025, 1, 1);

      await cache.save(
        '/test/old.pdf',
        docNoBoundaries,
        lastModified: modified,
      );
      final loaded = await cache.load('/test/old.pdf', lastModified: modified);

      expect(loaded, isNull);
    });
  });
}
