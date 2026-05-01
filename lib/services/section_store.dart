import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:runthru/services/models.dart';

/// Number of sentences per section (configurable constant).
const int kSectionSize = 200;

/// Disk-level I/O for the section-based persistence layer.
///
/// Storage layout:
///   <appSupport>/pdf_store/<fileHash>/manifest.json
///   <appSupport>/pdf_store/<fileHash>/section_000.json
///   ...
///
/// All I/O runs in Isolates — never on the main event loop.
class SectionStore {
  SectionStore._();

  static String? _storeRoot;

  /// Lazily resolve the root directory for all section stores.
  static Future<String?> _root() async {
    if (_storeRoot != null) return _storeRoot;
    try {
      final appDir = await getApplicationSupportDirectory();
      final dir = Directory('${appDir.path}/pdf_store');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _storeRoot = dir.path;
      return _storeRoot;
    } on FileSystemException {
      return null;
    }
  }

  /// Compute a stable hash for a PDF file path + last-modified time.
  /// SHA-256 truncated to 16 hex chars.
  static String fileHash(String filePath) {
    final file = File(filePath);
    String modified;
    try {
      modified =
          file.existsSync() ? file.lastModifiedSync().toIso8601String() : '';
    } on FileSystemException {
      modified = '';
    }
    final input = '$filePath|$modified';
    final digest = sha256.convert(utf8.encode(input));
    return digest.toString().substring(0, 16);
  }

  /// Returns the store directory for a specific PDF hash.
  static Future<String?> storeDir(String hash) async {
    final root = await _root();
    if (root == null) return null;
    return '$root/$hash';
  }

  /// Save a section to disk in an isolate.
  static Future<void> saveSectionInIsolate(
    String storeDir,
    int sectionIndex,
    SectionData data,
  ) async {
    await Isolate.run(() => _saveSection(storeDir, sectionIndex, data));
  }

  /// Load a section from disk in an isolate.
  static Future<SectionData?> loadSectionInIsolate(
    String storeDir,
    int sectionIndex,
  ) async {
    return Isolate.run(() => _loadSection(storeDir, sectionIndex));
  }

  /// Save manifest to disk in an isolate.
  static Future<void> saveManifestInIsolate(
    String storeDir,
    DocumentManifest manifest,
  ) async {
    await Isolate.run(() => _saveManifest(storeDir, manifest));
  }

  /// Load manifest from disk in an isolate.
  static Future<DocumentManifest?> loadManifestInIsolate(
    String storeDir,
  ) async {
    return Isolate.run(() => _loadManifest(storeDir));
  }

  /// Check whether a section store exists for the given hash.
  static Future<bool> hasStore(String hash) async {
    final dir = await storeDir(hash);
    if (dir == null) return false;
    return File('$dir/manifest.json').existsSync();
  }

  /// Delete an entire store directory for a given hash.
  static Future<void> deleteStore(String hash) async {
    final dir = await storeDir(hash);
    if (dir == null) return;
    final d = Directory(dir);
    if (d.existsSync()) {
      d.deleteSync(recursive: true);
    }
  }

  /// Compute total disk usage of all section stores in bytes.
  static Future<int> totalDiskUsage() async {
    final root = await _root();
    if (root == null) return 0;
    return Isolate.run(() => _computeDiskUsage(root));
  }

  /// Get the store index file (tracks last-opened timestamps for LRU).
  static Future<StoreIndex> loadStoreIndex() async {
    final root = await _root();
    if (root == null) return const StoreIndex(entries: {});
    return Isolate.run(() => _loadStoreIndex(root));
  }

  /// Persist the store index.
  static Future<void> saveStoreIndex(StoreIndex index) async {
    final root = await _root();
    if (root == null) return;
    await Isolate.run(() => _saveStoreIndex(root, index));
  }

