import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/store/config.dart';

/// Scans a folder recursively for .pdf files.
class FolderScannerService {
  FolderScannerService._();

  static bool get _isIos => !kIsWeb && Platform.isIOS;

  /// Scan for PDFs.
  ///
  /// On iOS the picked directory is a security-scoped URL whose access
  /// token is only valid on the main isolate, so we scan synchronously
  /// there. On all other platforms we use a background isolate.
  static Future<List<PdfEntry>> scanAsync(String? folderPath) async {
    if (folderPath == null || folderPath.isEmpty) return [];
    try {
      if (_isIos) {
        // Security-scoped resource — must stay on the main isolate.
        return _scanSync(folderPath);
      }
      return await Isolate.run(() => _scanSync(folderPath));
    } on Object catch (e, st) {
      dev.log(
        'Folder scan failed: $e',
        name: 'folder_scanner',
        error: e,
        stackTrace: st,
      );
      return [];
    }
  }

  /// Synchronous scan — runs in an isolate on Android/desktop,
  /// or on the main isolate on iOS (security-scoped access).
  static List<PdfEntry> _scanSync(String folderPath) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) {
      dev.log(
        'Directory does not exist: $folderPath',
        name: 'folder_scanner',
      );
      return [];
    }

    final entries = <PdfEntry>[];

    try {
      // On iOS, security-scoped folder access only covers the picked
      // directory itself. Recursive traversal and followLinks:false both
      // break in the iOS sandbox. Use the simple top-level listing that
      // worked in build 2.
      final entities = _isIos
          ? dir.listSync()
          : dir.listSync(recursive: true, followLinks: false);

      for (final entity in entities) {
        if (entity is File) {
          final path = entity.path;
          if (path.toLowerCase().endsWith('.pdf')) {
            final name = path.split(Platform.pathSeparator).last;
            entries.add(PdfEntry(filePath: path, fileName: name));
          }
        }
      }
    } on FileSystemException catch (e) {
      dev.log(
        'Cannot read folder: ${e.message}',
        name: 'folder_scanner',
      );
      // Return whatever we found before the error
    }

    entries.sort(
      (a, b) => a.fileName.compareTo(b.fileName),
    );
    return entries;
  }
}

/// Riverpod provider that watches config for folder path changes.
/// Returns a FutureProvider since folder scanning now runs in an isolate.
final pdfListProvider = FutureProvider<List<PdfEntry>>((ref) async {
  final config = ref.watch(configProvider);
  return config.when(
    data: (c) => FolderScannerService.scanAsync(c.pdfFolderPath),
    loading: () async => [],
    error: (_, __) async => [],
  );
});
