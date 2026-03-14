import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/store/config.dart';

/// Scans a folder for top-level .pdf files.
class FolderScannerService {
  FolderScannerService._();

  static List<PdfEntry> scan(String? folderPath) {
    if (folderPath == null || folderPath.isEmpty) return [];

    final dir = Directory(folderPath);
    if (!dir.existsSync()) return [];

    final entries = <PdfEntry>[];
    for (final entity in dir.listSync()) {
      if (entity is File) {
        final path = entity.path;
        if (path.toLowerCase().endsWith('.pdf')) {
          final name = path.split(Platform.pathSeparator).last;
          entries.add(PdfEntry(filePath: path, fileName: name));
        }
      }
    }

    entries.sort(
      (a, b) => a.fileName.compareTo(b.fileName),
    );
    return entries;
  }
}

/// Riverpod provider that watches config for folder path changes.
final pdfListProvider = Provider<List<PdfEntry>>((ref) {
  final config = ref.watch(configProvider);
  return config.when(
    data: (c) => FolderScannerService.scan(c.pdfFolderPath),
    loading: () => [],
    error: (_, __) => [],
  );
});
