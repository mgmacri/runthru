import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/store/library_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the persisted library sources list.
const _sourcesKey = 'runthru_library_sources';

/// Legacy single-folder config key, read once for migration.
const _legacyConfigKey = 'runthru_config';

/// Deletes an owned library source from local storage.
typedef LibrarySourceDelete = Future<void> Function(LibrarySource source);

/// Thrown when RunThru cannot delete files it owns for a library source.
///
/// Removal is aborted in this case so the persisted source list still matches
/// the files left on disk.
class LibrarySourceRemovalException implements Exception {
  /// Creates a source-removal failure for [locator].
  const LibrarySourceRemovalException(this.locator, this.cause);

  /// Filesystem path that could not be removed.
  final String locator;

  /// Original filesystem exception or error.
  final Object cause;

  @override
  String toString() => 'LibrarySourceRemovalException($locator): $cause';
}

/// Riverpod AsyncNotifier managing the user's library sources (folders + files).
///
/// Persisted independently of `AppConfig` so that adding/removing a source
/// never rewrites unrelated settings, and so the library can grow without
/// bloating the config blob. The scanned books are derived from these sources
/// by `pdfListProvider`.
class LibrarySourcesNotifier extends AsyncNotifier<List<LibrarySource>> {
  /// Creates a library-source notifier.
  LibrarySourcesNotifier({LibrarySourceDelete? deleteOwnedSource})
    : _deleteOwnedSource = deleteOwnedSource ?? _deleteOwnedFromDisk;

  final LibrarySourceDelete _deleteOwnedSource;
  Completer<void>? _lock;
  int _idCounter = 0;

  @override
  Future<List<LibrarySource>> build() => _load();

  Future<T> _synchronized<T>(Future<T> Function() action) async {
    while (_lock != null) {
      await _lock!.future;
    }
    _lock = Completer<void>();
    try {
      return await action();
    } finally {
      final l = _lock;
      _lock = null;
      l?.complete();
    }
  }

