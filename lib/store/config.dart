import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/features/reading/pacing/pacing_config.dart';
import 'package:runthru/store/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _configKey = 'runthru_config';

/// Riverpod AsyncNotifier managing persistent app configuration.
class ConfigNotifier extends AsyncNotifier<AppConfig> {
  Future<void> setLetterSpacing(double spacing) => _synchronized(() async {
    final config = state.valueOrNull ?? const AppConfig();
    final updated = config.copyWith(letterSpacing: spacing.clamp(0.0, 5.0));
    state = AsyncData<AppConfig>(updated);
    await _persist(updated);
  });

  Future<void> setWordSpacing(double spacing) => _synchronized(() async {
    final config = state.valueOrNull ?? const AppConfig();
    final updated = config.copyWith(wordSpacing: spacing.clamp(0.0, 20.0));
    state = AsyncData<AppConfig>(updated);
    await _persist(updated);
  });

  Future<void> setReadingRulerEnabled(bool enabled) => _synchronized(() async {
    final config = state.valueOrNull ?? const AppConfig();
    final updated = config.copyWith(readingRulerEnabled: enabled);
    state = AsyncData<AppConfig>(updated);
    await _persist(updated);
  });

  Future<void> setFocusModeEnabled(bool enabled) => _synchronized(() async {
    final config = state.valueOrNull ?? const AppConfig();
    final updated = config.copyWith(focusModeEnabled: enabled);
    state = AsyncData<AppConfig>(updated);
    await _persist(updated);
  });

  /// Turns chapter title cards and chapter-complete moments on or off.
  Future<void> setChapterMoments(bool enabled) => _synchronized(() async {
    final config = state.valueOrNull ?? const AppConfig();
    final updated = config.copyWith(chapterMoments: enabled);
    state = AsyncData<AppConfig>(updated);
    await _persist(updated);
  });

  /// Sets the Book-mode text size, clamped to the supported range.
  Future<void> setBookFontSize(double size) => _synchronized(() async {
    final config = state.valueOrNull ?? const AppConfig();
    final updated = config.copyWith(
      bookFontSize: size.clamp(kMinBookFontSize, kMaxBookFontSize).toDouble(),
    );
    state = AsyncData<AppConfig>(updated);
    await _persist(updated);
  });

  /// Remembers the reading mode so the next book opens in it.
  Future<void> setLastReadingMode(String mode) => _synchronized(() async {
    final config = state.valueOrNull ?? const AppConfig();
    if (config.lastReadingMode == mode) return;
    final updated = config.copyWith(lastReadingMode: mode);
    state = AsyncData<AppConfig>(updated);
    await _persist(updated);
  });

  /// Sets the Google Drive access mode without requesting new OAuth scopes.
  Future<void> setGoogleDriveAccessMode(GoogleDriveAccessMode mode) =>
      _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        final updated = config.copyWith(googleDriveAccessMode: mode);
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });

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

  // NOTE: bookmarks moved to BookmarkStore (lib/store/bookmark_store.dart).
  // AppConfig.bookmarks is retained read-only as the migration source and
  // rollback path — never add a bookmark writer here again (BK-5: it
  // rewrote the whole config blob every 5 seconds during reading).

  Future<void> setAnchorColorIndex(int index) => _synchronized(() async {
    final config = state.valueOrNull ?? const AppConfig();
    final updated = config.copyWith(anchorColorIndex: index);
    state = AsyncData<AppConfig>(updated);
    await _persist(updated);
  });

  Future<void> setReadingFontFamily(String family) => _synchronized(() async {
    final config = state.valueOrNull ?? const AppConfig();
    final updated = config.copyWith(readingFontFamily: family);
    state = AsyncData<AppConfig>(updated);
    await _persist(updated);
  });

  Future<void> setFontScale(double scale) => _synchronized(() async {
    final config = state.valueOrNull ?? const AppConfig();
    final updated = config.copyWith(fontScale: scale.clamp(0.5, 2.0));
    state = AsyncData<AppConfig>(updated);
    await _persist(updated);
  });

  /// Records the store-delivered RunThru Unlock entitlement. Only
  /// `PurchaseController` calls this, after the store reports the purchase.
  Future<void> setHasPremium(bool value) => _synchronized(() async {
    final config = state.valueOrNull ?? const AppConfig();
    final updated = config.copyWith(hasPremium: value);
    state = AsyncData<AppConfig>(updated);
    await _persist(updated);
  });

  Future<void> setParallaxIntensity(ParallaxIntensity intensity) =>
      _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        // The 3D room is part of RunThru Unlock; free users stay flat.
        final updated = config.copyWith(
          parallaxIntensity: config.hasPremium
              ? intensity
              : ParallaxIntensity.none,
        );
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });

  Future<void> setReadingGoalPreset(ReadingGoalPreset? preset) =>
      _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        final updated = preset == null
            ? config.copyWith(clearReadingGoalPreset: true)
            : config.copyWith(readingGoalPreset: preset);
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });

  Future<void> setOrpCondition(OrpCondition condition) =>
      _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        final updated = config.copyWith(orpCondition: condition);
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });

  /// Mark a hint as shown so it never appears again (Rule 27).
  // P27 — hints show once per installation
  Future<void> markHintShown(String id) => _synchronized(() async {
    final config = state.valueOrNull ?? const AppConfig();
    final updated = config.copyWith(shownHints: {...config.shownHints, id});
    state = AsyncData<AppConfig>(updated);
    await _persist(updated);
  });

  /// Check whether a hint has already been shown.
  bool hasHintBeenShown(String id) {
    final config = state.valueOrNull ?? const AppConfig();
    return config.shownHints.contains(id);
  }

  Future<void> setHasSeenReadingGoalOnboarding(bool seen) =>
      _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        final updated = config.copyWith(hasSeenReadingGoalOnboarding: seen);
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });

  /// Updates the per-word adaptive pacing configuration.
  Future<void> updatePacingConfig(PacingConfig pacingConfig) =>
      _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        final updated = config.copyWith(pacingConfig: pacingConfig);
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });

  /// Applies a reading goal preset: its speed, word pacing and (for RunThru
  /// Unlock owners) 3D room, and remembers the choice, in one synchronized
  /// write. See [ReadingGoalSettings.withReadingGoal].
  // P8 Grade B — presets are reading intentions, not speed tiers
  Future<void> applyReadingGoalPreset(ReadingGoalConfig goal) =>
      _synchronized(() async {
        final config = state.valueOrNull ?? const AppConfig();
        final updated = config.withReadingGoal(goal);
        state = AsyncData<AppConfig>(updated);
        await _persist(updated);
      });
}

final configProvider = AsyncNotifierProvider<ConfigNotifier, AppConfig>(
  ConfigNotifier.new,
);
