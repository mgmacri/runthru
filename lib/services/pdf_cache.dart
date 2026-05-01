import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:runthru/services/models.dart';

/// Caches extracted PDF documents to local JSON files.
/// Uses LRU eviction to stay under [maxCacheBytes] (default 50 MB).
///
/// Supports two cache tiers:
/// - **Preview cache** (`*_preview.json`): pages 1–3 for fast startup.
/// - **Full cache** (`*.json`): the complete document.
class PdfCache {
  PdfCache._();

  /// Maximum cache size in bytes (50 MB).
  static const int maxCacheBytes = 50 * 1024 * 1024;

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

  /// Load full cached document, or null if missing / invalid.
  static Future<ExtractedDocument?> load(String filePath) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return null;

      final key = await _cacheKey(filePath);
      final cacheFile = File('$dir/$key.json');
      if (!await cacheFile.exists()) return null;

      // Touch the file to update access time for LRU
      try {
        await cacheFile.setLastModified(DateTime.now());
      } on FileSystemException {
        // Non-critical — ignore
      }

      final raw = await cacheFile.readAsString();
      // Decode JSON off the main thread — can be multi-MB.
      final doc = await Isolate.run(() {
        final json = jsonDecode(raw) as Map<String, Object?>;
        return ExtractedDocument.fromJson(json);
      });
      // Invalidate cache entries without page boundaries (old format).
      if (!doc.hasPageBoundaries) return null;
      return doc;
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
      final cacheFile = File('$dir/${key}_preview.json');
      if (!await cacheFile.exists()) return null;

      try {
        await cacheFile.setLastModified(DateTime.now());
      } on FileSystemException {
        // Non-critical
      }

      final raw = await cacheFile.readAsString();
      // Decode JSON off the main thread — can be multi-MB.
      final doc = await Isolate.run(() {
        final json = jsonDecode(raw) as Map<String, Object?>;
        return ExtractedDocument.fromJson(json);
      });
      // Invalidate cache entries without page boundaries (old format).
      if (!doc.hasPageBoundaries) return null;
      return doc;
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
      final cacheFile = File('$dir/$key.json');
      // Encode JSON off the main thread.
      final json = await Isolate.run(() => jsonEncode(doc.toJson()));
      await cacheFile.writeAsString(json);

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
      final cacheFile = File('$dir/${key}_preview.json');
      // Encode JSON off the main thread.
      final json = await Isolate.run(() => jsonEncode(doc.toJson()));
      await cacheFile.writeAsString(json);

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
    try {
      await Isolate.run(() => _evictSync(dirPath));
    } on Object catch (e) {
      dev.log('Cache eviction error: $e', name: 'pdf_cache');
    }
  }

  /// Synchronous eviction — runs inside an isolate only.
  static void _evictSync(String dirPath) {
    final dir = Directory(dirPath);
    final files = dir.listSync().whereType<File>().toList();

    var totalBytes = 0;
    for (final file in files) {
      totalBytes += file.lengthSync();
    }

    if (totalBytes <= maxCacheBytes) return;

    // Sort by last modified ascending (oldest first = LRU).
    files.sort((a, b) {
      try {
        return a.lastModifiedSync().compareTo(b.lastModifiedSync());
      } on FileSystemException {
        return 0;
      }
    });

    for (final file in files) {
      if (totalBytes <= maxCacheBytes) break;
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