  /// Evict stores until total usage is under [budgetBytes].
  static Future<void> evictIfOverBudget({
    int budgetBytes = 200 * 1024 * 1024,
  }) async {
    final root = await _root();
    if (root == null) return;
    await Isolate.run(() => _evict(root, budgetBytes));
  }

  /// Divide an ExtractedDocument into sections.
  static List<SectionData> splitIntoSections(ExtractedDocument doc) {
    final sections = <SectionData>[];
    for (var i = 0; i < doc.sentences.length; i += kSectionSize) {
      final end = (i + kSectionSize).clamp(0, doc.sentences.length);
      sections.add(SectionData(
        sectionIndex: i ~/ kSectionSize,
        startSentenceIndex: i,
        sentences: doc.sentences.sublist(i, end),
      ));
    }
    return sections;
  }

  /// Build a manifest from a document and its file path.
  static DocumentManifest buildManifest(
    String filePath,
    String hash,
    ExtractedDocument doc,
  ) {
    return DocumentManifest(
      filePath: filePath,
      fileHash: hash,
      totalSentences: doc.sentences.length,
      totalWords: doc.totalWords,
      totalSections:
          (doc.sentences.length / kSectionSize).ceil().clamp(1, 999999),
      sectionSize: kSectionSize,
      lastModified: DateTime.now(),
      createdAt: DateTime.now(),
    );
  }
}

// ── Top-level isolate functions ────────────────────────────────────────

String _sectionFileName(int index) =>
    'section_${index.toString().padLeft(3, '0')}.json';

void _saveSection(String storeDir, int sectionIndex, SectionData data) {
  final dir = Directory(storeDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final file = File('$storeDir/${_sectionFileName(sectionIndex)}');
  file.writeAsStringSync(jsonEncode(data.toJson()));
}

SectionData? _loadSection(String storeDir, int sectionIndex) {
  final file = File('$storeDir/${_sectionFileName(sectionIndex)}');
  if (!file.existsSync()) return null;
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    return SectionData.fromJson(json);
  } on Object {
    return null;
  }
}

void _saveManifest(String storeDir, DocumentManifest manifest) {
  final dir = Directory(storeDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final file = File('$storeDir/manifest.json');
  file.writeAsStringSync(jsonEncode(manifest.toJson()));
}

DocumentManifest? _loadManifest(String storeDir) {
  final file = File('$storeDir/manifest.json');
  if (!file.existsSync()) return null;
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    return DocumentManifest.fromJson(json);
  } on Object {
    return null;
  }
}

int _computeDiskUsage(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return 0;
  var total = 0;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      try {
        total += entity.lengthSync();
      } on FileSystemException {
        // skip
      }
    }
  }
  return total;
}

StoreIndex _loadStoreIndex(String root) {
  final file = File('$root/store_index.json');
  if (!file.existsSync()) return const StoreIndex(entries: {});
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    return StoreIndex.fromJson(json);
  } on Object {
    return const StoreIndex(entries: {});
  }
}

void _saveStoreIndex(String root, StoreIndex index) {
  final file = File('$root/store_index.json');
  file.writeAsStringSync(jsonEncode(index.toJson()));
}

void _evict(String root, int budgetBytes) {
  final dir = Directory(root);
  if (!dir.existsSync()) return;

  // Calculate total usage
  var total = _computeDiskUsage(root);
  if (total <= budgetBytes) return;

  // Load store index for LRU ordering
  final index = _loadStoreIndex(root);
  final entries = index.entries.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));

  for (final entry in entries) {
    if (total <= budgetBytes) break;
    final storeDir = Directory('$root/${entry.key}');
    if (!storeDir.existsSync()) continue;
    var storeSize = 0;
    for (final f in storeDir.listSync(recursive: true)) {
      if (f is File) {
        try {
          storeSize += f.lengthSync();
        } on FileSystemException {
          // skip
        }
      }
    }
    storeDir.deleteSync(recursive: true);
    total -= storeSize;
  }
}
