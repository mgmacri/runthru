import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:runthru/services/models.dart';

/// Caches extracted PDF documents to local gzip-compressed JSON files.
/// Uses LRU eviction to stay under [maxCacheBytes] (default 50 MB).
///
/// Documents are stored as gzip'd UTF-8 JSON (`dart:io` [gzip]) — natural
/// language word lists compress ~5-10x versus raw JSON, and encode/decode
/// runs in an isolate to keep the main thread free.
///
/// Supports two cache tiers:
/// - **Preview cache** (`*_preview.json.gz`): pages 1–3 for fast startup.
/// - **Full cache** (`*.json.gz`): the complete document.
class PdfCache {
  PdfCache._();

  /// Active cache budget in bytes. Set by [configureBudget] from the single
  /// [ContentCachePolicy] — do not hardcode private budgets here.
  static int _maxCacheBytes = 150 * 1024 * 1024;

  /// Current cache budget in bytes.
  static int get maxCacheBytes => _maxCacheBytes;

  /// Applies the shared cache policy budget.
  static void configureBudget(int bytes) {
    _maxCacheBytes = bytes;
  }

  /// Suffix for full-document cache files.
  static const String _fullSuffix = '.json.gz';

  /// Suffix for preview cache files.
  static const String _previewSuffix = '_preview.json.gz';

