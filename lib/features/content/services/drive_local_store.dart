/// Persistent local copies of imported Google Drive files (BK-9).
///
/// After a successful Drive import the downloaded file is kept under the
/// app's documents directory, named by its content hash:
///
///   <docs>/drive_imports/index.json            (fileId → hash/name/mime)
///   <docs>/drive_imports/<contentHash>.<ext>
///
/// "Continue Reading" re-opens from the local copy — never re-downloads,
/// never re-extracts (the extracted text lives in the content store under
/// the same hash). Local copies are evictable derived data; losing one only
/// costs a re-download on the next open.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:runthru/core/logger.dart';

/// Index record for one persisted Drive file.
class DriveLocalCopy {
  /// Creates a record.
  const DriveLocalCopy({
    required this.fileId,
    required this.contentHash,
    required this.name,
    required this.mimeType,
    required this.localPath,
  });

  /// Rebuilds a record from JSON (the local path is derived, not stored).
  factory DriveLocalCopy.fromJson(Map<String, Object?> json, String dirPath) {
    final hash = json['contentHash'] as String? ?? '';
    final ext = json['ext'] as String? ?? 'bin';
    return DriveLocalCopy(
      fileId: json['fileId'] as String? ?? '',
      contentHash: hash,
      name: json['name'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
      localPath: '$dirPath/$hash.$ext',
    );
  }

  /// Drive file ID.
  final String fileId;

  /// Content hash — identity shared with the content store.
  final String contentHash;

  /// User-visible name.
  final String name;

  /// Drive MIME type.
  final String mimeType;

  /// Absolute path of the local copy.
  final String localPath;

  /// Serialises to JSON.
  Map<String, Object?> toJson() => {
    'fileId': fileId,
    'contentHash': contentHash,
    'name': name,
    'mimeType': mimeType,
    'ext': localPath.split('.').last,
  };
}

/// Manages the on-disk index and copies of imported Drive files.
class DriveLocalStore {
  /// Creates the store. [rootResolver] is injectable for tests.
  DriveLocalStore({Future<String?> Function()? rootResolver})
    : _rootResolver = rootResolver ?? _defaultRoot;

  final Future<String?> Function() _rootResolver;
  Future<void> _chain = Future<void>.value();

  static const String _tag = 'drive_local_store';

  static Future<String?> _defaultRoot() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      return '${docs.path}/drive_imports';
    } on Object {
      return null;
    }
  }

  Future<String?> _dir() async {
    final root = await _rootResolver();
    if (root == null) return null;
    try {
      final dir = Directory(root);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return root;
    } on FileSystemException {
      return null;
    }
  }

  /// Returns the persisted copy for [fileId] if its bytes still exist.
  Future<DriveLocalCopy?> lookup(String fileId) async {
    final dir = await _dir();
    if (dir == null) return null;
    final index = await _loadIndex(dir);
    final record = index[fileId];
    if (record == null) return null;
    if (!File(record.localPath).existsSync()) return null;
    return record;
  }

  /// Persists [sourceFile] (a completed download) as the local copy for
  /// [fileId] under [contentHash]. Returns the stored record.
  Future<DriveLocalCopy?> persist({
    required String fileId,
    required String contentHash,
    required String name,
    required String mimeType,
    required File sourceFile,
    required String extension,
  }) async {
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final target = File('$dir/$contentHash.$extension');
      if (!target.existsSync()) {
        await sourceFile.copy(target.path);
      }
      final record = DriveLocalCopy(
        fileId: fileId,
        contentHash: contentHash,
        name: name,
        mimeType: mimeType,
        localPath: target.path,
      );
      await _updateIndex(dir, (index) => index[fileId] = record);
      appLog(_tag, 'persisted drive import name=$name');
      return record;
    } on Object catch (e) {
      appLog(_tag, 'persist failed name=$name: $e');
      return null;
    }
  }

  /// Total bytes used by local Drive copies (for the shared cache budget).
  Future<int> totalUsageBytes() async {
    final dir = await _dir();
    if (dir == null) return 0;
    var total = 0;
    try {
      for (final f in Directory(dir).listSync().whereType<File>()) {
        total += f.lengthSync();
      }
    } on FileSystemException {
      // partial total is fine
    }
    return total;
  }

  Future<Map<String, DriveLocalCopy>> _loadIndex(String dir) async {
    try {
      final file = File('$dir/index.json');
      if (!file.existsSync()) return {};
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return json.map(
        (k, v) => MapEntry(
          k,
          DriveLocalCopy.fromJson(v as Map<String, Object?>, dir),
        ),
      );
    } on Object {
      return {};
    }
  }

  Future<void> _updateIndex(
    String dir,
    void Function(Map<String, DriveLocalCopy> index) mutate,
  ) {
    final next = _chain.then((_) async {
      try {
        final index = await _loadIndex(dir);
        mutate(index);
        await File('$dir/index.json').writeAsString(
          jsonEncode(index.map((k, v) => MapEntry(k, v.toJson()))),
        );
      } on Object catch (e) {
        appLog(_tag, 'index update failed: $e');
      }
    });
    _chain = next.catchError((Object _) {});
    return next;
  }

  /// Deletes orphaned `runthru-drive-*` temp files older than [maxAge]
  /// from [tempDir]. Deterministic cleanup for interrupted imports.
  static Future<int> sweepTempFiles(
    Directory tempDir, {
    Duration maxAge = const Duration(hours: 24),
  }) async {
    var removed = 0;
    try {
      final cutoff = DateTime.now().subtract(maxAge);
      for (final entity in tempDir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith('runthru-drive-')) continue;
        try {
          if (entity.lastModifiedSync().isBefore(cutoff)) {
            entity.deleteSync();
            removed++;
          }
        } on FileSystemException {
          // skip
        }
      }
      if (removed > 0) {
        appLog(_tag, 'swept $removed orphaned drive temp file(s)');
      }
    } on Object catch (e) {
      appLog(_tag, 'temp sweep failed: $e');
    }
    return removed;
  }
}

/// App-wide Drive local-copy store.
final driveLocalStoreProvider = Provider<DriveLocalStore>(
  (ref) => DriveLocalStore(),
);
