import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/core/logger.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/store/config.dart';

/// Scans a folder recursively for .pdf files.
class FolderScannerService {
  FolderScannerService._();

  static bool get _isIos => !kIsWeb && Platform.isIOS;

  static const String _tag = 'folder_scanner';

  /// Scan for PDFs.
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
      if (_isIos) {
        // Security-scoped resource — must stay on the main isolate.
        return _scanSync(folderPath);
      }
      return await Isolate.run(() => _scanSync(folderPath));
    } on Object catch (e, st) {
      appLog(_tag, 'scanAsync EXCEPTION: $e\n$st');
      return [];
    }
  }

  /// Synchronous scan — runs in an isolate on Android/desktop,
  /// or on the main isolate on iOS (security-scoped access).
  static List<PdfEntry> _scanSync(String folderPath) {
    appLog(_tag, '_scanSync — path=$folderPath');

    final dir = Directory(folderPath);
    final exists = dir.existsSync();
    appLog(_tag, '_scanSync — existsSync=$exists');

    if (!exists) {
      appLog(_tag, '_scanSync — directory does not exist, returning []');
      return [];
    }

    final entries = <PdfEntry>[];

    try {
      final entities = _isIos
          ? dir.listSync()
          : dir.listSync(recursive: true, followLinks: false);

      appLog(_tag, '_scanSync — listSync returned ${entities.length} entities');

      for (final entity in entities) {
        final type = entity is File
            ? 'File'
            : entity is Directory
                ? 'Dir'
                : entity.runtimeType.toString();
        appLog(_tag, '  entity: $type ${entity.path}');

        if (entity is File) {
          final path = entity.path;
          if (path.toLowerCase().endsWith('.pdf')) {
            final name = path.split(Platform.pathSeparator).last;
            entries.add(PdfEntry(filePath: path, fileName: name));
          }
        }
      }
    } on FileSystemException catch (e) {
      appLog(_tag, '_scanSync FileSystemException: ${e.message} (${e.path})');
    } on Object catch (e) {
      appLog(_tag, '_scanSync unexpected error: $e');
    }

    appLog(_tag, '_scanSync — found ${entries.length} PDFs');
    entries.sort((a, b) => a.fileName.compareTo(b.fileName));
    return entries;
  }
}

/// Riverpod provider that watches config for folder path changes.
/// Returns a FutureProvider since folder scanning now runs in an isolate.
final pdfListProvider = FutureProvider<List<PdfEntry>>((ref) async {
  final config = ref.watch(configProvider);
  return config.when(
    data: (c) {
      appLog('pdfListProvider', 'config loaded — folder=${c.pdfFolderPath}');
      return FolderScannerService.scanAsync(c.pdfFolderPath);
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
