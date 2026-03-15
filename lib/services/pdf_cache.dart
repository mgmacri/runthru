import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:speedy_boy/services/models.dart';

/// Caches extracted PDF documents to local JSON files.
/// Uses LRU eviction to stay under [maxCacheBytes] (default 50 MB).
class PdfCache {
  PdfCache._();

  /// Maximum cache size in bytes (50 MB).
  static const int maxCacheBytes = 50 * 1024 * 1024;

  static Future<String?> _cacheDir() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${appDir.path}/pdf_cache');
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      return cacheDir.path;
    } on FileSystemException catch (e) {
      dev.log(
        'Cache directory unavailable: $e',
        name: 'pdf_cache',
      );
      return null;
    }
  }

  /// Cache key = hash of filePath + lastModified.
  static String _cacheKey(String filePath) {
    final file = File(filePath);
    String modified;
    try {
      modified =
          file.existsSync() ? file.lastModifiedSync().toIso8601String() : '';
    } on FileSystemException {
      modified = '';
    }
    final input = '$filePath|$modified';
    return input.hashCode.toUnsigned(64).toRadixString(16);
  }

  /// Load cached document, or null if missing / invalid.
  static Future<ExtractedDocument?> load(String filePath) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return null;

      final key = _cacheKey(filePath);
      final cacheFile = File('$dir/$key.json');
      if (!cacheFile.existsSync()) return null;

      // Touch the file to update access time for LRU
      try {
        cacheFile.setLastModifiedSync(DateTime.now());
      } on FileSystemException {
        // Non-critical — ignore
      }

      final raw = await cacheFile.readAsString();
      final json = jsonDecode(raw) as Map<String, Object?>;
      return ExtractedDocument.fromJson(json);
    } on Object catch (e) {
      dev.log('Cache load failed: $e', name: 'pdf_cache');
      return null;
    }
  }

  /// Save extracted document to cache, then evict if over budget.
  static Future<void> save(
    String filePath,
    ExtractedDocument doc,
  ) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return;

      final key = _cacheKey(filePath);
      final cacheFile = File('$dir/$key.json');
      final json = jsonEncode(doc.toJson());
      await cacheFile.writeAsString(json);

      await _evictIfOverBudget(dir);
    } on Object catch (e) {
      dev.log('Cache save failed: $e', name: 'pdf_cache');
    }
  }

  /// Check if a valid cache exists for the given file.
  static Future<bool> hasValidCache(String filePath) async {
    final doc = await load(filePath);
    return doc != null;
  }

  /// Evict oldest (least-recently-used) cache files until under budget.
  static Future<void> _evictIfOverBudget(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      final files = dir.listSync().whereType<File>().toList();

      var totalBytes = 0;
      for (final file in files) {
        totalBytes += file.lengthSync();
      }

      if (totalBytes <= maxCacheBytes) return;

      // Sort by last modified ascending (oldest first = LRU)
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
        } on FileSystemException catch (e) {
          dev.log('Cache eviction failed: $e', name: 'pdf_cache');
        }
      }
    } on Object catch (e) {
      dev.log('Cache eviction error: $e', name: 'pdf_cache');
    }
  }
}
