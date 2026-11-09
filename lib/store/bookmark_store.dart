/// Standalone bookmark store (BK-5).
///
/// Bookmarks used to live inside the single `runthru_config` blob, which was
/// re-serialized in full every 5 seconds during reading and grew without
/// bound. Here every bookmark is its own SharedPreferences entry
/// (`runthru_bm_<path>`), so a position save writes one small record — never
/// the whole map, never the config.
///
/// Identity: entries are keyed by file path (the locator readers have in
/// hand) and carry the book's content hash. When a re-import gives the same
/// content a new path, [resolve] finds the bookmark by hash and re-keys it —
/// the reader resumes exactly where the user left off.
///
/// Migration: on first load, bookmarks found in the legacy config blob are
/// copied here once. The originals stay in the config (read-only, rollback
/// path); they just stop being written.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/services/preprocessing_queue.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kPrefix = 'runthru_bm_';
const String _kMigratedFlag = 'runthru_bookmarks_migrated_v1';

/// Matches non-local content ids (`instapaper://…`, `drive://…`) that the
/// local-source prune must never touch.
final RegExp _kRemoteScheme = RegExp(r'^[a-z][a-z0-9+.-]*://');

/// Manages per-book bookmarks. State maps file path → [BookmarkData].
class BookmarkStoreNotifier extends AsyncNotifier<Map<String, BookmarkData>> {
  Future<void> _chain = Future<void>.value();

  @override
  Future<Map<String, BookmarkData>> build() => _load();

  Future<Map<String, BookmarkData>> _load() async {
    final map = <String, BookmarkData>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_kPrefix)) continue;
        final raw = prefs.getString(key);
        if (raw == null) continue;
        try {
          map[key.substring(_kPrefix.length)] = BookmarkData.fromJson(
            jsonDecode(raw) as Map<String, Object?>,
          );
        } on Object {
          // Corrupt entry — skip it, never the whole store.
        }
      }

      // One-time copy from the legacy config blob (originals untouched).
      if (!(prefs.getBool(_kMigratedFlag) ?? false)) {
        final config = await ref.read(configProvider.future);
        var copied = 0;
        for (final entry in config.bookmarks.entries) {
          if (map.containsKey(entry.key)) continue;
          map[entry.key] = entry.value;
          await prefs.setString(
            '$_kPrefix${entry.key}',
            jsonEncode(entry.value.toJson()),
          );
          copied++;
        }
        await prefs.setBool(_kMigratedFlag, true);
        if (copied > 0) {
          appLog('bookmark_store', 'migrated $copied bookmark(s) from config');
        }
      }
    } on Object catch (e) {
      appLog('bookmark_store', 'load failed: $e');
    }
    return map;
  }

  String? _hashFor(String filePath) {
    try {
      return ref
          .read(preprocessingQueueProvider.notifier)
          .contentHashOf(filePath);
    } on Object {
      return null;
    }
  }

  /// Returns the bookmark for [filePath]. When the path is unknown but the
  /// same content exists under an old path (re-import), the bookmark is
  /// found by content hash and silently re-keyed to the new path.
  BookmarkData? resolve(String filePath) {
    final map = state.valueOrNull;
    if (map == null) return null;
    final direct = map[filePath];
    if (direct != null) return direct;

    final hash = _hashFor(filePath);
    if (hash == null) return null;
    return resolveByContentHash(hash, adoptPath: filePath);
  }

  /// Looks up a bookmark by content hash. With [adoptPath] set, a match
  /// found under another path is re-keyed to it (re-import adoption).
  BookmarkData? resolveByContentHash(String hash, {String? adoptPath}) {
    final map = state.valueOrNull;
    if (map == null) return null;
    for (final entry in map.entries) {
      if (entry.value.contentHash == hash) {
        if (adoptPath != null && entry.key != adoptPath) {
          unawaited(_rekey(entry.key, adoptPath, entry.value));
        }
        return entry.value;
      }
    }
    return null;
  }

  /// Saves the bookmark for [filePath] — one entry written, nothing else.
  Future<void> save(String filePath, BookmarkData data) {
    final stamped = data.contentHash == null
        ? data.copyWith(contentHash: _hashFor(filePath))
        : data;
    final map = Map<String, BookmarkData>.from(state.valueOrNull ?? const {});
    map[filePath] = stamped;
    state = AsyncData(map);
    return _serialise((prefs) async {
      await prefs.setString('$_kPrefix$filePath', jsonEncode(stamped.toJson()));
    });
  }

  /// Removes entries for local files that no longer exist in any source.
  /// Remote-scheme ids and entries whose content hash is still active are
  /// kept. Returns the number of pruned entries.
  Future<int> pruneMissingLocal({
    required Set<String> activePaths,
    required Set<String> activeHashes,
  }) async {
    final map = Map<String, BookmarkData>.from(state.valueOrNull ?? const {});
    final doomed = <String>[];
    for (final entry in map.entries) {
      final path = entry.key;
      if (_kRemoteScheme.hasMatch(path)) continue;
      if (activePaths.contains(path)) continue;
      final hash = entry.value.contentHash;
      if (hash != null && activeHashes.contains(hash)) continue;
      doomed.add(path);
    }
    if (doomed.isEmpty) return 0;
    for (final path in doomed) {
      map.remove(path);
    }
    state = AsyncData(map);
    await _serialise((prefs) async {
      for (final path in doomed) {
        await prefs.remove('$_kPrefix$path');
      }
    });
    appLog('bookmark_store', 'pruned ${doomed.length} orphaned bookmark(s)');
    return doomed.length;
  }

  Future<void> _rekey(String oldPath, String newPath, BookmarkData data) async {
    final map = Map<String, BookmarkData>.from(state.valueOrNull ?? const {});
    map.remove(oldPath);
    map[newPath] = data;
    state = AsyncData(map);
    await _serialise((prefs) async {
      await prefs.setString('$_kPrefix$newPath', jsonEncode(data.toJson()));
      await prefs.remove('$_kPrefix$oldPath');
    });
    appLog('bookmark_store', 'bookmark re-keyed after re-import');
  }

  Future<void> _serialise(
    Future<void> Function(SharedPreferences prefs) action,
  ) {
    final next = _chain.then((_) async {
      try {
        await action(await SharedPreferences.getInstance());
      } on Object catch (e) {
        appLog('bookmark_store', 'write failed: $e');
      }
    });
    _chain = next;
    return next;
  }
}

/// App-wide bookmark store.
final bookmarkStoreProvider =
    AsyncNotifierProvider<BookmarkStoreNotifier, Map<String, BookmarkData>>(
      BookmarkStoreNotifier.new,
    );
