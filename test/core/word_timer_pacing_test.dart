import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/word_timer.dart';
import 'package:runthru/features/reading/pacing/pacing_config.dart';
import 'package:runthru/features/reading/pacing/word_duration.dart';
import 'package:runthru/store/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('WordTimer adaptive pacing integration', () {
    late WordTimerNotifier notifier;

    setUp(() {
      notifier = WordTimerNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('default config is a no-op for plain words', () {
      // Plain short words with no punctuation, complexity, or length bonuses
      // should schedule at exactly baseIntervalMs (200ms at 300 WPM).
      final words = ['the', 'quick', 'brown', 'fox'];
      notifier.loadDocument(words.length);
      notifier.attachWordSource((i) => i < words.length ? words[i] : null);

      const base = 200; // 60000 / 300 = 200
      for (var i = 0; i < words.length; i++) {
        final next = i + 1 < words.length ? words[i + 1] : null;
        final duration = durationForWord(
          words[i],
          nextWord: next,
          baseIntervalMs: base,
          config: defaultPacingConfig,
        );
        expect(duration, base, reason: '"${words[i]}" should have no bonus');
      }
    });

    test('paragraph total is deterministic', () {
      // A known sentence with punctuation and length bonuses.
      final words = 'The quick brown fox jumps over the lazy dog.'.split(' ');
      const base = 200; // 300 WPM

      var total = 0;
      for (var i = 0; i < words.length; i++) {
        final next = i + 1 < words.length ? words[i + 1] : null;
        total += durationForWord(
          words[i],
          nextWord: next,
          baseIntervalMs: base,
          config: defaultPacingConfig,
        );
      }

      // "dog." ends the sentence (no next word → null, which is not lowercase,
      // so the sentence pause fires). Compute expected: 8 × 200 + pause for
      // "dog." (period with no next word → sentence pause 135% of 200 delay).
      // dog. readable=3, ≤4 + next is null (not lowercase) → sentence fires.
      // Expected: 8 × 200 + (200 + scaledDelay(135, 100, 200))
      //         = 1600 + (200 + 270) = 2070
      expect(total, 2070);
    });

    test('scale isolation: longWordScale affects long words only', () {
      // "information" has length bonus (readable=11, tier1+tier2 + syllable).
      // "done." before "The" has punctuation bonus only.
      const base = 200;

      final infoDuration = durationForWord(
        'information',
        nextWord: 'is',
        baseIntervalMs: base,
        config: const PacingConfig(longWordScalePercent: 200),
      );
      final infoDurationDefault = durationForWord(
        'information',
        nextWord: 'is',
        baseIntervalMs: base,
        config: defaultPacingConfig,
      );

      final doneDuration = durationForWord(
        'done.',
        nextWord: 'The',
        baseIntervalMs: base,
        config: const PacingConfig(longWordScalePercent: 200),
      );
      final doneDurationDefault = durationForWord(
        'done.',
        nextWord: 'The',
        baseIntervalMs: base,
        config: defaultPacingConfig,
      );

      // Long word scale change should increase "information" duration.
      expect(infoDuration, greaterThan(infoDurationDefault));
      // Punctuation-only word "done." should be unaffected by long word scale.
      expect(doneDuration, doneDurationDefault);
    });

    test('persistence round-trip via AppConfig JSON', () {
      SharedPreferences.setMockInitialValues({});

      const config = PacingConfig(
        longWordDelayMs: 300,
        complexWordDelayMs: 150,
        punctuationDelayMs: 400,
        longWordScalePercent: 175,
        complexWordScalePercent: 50,
        punctuationScalePercent: 125,
      );

      final appConfig = const AppConfig().copyWith(pacingConfig: config);
      final json = appConfig.toJson();
      final jsonString = jsonEncode(json);
      final decoded = jsonDecode(jsonString) as Map<String, Object?>;
      final restored = AppConfig.fromJson(decoded);

      expect(restored.pacingConfig, config);
      expect(restored.pacingConfig.longWordDelayMs, 300);
      expect(restored.pacingConfig.complexWordDelayMs, 150);
      expect(restored.pacingConfig.punctuationDelayMs, 400);
      expect(restored.pacingConfig.longWordScalePercent, 175);
      expect(restored.pacingConfig.complexWordScalePercent, 50);
      expect(restored.pacingConfig.punctuationScalePercent, 125);
    });

    test('copyWith(pacingConfig) does not reset currentIndex or isPlaying', () {
      notifier.loadDocument(100, startIndex: 42);
      notifier.play();

      expect(notifier.state.currentIndex, 42);
      expect(notifier.state.isPlaying, true);

      // Update pacing config via copyWith on the state.
      const newConfig = PacingConfig(longWordScalePercent: 150);
      final updated = notifier.state.copyWith(pacingConfig: newConfig);

      expect(updated.currentIndex, 42);
      expect(updated.isPlaying, true);
      expect(updated.pacingConfig.longWordScalePercent, 150);
    });
  });
}
