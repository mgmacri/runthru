import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/section_store.dart';

/// One-time migration from the old flat-JSON pdf_cache to section-based storage.
///
/// Run at app startup. If the old cache directory exists, migrate each file
/// then delete the old directory. Failures for individual files are non-fatal.
class CacheMigration {
  CacheMigration._();

  /// Returns true if there are old cache files to migrate.
  static Future<bool> needsMigration() async {
    final oldDir = await _oldCacheDir();
    return oldDir != null && oldDir.existsSync();
  }

  /// Migrate all old cache files to section-based format.
  /// Returns the number of files successfully migrated.
  static Future<int> migrate() async {
    final oldDir = await _oldCacheDir();
    if (oldDir == null || !oldDir.existsSync()) return 0;

    var migrated = 0;
    final files = oldDir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.json') && !f.path.endsWith('_preview.json'))
        .toList();

    for (final file in files) {
      try {
        final success = await _migrateFile(file);
        if (success) migrated++;
      } on Object catch (e) {
        dev.log('Migration failed for ${file.path}: $e',
            name: 'cache_migration');
        // Delete the failed old entry so it re-extracts later
        try {
          file.deleteSync();
        } on FileSystemException {
          // ignore
        }
      }
    }

    // Delete old cache directory after migration
    try {
      oldDir.deleteSync(recursive: true);
      dev.log('Old cache directory deleted', name: 'cache_migration');
    } on FileSystemException catch (e) {
      dev.log('Failed to delete old cache dir: $e', name: 'cache_migration');
    }

    return migrated;
  }

  static Future<Directory?> _oldCacheDir() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final dir = Directory('${appDir.path}/pdf_cache');
      return dir;
    } on Object {
      return null;
    }
  }

  static Future<bool> _migrateFile(File oldFile) async {
    return Isolate.run(() => _migrateInIsolate(oldFile.path));
  }
}

/// Top-level function for isolate execution.
bool _migrateInIsolate(String oldFilePath) {
  final file = File(oldFilePath);
  if (!file.existsSync()) return false;

  final raw = file.readAsStringSync();
  final json = jsonDecode(raw) as Map<String, Object?>;
  final doc = ExtractedDocument.fromJson(json);

  if (doc.sentences.isEmpty) return false;

  // Extract filename without extension as a pseudo-path
  final baseName =
      oldFilePath.split(Platform.pathSeparator).last.replaceAll('.json', '');

  // Use the old cache key as the hash
  final hash = baseName;

  // Determine store directory — we can't use async path_provider in an isolate,
  // so derive from the old file's parent
  final oldDir = file.parent.path;
  final storeRoot = oldDir.replaceAll('pdf_cache', 'pdf_store');
  final storeDir = '$storeRoot/$hash';

  final dir = Directory(storeDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);

  // Split into sections
  final sections = <SectionData>[];
  for (var i = 0; i < doc.sentences.length; i += kSectionSize) {
    final end = (i + kSectionSize).clamp(0, doc.sentences.length);
    sections.add(SectionData(
      sectionIndex: i ~/ kSectionSize,
      startSentenceIndex: i,
      sentences: doc.sentences.sublist(i, end),
    ));
  }

  // Write sections
  for (final section in sections) {
    final secFile = File(
        '$storeDir/section_${section.sectionIndex.toString().padLeft(3, '0')}.json');
    secFile.writeAsStringSync(jsonEncode(section.toJson()));
  }

  // Write manifest
  final manifest = DocumentManifest(
    filePath: '', // Unknown from old cache
    fileHash: hash,
    totalSentences: doc.sentences.length,
    totalWords: doc.totalWords,
    totalSections: sections.length,
    sectionSize: kSectionSize,
    lastModified: DateTime.now(),
    createdAt: DateTime.now(),
  );
  final manifestFile = File('$storeDir/manifest.json');
  manifestFile.writeAsStringSync(jsonEncode(manifest.toJson()));

  return true;
}
