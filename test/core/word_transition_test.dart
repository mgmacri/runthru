import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/word_transition.dart';
import 'package:runthru/design/design.dart';

void main() {
  group('selectWordTransition', () {
    test('A-001 at 350 WPM for any word length', () {
      for (final charCount in [1, 3, 7, 15]) {
        final result = selectWordTransition(
          wpm: 350,
          charCount: charCount,
          displayMs: (60000 / 350).round(),
        );
        expect(result.transition, WordTransition.a001Breathe);
        expect(
          result.baseDurationMs,
          RunThruAnimations.wordAdvanceDuration.inMilliseconds,
        );
      }
    });

    test('A-001 at 500 WPM for any word length', () {
      for (final charCount in [1, 3, 7, 15]) {
        final result = selectWordTransition(
          wpm: 500,
          charCount: charCount,
          displayMs: (60000 / 500).round(),
        );
        expect(result.transition, WordTransition.a001Breathe);
        expect(
          result.baseDurationMs,
          RunThruAnimations.wordAdvanceDuration.inMilliseconds,
        );
      }
    });

    test('A-013 capped at 250 WPM for "the" (3 chars)', () {
      final displayMs = (60000 / 250).round(); // 240ms
      final result = selectWordTransition(
        wpm: 250,
        charCount: 3,
        displayMs: displayMs,
      );
      expect(result.transition, WordTransition.a013BounceIn);

      // Budget: floor(240 * 0.6) - 6 * 2 = 144 - 12 = 132
      final expectedBudget =
          (displayMs * RunThruTiming.a013MaxDisplayFraction).floor() -
          RunThruAnimations.glyphStaggerMs * (3 - 1);
      expect(result.baseDurationMs, expectedBudget);
      expect(
        result.baseDurationMs,
        greaterThanOrEqualTo(RunThruTiming.a013MinBaseDuration),
      );
    });

    test('A-013 capped at 250 WPM for "reading" (7 chars)', () {
      final displayMs = (60000 / 250).round(); // 240ms
      final result = selectWordTransition(
        wpm: 250,
        charCount: 7,
        displayMs: displayMs,
      );
      expect(result.transition, WordTransition.a013BounceIn);

      // Budget: floor(240 * 0.6) - 6 * 6 = 144 - 36 = 108
      final expectedBudget =
          (displayMs * RunThruTiming.a013MaxDisplayFraction).floor() -
          RunThruAnimations.glyphStaggerMs * (7 - 1);
      expect(result.baseDurationMs, expectedBudget);
      expect(
        result.baseDurationMs,
        greaterThanOrEqualTo(RunThruTiming.a013MinBaseDuration),
      );
    });

    test('A-013 base never below 40ms', () {
      // Use a very long word with a short display time to force the floor.
      final result = selectWordTransition(
        wpm: 300,
        charCount: 30,
        displayMs: 200, // 200ms
      );
      expect(result.transition, WordTransition.a013BounceIn);
      expect(result.baseDurationMs, RunThruTiming.a013MinBaseDuration);
    });

    test('A-013 uncapped when animation fits within display budget', () {
      // Slow WPM, short word — budget is generous.
      final displayMs = (60000 / 100).round(); // 600ms
      final result = selectWordTransition(
        wpm: 100,
        charCount: 3,
        displayMs: displayMs,
      );
      expect(result.transition, WordTransition.a013BounceIn);

      // Budget: floor(600 * 0.6) - 6 * 2 = 360 - 12 = 348
      final expectedBudget =
          (displayMs * RunThruTiming.a013MaxDisplayFraction).floor() -
          RunThruAnimations.glyphStaggerMs * (3 - 1);
      expect(result.baseDurationMs, expectedBudget);
    });

    test('301 WPM triggers A-001 fallback', () {
      final result = selectWordTransition(
        wpm: 301,
        charCount: 5,
        displayMs: (60000 / 301).round(),
      );
      expect(result.transition, WordTransition.a001Breathe);
    });

    test('300 WPM stays on A-013', () {
      final result = selectWordTransition(
        wpm: 300,
        charCount: 5,
        displayMs: (60000 / 300).round(),
      );
      expect(result.transition, WordTransition.a013BounceIn);
    });
  });
}
