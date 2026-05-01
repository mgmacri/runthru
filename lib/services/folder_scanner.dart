import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/store/config.dart';

/// Scans one or more folders recursively for .pdf files.
/// Supports multi-directory concurrent scanning with streaming results.
class FolderScannerService {
  FolderScannerService._();

  static bool get _isIos => !kIsWeb && Platform.isIOS;

  static const String _tag = 'folder_scanner';

  /// Maximum concurrent scan isolates when batching >4 directories.
  static const int _maxConcurrentScans = 4;

  /// Scan a single directory for PDFs and EPUBs.
  ///
  /// On iOS the picked directory is a security-scoped URL whose access
  /// token is only valid on the main isolate, so we scan synchronously
  /// there. On all other platforms we use a background isolate.
  static Future<List<PdfEntry>> scanAsync(String? folderPath) async {
    appLog(_tag, 'scanAsync called — path=$folderPath isIos=$_isIos');
    if (folderPath == null || folderPath.isEmpty) {
      appLog(_tag, 'scanAsync — empty path, returning []');
      return [];
    }
    try {
      List<PdfEntry> entries;
      if (_isIos) {
        entries = _scanSync(folderPath);
      } else {
        entries = await Isolate.run(() => _scanSync(folderPath));
      }
      appLog(
        _tag,
        'scanAsync result — ${entries.length} files found: '
        '${entries.map((e) => e.fileName).join(', ')}',
      );
      return entries;
    } on Object catch (e, st) {
      appLog(_tag, 'scanAsync EXCEPTION: $e\n$st');
      return [];
    }
  }

  /// Scan multiple directories concurrently.
  /// Results are deduplicated by canonical file path.
  static Future<List<PdfEntry>> scanMultipleAsync(
    List<String> folderPaths,
  ) async {
    if (folderPaths.isEmpty) return [];

    final seen = <String>{};
    final results = <PdfEntry>[];

    // Batch concurrency: scan up to _maxConcurrentScans at a time.
    for (var i = 0; i < folderPaths.length; i += _maxConcurrentScans) {
      final batch = folderPaths.skip(i).take(_maxConcurrentScans);
      final futures = batch.map(scanAsync);
      final batchResults = await Future.wait(futures);

      for (final entries in batchResults) {
        for (final entry in entries) {
          final canonical = _canonicalPath(entry.filePath);
          if (seen.add(canonical)) {
            results.add(entry);
          }
        }
      }
    }

    results.sort((a, b) => a.fileName.compareTo(b.fileName));
    return results;
  }

  /// Stream scanned PdfEntry objects incrementally from multiple directories.
  /// Cards appear one-by-one as they are discovered.
  static Stream<PdfEntry> scanMultipleStream(
    List<String> folderPaths,
  ) async* {
    if (folderPaths.isEmpty) return;

    final seen = <String>{};

    for (var i = 0; i < folderPaths.length; i += _maxConcurrentScans) {
      final batch = folderPaths.skip(i).take(_maxConcurrentScans).toList();
      final futures = batch.map(scanAsync);
      final batchResults = await Future.wait(futures);

      for (final entries in batchResults) {
        for (final entry in entries) {
          final canonical = _canonicalPath(entry.filePath);
          if (seen.add(canonical)) {
            yield entry;
          }
        }
      }
    }
  }

  /// Synchronous scan — runs in an isolate on Android/desktop,
  /// or on the main isolate on iOS (security-scoped access).
  static List<PdfEntry> _scanSync(String folderPath) {
    // NOTE: appLog() uses main-isolate state and cannot be called from
    // Isolate.run(). Use dart:developer log() for cross-isolate safety.
    dev.log('_scanSync — path=$folderPath', name: _tag);

    final dir = Directory(folderPath);
    final exists = dir.existsSync();
    dev.log('_scanSync — existsSync=$exists', name: _tag);

    if (!exists) {
      dev.log('_scanSync — directory does not exist, returning []', name: _tag);
      return [];
    }

    final entries = <PdfEntry>[];

    try {
      final entities = _isIos
          ? dir.listSync()
          : dir.listSync(recursive: true, followLinks: false);

      dev.log('_scanSync — listSync returned ${entities.length} entities',
          name: _tag);

      for (final entity in entities) {
        if (entity is File) {
          final path = entity.path;
          final lower = path.toLowerCase();
          if (lower.endsWith('.pdf') || lower.endsWith('.epub')) {
            final name = path.split(Platform.pathSeparator).last;
            entries.add(PdfEntry(filePath: path, fileName: name));
          }
        }
      }
    } on FileSystemException catch (e) {
      dev.log('_scanSync FileSystemException: ${e.message} (${e.path})',
          name: _tag);
    } on Object catch (e) {
      dev.log('_scanSync unexpected error: $e', name: _tag);
    }

    dev.log('_scanSync — found ${entries.length} books (PDF/EPUB)', name: _tag);
    entries.sort((a, b) => a.fileName.compareTo(b.fileName));
    return entries;
  }

  /// Normalize a file path for deduplication.
  static String _canonicalPath(String path) {
    // On Windows, normalize separators and lower-case for case-insensitive FS.
    var canonical = path.replaceAll('\\', '/');
    if (!kIsWeb && Platform.isWindows) {
      canonical = canonical.toLowerCase();
    }
    return canonical;
  }
}

/// Riverpod provider that watches config for folder path changes.
final pdfListProvider = FutureProvider<List<PdfEntry>>((ref) async {
  final config = ref.watch(configProvider);
  return config.when(
    data: (c) {
      appLog('pdfListProvider', 'config loaded — folder=${c.pdfFolderPath}');
      final path = c.pdfFolderPath;
      if (path == null || path.isEmpty) return Future.value([]);
      // Support single path via scanAsync for backward compatibility.
      return FolderScannerService.scanAsync(path);
    },
    loading: () async {
      appLog('pdfListProvider', 'config loading…');
      return [];
    },
    error: (e, __) async {
      appLog('pdfListProvider', 'config error: $e');
      return [];
    },
  );
});

/// Stream-based provider for incremental multi-directory scanning.
final pdfStreamProvider =
    StreamProvider.family<PdfEntry, List<String>>((ref, folderPaths) {
  return FolderScannerService.scanMultipleStream(folderPaths);
});
