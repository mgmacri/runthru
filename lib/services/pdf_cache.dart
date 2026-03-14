import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:speedy_boy/services/models.dart';

/// Caches extracted PDF documents to local JSON files.
class PdfCache {
  PdfCache._();

  static Future<String> _cacheDir() async {
    final appDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${appDir.path}/pdf_cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    return cacheDir.path;
  }

  /// Cache key = hash of filePath + lastModified.
  static String _cacheKey(String filePath) {
    final file = File(filePath);
    final modified =
        file.existsSync() ? file.lastModifiedSync().toIso8601String() : '';
    final input = '$filePath|$modified';
    return input.hashCode.toUnsigned(64).toRadixString(16);
  }

  /// Load cached document, or null if missing / invalid.
  static Future<ExtractedDocument?> load(
    String filePath,
  ) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final cacheFile = File('$dir/$key.json');
      if (!cacheFile.existsSync()) return null;

      final raw = await cacheFile.readAsString();
      final json = jsonDecode(raw) as Map<String, Object?>;
      return ExtractedDocument.fromJson(json);
    } on Object {
      return null;
    }
  }

  /// Save extracted document to cache.
  static Future<void> save(
    String filePath,
    ExtractedDocument doc,
  ) async {
    final dir = await _cacheDir();
    final key = _cacheKey(filePath);
    final cacheFile = File('$dir/$key.json');
    final json = jsonEncode(doc.toJson());
    await cacheFile.writeAsString(json);
  }

  /// Check if a valid cache exists for the given file.
  static Future<bool> hasValidCache(String filePath) async {
    final doc = await load(filePath);
    return doc != null;
  }
}