  static Future<String?> _cacheDir() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${appDir.path}/pdf_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      return cacheDir.path;
    } on FileSystemException catch (e) {
      dev.log('Cache directory unavailable: $e', name: 'pdf_cache');
      return null;
    }
  }

  /// Cache key = hash of filePath + lastModified.
  static Future<String> _cacheKey(String filePath) async {
    final file = File(filePath);
    String modified;
    try {
      modified = await file.exists()
          ? (await file.lastModified()).toIso8601String()
          : '';
    } on FileSystemException {
      modified = '';
    }
    final input = '$filePath|$modified';
    return input.hashCode.toUnsigned(64).toRadixString(16);
  }

  /// Reads a gzip'd-JSON [ExtractedDocument] from [cacheFile], or null if the
  /// payload is invalid or predates page-boundary support. Decode (gunzip +
  /// JSON parse) runs in an isolate — payloads can be multi-MB.
  static Future<ExtractedDocument?> _readGzipDoc(File cacheFile) async {
    final bytes = await cacheFile.readAsBytes();
    final doc = await Isolate.run(() {
      final jsonStr = utf8.decode(gzip.decode(bytes));
      final json = jsonDecode(jsonStr) as Map<String, Object?>;
      return ExtractedDocument.fromJson(json);
    });
    return isUsable(doc) ? doc : null;
  }

  /// Whether a cached [doc] can be served. Entries without page boundaries
  /// (the oldest format) and entries written by an older extractor are not:
  /// their text lacks headings and outline and, for PDFs, still carries
  /// running headers and split words. The caller re-extracts instead.
  @visibleForTesting
  static bool isUsable(ExtractedDocument doc) {
    return doc.hasPageBoundaries && doc.version >= kExtractionVersion;
  }

  /// Encodes [doc] to gzip'd UTF-8 JSON and writes it to [cacheFile]. Encode
  /// (JSON serialize + gzip) runs in an isolate to keep the main thread free.
  static Future<void> _writeGzipDoc(
    File cacheFile,
    ExtractedDocument doc,
  ) async {
    final bytes = await Isolate.run(
      () => gzip.encode(utf8.encode(jsonEncode(doc.toJson()))),
    );
    await cacheFile.writeAsBytes(bytes);
  }

  /// Load full cached document, or null if missing / invalid.
  static Future<ExtractedDocument?> load(String filePath) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return null;

      final key = await _cacheKey(filePath);
      final cacheFile = File('$dir/$key$_fullSuffix');
      if (!await cacheFile.exists()) return null;

      // Touch the file to update access time for LRU
      try {
        await cacheFile.setLastModified(DateTime.now());
      } on FileSystemException {
        // Non-critical — ignore
      }

      return _readGzipDoc(cacheFile);
    } on Object catch (e) {
      dev.log('Cache load failed: $e', name: 'pdf_cache');
      return null;
    }
  }

  /// Load preview-only cached document, or null if missing / invalid.
  static Future<ExtractedDocument?> loadPreview(String filePath) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return null;

      final key = await _cacheKey(filePath);
      final cacheFile = File('$dir/$key$_previewSuffix');
      if (!await cacheFile.exists()) return null;

      try {
        await cacheFile.setLastModified(DateTime.now());
      } on FileSystemException {
        // Non-critical
      }

      return _readGzipDoc(cacheFile);
    } on Object catch (e) {
      dev.log('Preview cache load failed: $e', name: 'pdf_cache');
      return null;
    }
  }

  /// Save full extracted document to cache, then evict if over budget.
  static Future<void> save(String filePath, ExtractedDocument doc) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return;

      final key = await _cacheKey(filePath);
      await _writeGzipDoc(File('$dir/$key$_fullSuffix'), doc);

      await _evictIfOverBudget(dir);
    } on Object catch (e) {
      dev.log('Cache save failed: $e', name: 'pdf_cache');
    }
  }

  /// Save preview document to cache.
  static Future<void> savePreview(
    String filePath,
    ExtractedDocument doc,
  ) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return;

      final key = await _cacheKey(filePath);
      await _writeGzipDoc(File('$dir/$key$_previewSuffix'), doc);

      await _evictIfOverBudget(dir);
    } on Object catch (e) {
      dev.log('Preview cache save failed: $e', name: 'pdf_cache');
    }
  }

  /// Check if a valid full cache exists for the given file.
  static Future<bool> hasValidCache(String filePath) async {
    final doc = await load(filePath);
    return doc != null;
  }

  /// Check if a valid preview cache exists for the given file.
  static Future<bool> hasValidPreviewCache(String filePath) async {
    final doc = await loadPreview(filePath);
    return doc != null;
  }

  /// Evict oldest (least-recently-used) cache files until under budget.
  ///
  /// All file I/O runs in an isolate to avoid blocking the main thread
  /// (Rule 11). With 6+ PDFs caching concurrently, synchronous directory
  /// scanning was causing 1000+ dropped frames at startup.
  static Future<void> _evictIfOverBudget(String dirPath) async {
    // Statics are per-isolate — capture the budget into the closure so the
    // spawned isolate doesn't see a default value.
    final budgetBytes = _maxCacheBytes;
    try {
      await Isolate.run(() => evictSync(dirPath, budgetBytes));
    } on Object catch (e) {
      dev.log('Cache eviction error: $e', name: 'pdf_cache');
    }
  }

  /// Total bytes currently used by the cache directory.
  static Future<int> totalUsageBytes() async {
    final dir = await _cacheDir();
    if (dir == null) return 0;
    try {
      return await Isolate.run(() {
        var total = 0;
        for (final file in Directory(dir).listSync().whereType<File>()) {
          try {
            total += file.lengthSync();
          } on FileSystemException {
            // skip
          }
        }
        return total;
      });
    } on Object catch (e) {
      dev.log('Cache usage scan failed: $e', name: 'pdf_cache');
      return 0;
    }
  }

  /// Synchronous LRU eviction (oldest last-read first) — runs inside an
  /// isolate in production; exposed for tests.
  @visibleForTesting
  static void evictSync(String dirPath, int budgetBytes) {
    final dir = Directory(dirPath);
    final files = dir.listSync().whereType<File>().toList();

    var totalBytes = 0;
    for (final file in files) {
      totalBytes += file.lengthSync();
    }

    if (totalBytes <= budgetBytes) return;

    // Sort by last modified ascending (oldest first = LRU).
    files.sort((a, b) {
      try {
        return a.lastModifiedSync().compareTo(b.lastModifiedSync());
      } on FileSystemException {
        return 0;
      }
    });

    for (final file in files) {
      if (totalBytes <= budgetBytes) break;
      try {
        final size = file.lengthSync();
        file.deleteSync();
        totalBytes -= size;
      } on FileSystemException {
        // Non-critical — skip this file.
      }
    }
  }
}