  Future<List<LibrarySource>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sourcesKey);

    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List<Object?>)
            .map((e) => LibrarySource.fromJson(e! as Map<String, Object?>))
            .toList();
        return list;
      } on Object catch (e) {
        appLog('library_sources', 'load failed, returning []: $e');
        return [];
      }
    }

    // One-time migration: seed from the legacy single `pdfFolderPath`.
    final migrated = await _migrateFromLegacyConfig(prefs);
    if (migrated.isNotEmpty) {
      await _persistList(prefs, migrated);
    }
    return migrated;
  }

  Future<List<LibrarySource>> _migrateFromLegacyConfig(
    SharedPreferences prefs,
  ) async {
    try {
      final raw = prefs.getString(_legacyConfigKey);
      if (raw == null) return [];
      final json = jsonDecode(raw) as Map<String, Object?>;
      final legacyPath = json['pdfFolderPath'] as String?;
      if (legacyPath == null || legacyPath.isEmpty) return [];
      appLog('library_sources', 'migrating legacy pdfFolderPath=$legacyPath');
      return [
        LibrarySource(
          id: _newId(),
          kind: LibrarySourceKind.folder,
          locator: legacyPath,
          displayName: _basename(legacyPath),
          // Never auto-delete migrated data — treat as a reference.
          ownsFiles: false,
          addedAt: DateTime.now(),
        ),
      ];
    } on Object catch (e) {
      appLog('library_sources', 'legacy migration failed: $e');
      return [];
    }
  }

  Future<void> _persist(List<LibrarySource> sources) async {
    final prefs = await SharedPreferences.getInstance();
    await _persistList(prefs, sources);
  }

  Future<void> _persistList(
    SharedPreferences prefs,
    List<LibrarySource> sources,
  ) async {
    final raw = jsonEncode(sources.map((s) => s.toJson()).toList());
    await prefs.setString(_sourcesKey, raw);
  }

  /// Adds a folder source.
  ///
  /// Returns false when a source with the same locator or stable source key
  /// already exists.
  Future<bool> addFolder(
    String locator, {
    bool ownsFiles = false,
    String? displayName,
    String? sourceKey,
  }) => _add(
    kind: LibrarySourceKind.folder,
    locator: locator,
    ownsFiles: ownsFiles,
    displayName: displayName,
    sourceKey: sourceKey,
  );

  /// Adds a single-file source.
  ///
  /// Returns false when a source with the same locator or stable source key
  /// already exists.
  Future<bool> addFile(
    String locator, {
    bool ownsFiles = false,
    String? displayName,
    String? sourceKey,
  }) => _add(
    kind: LibrarySourceKind.file,
    locator: locator,
    ownsFiles: ownsFiles,
    displayName: displayName,
    sourceKey: sourceKey,
  );

  Future<bool> _add({
    required LibrarySourceKind kind,
    required String locator,
    required bool ownsFiles,
    String? displayName,
    String? sourceKey,
  }) => _synchronized(() async {
    final current = state.valueOrNull ?? const <LibrarySource>[];
    final canonical = _canonical(locator);
    final canonicalSourceKey = _canonicalSourceKey(sourceKey);
    final isDuplicate = current.any((s) {
      final existingSourceKey = _canonicalSourceKey(s.sourceKey);
      if (canonicalSourceKey != null && existingSourceKey != null) {
        return existingSourceKey == canonicalSourceKey;
      }
      return _canonical(s.locator) == canonical;
    });
    if (isDuplicate) {
      appLog('library_sources', 'add skipped (duplicate): $locator');
      return false;
    }
    final source = LibrarySource(
      id: _newId(),
      kind: kind,
      locator: locator,
      displayName: _displayNameFor(locator, displayName, sourceKey),
      ownsFiles: ownsFiles,
      addedAt: DateTime.now(),
      sourceKey: sourceKey,
    );
    final updated = [...current, source];
    state = AsyncData(updated);
    await _persist(updated);
    appLog('library_sources', 'added ${kind.name}: $locator');
    return true;
  });

  /// Removes the source with [id]. If it owns its files, the app-managed
  /// directory/file is deleted to reclaim storage; referenced sources only
  /// drop the reference and never touch the user's real files.
  Future<void> remove(String id) => _synchronized(() async {
    final current = state.valueOrNull ?? const <LibrarySource>[];
    final matches = current.where((s) => s.id == id).toList();
    if (matches.isEmpty) return;
    final target = matches.first;

    if (target.ownsFiles) {
      try {
        await _deleteOwnedSource(target);
      } on LibrarySourceRemovalException {
        rethrow;
      } on Object catch (e) {
        appLog('library_sources', 'failed to delete owned files: $e');
        throw LibrarySourceRemovalException(target.locator, e);
      }
    }

    final updated = current.where((s) => s.id != id).toList();
    state = AsyncData(updated);
    await _persist(updated);
    appLog('library_sources', 'removed: ${target.locator}');
  });

  static Future<void> _deleteOwnedFromDisk(LibrarySource source) async {
    try {
      final entity = source.kind == LibrarySourceKind.folder
          ? Directory(source.locator)
          : File(source.locator);
      if (await entity.exists()) {
        await entity.delete(recursive: true);
        appLog('library_sources', 'deleted owned files: ${source.locator}');
      }
    } on Object catch (e) {
      appLog('library_sources', 'failed to delete owned files: $e');
      throw LibrarySourceRemovalException(source.locator, e);
    }
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  static String _canonical(String path) {
    var c = path.replaceAll('\\', '/');
    if (c.length > 1 && c.endsWith('/')) c = c.substring(0, c.length - 1);
    if (!kIsWeb && Platform.isWindows) c = c.toLowerCase();
    return c;
  }

  static String? _canonicalSourceKey(String? key) {
    if (key == null || key.isEmpty) return null;
    var c = key.replaceAll('\\', '/');
    if (c.length > 1 && c.endsWith('/')) c = c.substring(0, c.length - 1);
    if (!kIsWeb && Platform.isWindows) c = c.toLowerCase();
    return c;
  }

  static String _displayNameFor(
    String locator,
    String? displayName,
    String? sourceKey,
  ) {
    final trimmed = displayName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    final treeName = _friendlyNameFromSourceKey(sourceKey);
    if (treeName != null) return treeName;
    final base = _basename(locator).trim();
    return base.isEmpty ? 'Imported folder' : base;
  }

  static String? _friendlyNameFromSourceKey(String? sourceKey) {
    if (sourceKey == null || sourceKey.isEmpty) return null;
    final raw = sourceKey.startsWith('android-tree:')
        ? sourceKey.substring('android-tree:'.length)
        : sourceKey;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    final decoded = Uri.decodeComponent(uri.path);
    final last = decoded.split(':').last.split('/').where((s) => s.isNotEmpty);
    if (last.isEmpty) return null;
    return last.last;
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final idx = trimmed.lastIndexOf('/');
    return idx >= 0 ? trimmed.substring(idx + 1) : trimmed;
  }
}

/// Provider for the user's library sources.
final librarySourcesProvider =
    AsyncNotifierProvider<LibrarySourcesNotifier, List<LibrarySource>>(
      LibrarySourcesNotifier.new,
    );
