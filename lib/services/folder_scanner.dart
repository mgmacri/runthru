import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/store/config.dart';

/// Scans a folder recursively for .pdf files.
class FolderScannerService {
  FolderScannerService._();

  /// Scan in a background isolate so the UI never blocks.
  static Future<List<PdfEntry>> scanAsync(String? folderPath) async {
    if (folderPath == null || folderPath.isEmpty) return [];
    try {
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

  /// Synchronous scan — intended to run inside an isolate.
  static List<PdfEntry> _scanSync(String folderPath) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return [];

    final entries = <PdfEntry>[];

    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
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
