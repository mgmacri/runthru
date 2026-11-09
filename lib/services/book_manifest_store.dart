/// Durable per-book extraction manifest: page counts and chunked-extraction
/// progress.
///
/// Two jobs:
///  * **Page counts** — startup must never reopen every PDF just to count
///    pages (BK-3). Counted once, remembered here.
///  * **Chunk progress** — phase-2 extraction commits `lastCompletedPage`
///    after every chunk, so a book that needs ten minutes of extraction
///    completes across app launches instead of restarting from page 3 (BK-7).
///
/// Entries are keyed by `path|size|mtime` so a changed file is re-counted
/// automatically. The map is bounded; oldest entries fall off.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kManifestKey = 'runthru_book_manifest_v1';

/// One book's durable extraction facts.
class BookManifestEntry {
  /// Creates a manifest entry.
  const BookManifestEntry({
    required this.pageCount,
    this.lastCompletedPage = 0,
  });

  /// Rebuilds from JSON.
  factory BookManifestEntry.fromJson(Map<String, Object?> json) {
    return BookManifestEntry(
      pageCount: json['pageCount'] as int? ?? 0,
      lastCompletedPage: json['lastCompletedPage'] as int? ?? 0,
    );
  }

  /// Total pages (or EPUB chapters).
  final int pageCount;

  /// Highest page index + 1 whose extraction has been committed.
  final int lastCompletedPage;

  /// Serialises to JSON.
  Map<String, Object?> toJson() => {
    'pageCount': pageCount,
    'lastCompletedPage': lastCompletedPage,
  };
}

/// SharedPreferences-backed manifest with serialized writes.
class BookManifestStore {
  /// Max remembered books; oldest entries are dropped beyond this.
  static const int maxEntries = 2000;

  Future<void> _chain = Future<void>.value();
  Map<String, BookManifestEntry>? _cache;

  /// Returns the manifest entry for [path], or null when unknown or the
  /// file changed since it was recorded.
  Future<BookManifestEntry?> entryFor(String path) async {
    final key = await _statKey(path);
    if (key == null) return null;
    await _ensureLoaded();
    return _cache?[key];
  }

  /// Records the page count for [path] (resets chunk progress when the
  /// count changed).
  Future<void> setPageCount(String path, int pageCount) {
    return _mutate(path, (existing) {
      if (existing != null && existing.pageCount == pageCount) return existing;
      return BookManifestEntry(pageCount: pageCount);
    });
  }

  /// Commits chunked-extraction progress for [path].
  Future<void> setProgress(
    String path, {
    required int lastCompletedPage,
    required int pageCount,
  }) {
    return _mutate(
      path,
      (_) => BookManifestEntry(
        pageCount: pageCount,
        lastCompletedPage: lastCompletedPage,
      ),
    );
  }

  Future<void> _mutate(
    String path,
    BookManifestEntry? Function(BookManifestEntry? existing) update,
  ) {
    final next = _chain.then((_) async {
      final key = await _statKey(path);
      if (key == null) return;
      await _ensureLoaded();
      final cache = _cache;
      if (cache == null) return;
      final updated = update(cache[key]);
      if (updated == null || identical(updated, cache[key])) return;
      // Re-insert to refresh recency, then bound the map.
      cache.remove(key);
      cache[key] = updated;
      while (cache.length > maxEntries) {
        cache.remove(cache.keys.first);
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _kManifestKey,
          jsonEncode(cache.map((k, v) => MapEntry(k, v.toJson()))),
        );
      } on Object catch (e) {
        appLog('book_manifest', 'persist failed: $e');
      }
    });
    _chain = next.catchError((Object _) {});
    return next;
  }

  Future<void> _ensureLoaded() async {
    if (_cache != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kManifestKey);
      if (raw == null) {
        _cache = {};
        return;
      }
      final json = jsonDecode(raw) as Map<String, Object?>;
      _cache = json.map(
        (k, v) => MapEntry(
          k,
          BookManifestEntry.fromJson(v as Map<String, Object?>),
        ),
      );
    } on Object catch (e) {
      appLog('book_manifest', 'load failed: $e');
      _cache = {};
    }
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
}

/// App-wide book manifest store.
final bookManifestStoreProvider = Provider<BookManifestStore>(
  (ref) => BookManifestStore(),
);
