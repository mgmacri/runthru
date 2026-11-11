import 'dart:convert';

import 'package:fake_async/fake_async.dart';
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

    // B-55: nothing ever handed a pacing config to the timer, so it paced
    // with the defaults whatever the Word Pacing sliders said.
    group('setPacingConfig', () {
      const slower = PacingConfig(punctuationScalePercent: 200);
      const base = 200; // 300 WPM
      final words = List.filled(400, 'Stop.');

      int expectedMs(PacingConfig config) => durationForWord(
        'Stop.',
        nextWord: 'Stop.',
        baseIntervalMs: base,
        config: config,
      );

      /// Plays past the warm-up ramp, then pauses and plays again so the
      /// next word starts on a clean boundary.
      WordTimerNotifier startClean(FakeAsync async, {PacingConfig? pacing}) {
        final timer = WordTimerNotifier();
        timer.loadDocument(words.length);
        timer.attachWordSource((i) => i < words.length ? words[i] : null);
        timer.setWpm(300);
        if (pacing != null) timer.setPacingConfig(pacing);
        timer.play();
        async.elapse(const Duration(seconds: 15));
        timer.pause();
        timer.play();
        return timer;
      }

      /// Milliseconds until the word on screen is replaced.
      int shownMs(FakeAsync async, WordTimerNotifier timer) {
        final start = timer.state.currentIndex;
        var ms = 0;
        while (timer.state.currentIndex == start && ms < 5000) {
          async.elapse(const Duration(milliseconds: 1));
          ms++;
        }
        return ms;
      }

      test('a word stays up for the time its pacing gives it', () {
        expect(
          expectedMs(slower),
          greaterThan(expectedMs(defaultPacingConfig)),
        );
        fakeAsync((async) {
          final plain = startClean(async);
          expect(shownMs(async, plain), expectedMs(defaultPacingConfig));
          plain.dispose();

          final paced = startClean(async, pacing: slower);
          expect(paced.state.pacingConfig, slower);
          expect(shownMs(async, paced), expectedMs(slower));
          paced.dispose();
        });
      });

      test('a change while reading applies from the next word', () {
        fakeAsync((async) {
          final timer = startClean(async);
          final start = timer.state.currentIndex;

          timer.setPacingConfig(slower);
          // The word on screen keeps the time it was given.
          expect(shownMs(async, timer), expectedMs(defaultPacingConfig));
          expect(shownMs(async, timer), expectedMs(slower));
          expect(timer.state.currentIndex, start + 2);
          expect(timer.state.isPlaying, isTrue);
          timer.dispose();
        });
      });
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
