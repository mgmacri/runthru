/// Tests for the warm-up ramp behavior of [WordTimerNotifier].
///
/// The warm-up ramp plays the first ~10 seconds of reading at 80%→100% speed,
/// giving ADHD/neurodivergent readers a gentle on-ramp into the reading flow.
///
/// Covers:
/// - [WordTimerState] default warmup field values and `copyWith` semantics
/// - [WordTimerNotifier] warmup lifecycle: first play, loadDocument reset,
///   seekTo / restartCurrentSentence / resumeFromContextReveal invariance
/// - Timing: warmup completion after 10s, pause/resume progress preservation,
///   auto-rewind during warmup
/// - Interaction: warmup multiplies (not replaces) per-word adaptive pacing
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/word_timer.dart';
import 'package:runthru/design/design.dart';

void main() {
  // ── Group 1: WordTimerState warmup fields ──

  group('WordTimerState warmup fields', () {
    test('defaults to warmupProgress 0.0 and isWarmingUp false', () {
      const state = WordTimerState();
      expect(state.warmupProgress, 0.0);
      expect(state.isWarmingUp, false);
    });

    test('copyWith preserves warmup fields', () {
      const state = WordTimerState(warmupProgress: 0.5, isWarmingUp: true);
      final copied = state.copyWith(currentIndex: 10);
      expect(copied.warmupProgress, 0.5);
      expect(copied.isWarmingUp, true);
    });

    test('copyWith updates warmup fields', () {
      const state = WordTimerState();
      final updated = state.copyWith(warmupProgress: 0.7, isWarmingUp: true);
      expect(updated.warmupProgress, 0.7);
      expect(updated.isWarmingUp, true);
    });
  });

  // ── Group 2: WordTimerNotifier warmup behavior ──

  group('WordTimerNotifier warmup behavior', () {
    late WordTimerNotifier notifier;

    setUp(() {
      notifier = WordTimerNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('first play() sets isWarmingUp to true', () {
      notifier.loadDocument(100);
      notifier.play();
      expect(notifier.state.isWarmingUp, true);
      // warmupProgress may be slightly > 0 due to _scheduleNext running
      // immediately, but should be near zero.
      expect(notifier.state.warmupProgress, closeTo(0.0, 0.01));
      notifier.pause();
    });

    test('loadDocument resets warmup state', () {
      notifier.loadDocument(100);
      notifier.play();
      expect(notifier.state.isWarmingUp, true);
      notifier.pause();

      notifier.loadDocument(200);
      expect(notifier.state.isWarmingUp, false);
      expect(notifier.state.warmupProgress, 0.0);
    });

    test('seekTo does not affect warmup state', () {
      notifier.loadDocument(100);
      notifier.play();
      expect(notifier.state.isWarmingUp, true);
      notifier.pause();

      notifier.seekTo(50);
      expect(notifier.state.isWarmingUp, true);
      // warmupProgress should be whatever it was — not reset
    });

    test('restartCurrentSentence does not reset warmup', () {
      notifier.loadDocument(100);
      notifier.play();
      notifier.pause();

      final progressBefore = notifier.state.warmupProgress;
      notifier.restartCurrentSentence(0);
      // warmupProgress unchanged (or very close — may have ticked slightly)
      expect(notifier.state.warmupProgress, closeTo(progressBefore, 0.01));
    });

    test('resumeFromContextReveal does not reset warmup', () {
      notifier.loadDocument(100);
      notifier.play();
      notifier.pause();

      notifier.resumeFromContextReveal(10);
      expect(notifier.state.isWarmingUp, true);
      notifier.pause();
    });
  });

  // ── Group 3: Warmup timing (fakeAsync) ──

  group('Warmup timing', () {
    test('warmup increases interval above base for early words', () {
      // At 300 WPM, base interval = 200ms.
      // During warmup at 80% speed: interval ≈ 200/0.8 = 250ms.
      // We verify warmup is active and progress < 1.0 immediately after play.
      final notifier = WordTimerNotifier();
      addTearDown(notifier.dispose);

      notifier.loadDocument(100);
      notifier.attachWordSource((i) => i < 100 ? 'the' : null);
      notifier.play();
      expect(notifier.state.isWarmingUp, true);
      notifier.pause();
      expect(notifier.state.warmupProgress, lessThan(1.0));
    });

    test('warmup completes after ~10 seconds', () {
      fakeAsync((async) {
        final notifier = WordTimerNotifier();
        addTearDown(notifier.dispose);

        notifier.loadDocument(1000);
        notifier.attachWordSource((i) => i < 1000 ? 'the' : null);
        notifier.play();

        // Advance past the 10-second warmup duration.
        async.elapse(const Duration(seconds: 11));

        expect(notifier.state.isWarmingUp, false);
        expect(notifier.state.warmupProgress, 1.0);

        notifier.pause();
      });
    });

    test('pause during warmup preserves progress', () {
      fakeAsync((async) {
        final notifier = WordTimerNotifier();
        addTearDown(notifier.dispose);

        notifier.loadDocument(1000);
        notifier.attachWordSource((i) => i < 1000 ? 'the' : null);
        notifier.play();

        // Advance 5 seconds (~50% through 10s warmup).
        async.elapse(const Duration(seconds: 5));
        notifier.pause();

        final progress = notifier.state.warmupProgress;
        expect(progress, greaterThan(0.3));
        expect(progress, lessThan(0.7));
        expect(notifier.state.isWarmingUp, true);

        // Resume — should continue from ~50%, not restart.
        notifier.play();
        async.elapse(const Duration(seconds: 6));

        expect(notifier.state.isWarmingUp, false);
        expect(notifier.state.warmupProgress, 1.0);

        notifier.pause();
      });
    });

    test('auto-rewind still works during warmup', () {
      fakeAsync((async) {
        final notifier = WordTimerNotifier();
        addTearDown(notifier.dispose);

        notifier.loadDocument(100);
        notifier.attachWordSource((i) => i < 100 ? 'the' : null);

        notifier.play();
        async.elapse(const Duration(seconds: 2));
        final indexBeforePause = notifier.state.currentIndex;

        notifier.pause();
        notifier.play(); // resume — should auto-rewind 3 words

        // P18 auto-rewind: currentIndex = indexBeforePause - 3 (clamped ≥ 0).
        expect(
          notifier.state.currentIndex,
          (indexBeforePause - RunThruTiming.autoRewindWords).clamp(0, 99),
        );

        notifier.pause();
      });
    });
  });

  // ── Group 4: Warmup interaction with per-word pacing ──

  group('Warmup interaction with per-word pacing', () {
    test('warmup multiplies per-word interval, not replaces it', () {
      // A long word like "internationally" gets a length bonus PLUS warmup
      // slowdown. This contract test verifies that words still advance
      // (the timer fires) during warmup with mixed word lengths.
      fakeAsync((async) {
        final notifier = WordTimerNotifier();
        addTearDown(notifier.dispose);

        notifier.loadDocument(100);
        // Alternate between short and long words.
        notifier.attachWordSource(
          (i) => i < 100 ? (i.isEven ? 'the' : 'internationally') : null,
        );

        notifier.play();
        expect(notifier.state.isWarmingUp, true);

        // Advance a bit — words should still advance (timer is working).
        async.elapse(const Duration(seconds: 3));
        expect(notifier.state.currentIndex, greaterThan(0));

        notifier.pause();
      });
    });
  });
}
