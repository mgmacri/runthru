import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppConfig', () {
    test('defaults', () {
      const config = AppConfig();
      expect(config.defaultWpm, 300);
      expect(config.pdfFolderPath, isNull);
      expect(config.bookmarks, isEmpty);
      expect(
        config.googleDriveAccessMode,
        GoogleDriveAccessMode.selectedFilesOnly,
      );
      expect(config.focusModeEnabled, isFalse);
    });

    test('roundtrip JSON serialization', () {
      final config = AppConfig(
        defaultWpm: 500,
        pdfFolderPath: '/docs',
        bookmarks: {
          '/test.pdf': BookmarkData(wordIndex: 42, timestamp: DateTime(2026)),
        },
        googleDriveAccessMode: GoogleDriveAccessMode.fullDriveBrowser,
        focusModeEnabled: true,
      );

      final json = config.toJson();
      final restored = AppConfig.fromJson(json);

      expect(restored.defaultWpm, 500);
      expect(restored.pdfFolderPath, '/docs');
      expect(restored.bookmarks['/test.pdf']?.wordIndex, 42);
      expect(
        restored.googleDriveAccessMode,
        GoogleDriveAccessMode.fullDriveBrowser,
      );
      expect(restored.focusModeEnabled, isTrue);
    });

    test('fromJson handles missing fields gracefully', () {
      final config = AppConfig.fromJson({});
      expect(config.defaultWpm, 300);
      expect(config.pdfFolderPath, isNull);
      expect(
        config.googleDriveAccessMode,
        GoogleDriveAccessMode.selectedFilesOnly,
      );
      expect(config.focusModeEnabled, isFalse);
    });

    test('anchor colour defaults to the high-contrast red', () {
      expect(const AppConfig().anchorColorIndex, kDefaultAnchorColorIndex);
      expect(AppConfig.fromJson({}).anchorColorIndex, kDefaultAnchorColorIndex);
    });

    test(
      'legacy anchorColorIndex is ignored; the chosen colour roundtrips',
      () {
        // Pre-2.0 configs saved the Hot Coral default (0) under the old key,
        // which the main reader never honoured.
        final legacy = AppConfig.fromJson({'anchorColorIndex': 0});
        expect(legacy.anchorColorIndex, kDefaultAnchorColorIndex);

        final chosen = AppConfig.fromJson(
          const AppConfig(anchorColorIndex: 8).toJson(),
        );
        expect(chosen.anchorColorIndex, 8);
      },
    );

    test('corrupt Google Drive access mode defaults to selected files', () {
      final config = AppConfig.fromJson({
        'googleDriveAccessMode': 'workspaceReadOnly',
      });

      expect(
        config.googleDriveAccessMode,
        GoogleDriveAccessMode.selectedFilesOnly,
      );
    });

    test('v3 fields default safely when JSON keys missing', () {
      final config = AppConfig.fromJson({});
      expect(config.parallaxIntensity, ParallaxIntensity.none);
      expect(config.readingGoalPreset, isNull);
      expect(config.orpCondition, OrpCondition.orpBoldColor);
      expect(config.shownHints, isEmpty);
    });

    test('parallaxIntensity serializes and deserializes for an owner', () {
      for (final intensity in ParallaxIntensity.values) {
        final config = AppConfig(
          hasPremium: true,
          parallaxIntensity: intensity,
        );
        final json = config.toJson();
        final restored = AppConfig.fromJson(json);
        expect(restored.parallaxIntensity, intensity);
      }
    });

    test('a 3D room saved without the unlock loads flat', () {
      // Saved by a build whose placeholder purchase handed out the room
      // (the legacy `hasPremium` key), then upgraded: the reader went on
      // drawing the room, and Settings showed no control to turn it off.
      for (final room in ['off', 'subtle', 'full']) {
        expect(
          AppConfig.fromJson({
            'hasPremium': true,
            'parallaxIntensity': room,
          }).parallaxIntensity,
          ParallaxIntensity.none,
          reason: room,
        );
        expect(
          AppConfig.fromJson({'parallaxIntensity': room}).parallaxIntensity,
          ParallaxIntensity.none,
          reason: room,
        );
      }
      expect(
        AppConfig.fromJson({
          'premiumUnlocked': true,
          'parallaxIntensity': 'full',
        }).parallaxIntensity,
        ParallaxIntensity.full,
      );
    });

    test('orpCondition serializes and deserializes', () {
      for (final condition in OrpCondition.values) {
        final config = AppConfig(orpCondition: condition);
        final json = config.toJson();
        final restored = AppConfig.fromJson(json);
        expect(restored.orpCondition, condition);
      }
    });

    test('readingGoalPreset null by default', () {
      const config = AppConfig();
      expect(config.readingGoalPreset, isNull);

      // Round-trip with a non-null preset
      final withPreset = config.copyWith(
        readingGoalPreset: ReadingGoalPreset.deepRead,
      );
      final json = withPreset.toJson();
      final restored = AppConfig.fromJson(json);
      expect(restored.readingGoalPreset, ReadingGoalPreset.deepRead);

      // Round-trip with null preset
      final cleared = withPreset.copyWith(clearReadingGoalPreset: true);
      final json2 = cleared.toJson();
      final restored2 = AppConfig.fromJson(json2);
      expect(restored2.readingGoalPreset, isNull);
    });

    test('shownHints defaults to empty set', () {
      const config = AppConfig();
      expect(config.shownHints, isEmpty);

      final updated = config.copyWith(
        shownHints: {'hint_tap', 'hint_swipe_up'},
      );
      final json = updated.toJson();
      final restored = AppConfig.fromJson(json);
      expect(restored.shownHints, {'hint_tap', 'hint_swipe_up'});
    });

    test('shownHints missing key in JSON returns empty set', () {
      final config = AppConfig.fromJson({});
      expect(config.shownHints, isEmpty);
    });
  });

  group('ConfigNotifier onboarding persistence', () {
    test('fresh persisted config resolves onboarding as unseen', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final config = await container.read(configProvider.future);

      expect(config.hasSeenReadingGoalOnboarding, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('runthru_config'), isNull);
    });

    test('setHasSeenReadingGoalOnboarding persists completion flag', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(configProvider.future);
      await container
          .read(configProvider.notifier)
          .setHasSeenReadingGoalOnboarding(true);

      final config = container.read(configProvider).requireValue;
      expect(config.hasSeenReadingGoalOnboarding, isTrue);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('runthru_config');
      expect(raw, contains('"hasSeenReadingGoalOnboarding":true'));
    });

    test('setFocusModeEnabled persists synchronized focus mode flag', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(configProvider.future);
      await container.read(configProvider.notifier).setFocusModeEnabled(true);

      final config = container.read(configProvider).requireValue;
      expect(config.focusModeEnabled, isTrue);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('runthru_config');
      expect(raw, contains('"focusModeEnabled":true'));
    });

    test(
      'skip-equivalent comfortable preset and completion flag persist',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container.read(configProvider.future);
        final comfortable = readingGoalConfigs.firstWhere(
          (goal) => goal.preset == ReadingGoalPreset.comfortable,
        );
        await container
            .read(configProvider.notifier)
            .applyReadingGoalPreset(comfortable);
        await container
            .read(configProvider.notifier)
            .setHasSeenReadingGoalOnboarding(true);

        final config = container.read(configProvider).requireValue;
        expect(config.hasSeenReadingGoalOnboarding, isTrue);
        expect(config.readingGoalPreset, ReadingGoalPreset.comfortable);

        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('runthru_config');
        expect(raw, contains('"readingGoalPreset":"comfortable"'));
        expect(raw, contains('"hasSeenReadingGoalOnboarding":true'));
      },
    );
  });

  // R-11: the 3D room is part of the one-time RunThru Unlock purchase.
  group('ConfigNotifier RunThru Unlock (R-11)', () {
    Future<ProviderContainer> containerWith(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(configProvider.future);
      return container;
    }

    test('free users stay flat when choosing a 3D intensity', () async {
      final container = await containerWith({});
      await container
          .read(configProvider.notifier)
          .setParallaxIntensity(ParallaxIntensity.subtle);
      expect(
        container.read(configProvider).requireValue.parallaxIntensity,
        ParallaxIntensity.none,
      );
    });

    test('owners get the chosen intensity and preset parallax', () async {
      final container = await containerWith({});
      final notifier = container.read(configProvider.notifier);
      await notifier.setHasPremium(true);

      await notifier.setParallaxIntensity(ParallaxIntensity.subtle);
      expect(
        container.read(configProvider).requireValue.parallaxIntensity,
        ParallaxIntensity.subtle,
      );

      final goal = readingGoalConfigs.first;
      await notifier.applyReadingGoalPreset(goal);
      final config = container.read(configProvider).requireValue;
      expect(config.parallaxIntensity, goal.parallaxIntensity);
      expect(config.defaultWpm, goal.wpm);
      expect(config.pacingConfig, goal.pacing);
      expect(config.readingGoalInEffect, goal.preset);
    });

    // B-54: the goal a free reader chooses is saved with its speed and word
    // pacing, stays flat, and still shows as chosen after a restart.
    test('free users keep the goal they chose, flat', () async {
      final container = await containerWith({});
      final goal = readingGoalConfigs.firstWhere(
        (g) => g.preset == ReadingGoalPreset.quickScan,
      );
      await container
          .read(configProvider.notifier)
          .applyReadingGoalPreset(goal);

      final prefs = await SharedPreferences.getInstance();
      final restored = AppConfig.fromJson(
        jsonDecode(prefs.getString('runthru_config')!) as Map<String, Object?>,
      );
      expect(restored.defaultWpm, goal.wpm);
      expect(restored.pacingConfig, goal.pacing);
      expect(restored.parallaxIntensity, ParallaxIntensity.none);
      expect(restored.readingGoalInEffect, ReadingGoalPreset.quickScan);
      expect(restored.readingGoalCustomized, isFalse);
    });

    test('the entitlement persists under premiumUnlocked', () async {
      final container = await containerWith({});
      await container.read(configProvider.notifier).setHasPremium(true);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('runthru_config')!;
      expect(raw, contains('"premiumUnlocked":true'));
      expect(raw, isNot(contains('"hasPremium"')));
    });

    test('legacy hasPremium from the old placeholder grants nothing', () {
      final legacy = AppConfig.fromJson({'hasPremium': true});
      expect(legacy.hasPremium, isFalse);
      expect(AppConfig.fromJson({'premiumUnlocked': true}).hasPremium, isTrue);
    });
  });

  group('BookmarkData', () {
    test('roundtrip JSON', () {
      final bookmark = BookmarkData(
        wordIndex: 100,
        timestamp: DateTime(2026, 3, 14),
      );
      final json = bookmark.toJson();
      final restored = BookmarkData.fromJson(json);
      expect(restored.wordIndex, 100);
      expect(restored.timestamp, isNotNull);
    });
  });
}
