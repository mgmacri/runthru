/// Content-hash identity resolution with an on-disk memo index.
///
/// Hashing a file means reading every byte, so the digest is computed at most
/// once per `(path, size, mtime)` and memoised in `content_index.json` under
/// the app-support directory. Lookups after that are a single `stat()` —
/// startup never re-reads file bytes for known files.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:runthru/core/logger.dart';

/// Resolves and memoises content hashes (sha256 of file bytes).
class ContentIdentityService {
  /// Creates the service. [rootResolver] is injectable for tests; it returns
  /// the directory holding `content_index.json`, or null when storage is
  /// unavailable (all operations then degrade to null results).
  ContentIdentityService({Future<String?> Function()? rootResolver})
    : _rootResolver = rootResolver ?? _defaultRoot;

  final Future<String?> Function() _rootResolver;

  /// `path|size|mtimeMs` → sha256 hex. Insertion-ordered; oldest dropped
  /// beyond [_maxIndexEntries].
  Map<String, String>? _index;
  Future<void> _chain = Future<void>.value();

  /// Bound on memoised entries so the index never grows without limit.
  static const int _maxIndexEntries = 5000;

  static const String _indexFileName = 'content_index.json';

  static Future<String?> _defaultRoot() async {
    try {
      return (await getApplicationSupportDirectory()).path;
    } on Object {
      return null;
    }
  }

  /// Returns the memoised content hash for [path] without reading file
  /// bytes, or null when the file is missing or has not been hashed yet.
  Future<String?> knownHashFor(String path) async {
    final key = await _statKey(path);
    if (key == null) return null;
    await _ensureLoaded();
    return _index?[key];
  }

  /// Returns the content hash for [path], computing it (in an isolate) and
  /// memoising it if needed. Null when the file is unreadable.
  Future<String?> ensureHash(String path) async {
    final key = await _statKey(path);
    if (key == null) return null;
    await _ensureLoaded();
    final known = _index?[key];
    if (known != null) return known;

    String? hash;
    try {
      hash = await Isolate.run(() => hashFileSync(path));
    } on Object catch (e) {
      appLog('content-identity', 'hash failed: $e');
      return null;
    }
    if (hash == null) return null;

    final index = _index;
    if (index != null) {
      index[key] = hash;
      while (index.length > _maxIndexEntries) {
        index.remove(index.keys.first);
      }
      _schedulePersist();
    }
    return hash;
  }

  Future<String?> _statKey(String path) async {
    try {
      final stat = await File(path).stat();
      if (stat.type == FileSystemEntityType.notFound) return null;
      return '$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
    } on Object {
      return null;
    }
  }

  Future<void> _ensureLoaded() async {
    if (_index != null) return;
    final root = await _rootResolver();
    if (root == null) {
      _index = {};
      return;
    }
    try {
      final file = File('$root/$_indexFileName');
      if (!file.existsSync()) {
        _index = {};
        return;
      }
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      _index = decoded.map((k, v) => MapEntry(k, v as String? ?? ''))
        ..removeWhere((_, v) => v.isEmpty);
    } on Object catch (e) {
      appLog('content-identity', 'index load failed: $e');
      _index = {};
    }
  }

  void _schedulePersist() {
    _chain = _chain.then((_) async {
      final root = await _rootResolver();
      final index = _index;
      if (root == null || index == null) return;
      try {
        final file = File('$root/$_indexFileName');
        await file.writeAsString(jsonEncode(index));
      } on Object catch (e) {
        appLog('content-identity', 'index persist failed: $e');
      }
    });
  }

  /// Streamed sha256 of a file's bytes. Synchronous — call inside an isolate.
  static String? hashFileSync(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    Digest? digest;
    final output = ChunkedConversionSink<Digest>.withCallback(
      (digests) => digest = digests.single,
    );
    final input = sha256.startChunkedConversion(output);
    final raf = file.openSync();
    try {
      const chunkSize = 1 << 20; // 1 MB — bounded memory for any file size.
      while (true) {
        final bytes = raf.readSync(chunkSize);
        if (bytes.isEmpty) break;
        input.add(bytes);
      }
    } finally {
      raf.closeSync();
    }
    input.close();
    return digest?.toString();
  }
}

/// App-wide content identity service.
final contentIdentityProvider = Provider<ContentIdentityService>(
  (ref) => ContentIdentityService(),
);
