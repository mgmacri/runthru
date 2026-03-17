import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speedy_boy/store/models.dart';

const _configKey = 'speedy_boy_config';

/// Riverpod AsyncNotifier managing persistent app configuration.
class ConfigNotifier extends AsyncNotifier<AppConfig> {
  /// Serializes concurrent read-modify-write cycles to prevent data loss.
  Completer<void>? _lock;

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

  @override
  Future<AppConfig> build() async {
    return _load();
  }

  Future<AppConfig> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw == null) return const AppConfig();

    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      return AppConfig.fromJson(json);
    } on Object {
      // Corrupt data — return defaults
      return const AppConfig();
    }
  }

  Future<void> _persist(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(config.toJson());
    await prefs.setString(_configKey, json);
  }

  Future<void> setDefaultWpm(int wpm) => _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        final updated = config.copyWith(defaultWpm: wpm.clamp(30, 1000));
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });

  Future<void> setPdfFolderPath(String? path) => _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        final updated = path == null
            ? config.copyWith(clearPdfFolderPath: true)
            : config.copyWith(pdfFolderPath: path);
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });

  Future<void> updateBookmark(
    String filePath,
    BookmarkData data,
  ) =>
      _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        final bookmarks = Map<String, BookmarkData>.from(
          config.bookmarks,
        );
        bookmarks[filePath] = data;
        final updated = config.copyWith(bookmarks: bookmarks);
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });

  Future<void> setAnchorColorIndex(int index) => _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        final updated = config.copyWith(anchorColorIndex: index);
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });

  Future<void> setFontFamily(String fontFamily) => _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        final updated = config.copyWith(fontFamily: fontFamily);
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });

  Future<void> setFontScale(double scale) => _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        final updated = config.copyWith(fontScale: scale.clamp(0.5, 2.0));
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });

  Future<void> setHasPremium(bool value) => _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        final updated = config.copyWith(hasPremium: value);
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });
}

final configProvider = AsyncNotifierProvider<ConfigNotifier, AppConfig>(
  ConfigNotifier.new,
);
