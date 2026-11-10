import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/word_timer.dart';
import 'package:runthru/features/reading/pacing/word_duration.dart';

/// The reader's promise: at N words per minute, N words go by in a minute.
///
/// For its first eight months the timer showed every word after the first
/// for twice its time (a drift correction that measured the wrong span), so
/// "250 WPM" read at 125. Nothing tested the rate. These do.
void main() {
  /// Words advanced in [measure] after [settle] of play at [wpm].
  int advanced(
    FakeAsync async,
    WordTimerNotifier notifier, {
    Duration settle = const Duration(seconds: 20),
    Duration measure = const Duration(minutes: 1),
  }) {
    async.elapse(settle);
    final start = notifier.state.currentIndex;
    async.elapse(measure);
    return notifier.state.currentIndex - start;
  }

  group('word rate', () {
    for (final wpm in [60, 150, 250, 300, 450, 600, 1000]) {
      test('$wpm WPM shows $wpm words in a minute', () {
        fakeAsync((async) {
          final notifier = WordTimerNotifier();
          addTearDown(notifier.dispose);
          notifier.loadDocument(200000);
          notifier.setWpm(wpm);
          notifier.play();

          // Past the warm-up ramp, one clean minute.
          final words = advanced(async, notifier);
          // The interval is whole milliseconds (60000 ~/ wpm), so the rate
          // can sit a hair above the nominal figure, never below it.
          final interval = notifier.state.intervalMs;
          expect(words, closeTo(60000 / interval, 1));
          expect(words, greaterThanOrEqualTo(wpm - 1));
          expect(words, lessThanOrEqualTo((wpm * 1.02).ceil() + 1));
          notifier.pause();
        });
      });
    }

    test('every word stays up for its interval, the second included', () {
      fakeAsync((async) {
        final notifier = WordTimerNotifier();
        addTearDown(notifier.dispose);
        notifier.loadDocument(1000);
        notifier.setWpm(300); // 200 ms a word
        notifier.play();
        // Leave the warm-up behind, then pause and play again on a clean
        // word boundary.
        async.elapse(const Duration(seconds: 15));
        notifier.pause();
        notifier.play();
        final start = notifier.state.currentIndex;

        async.elapse(const Duration(milliseconds: 199));
        expect(notifier.state.currentIndex, start);
        async.elapse(const Duration(milliseconds: 2));
        expect(notifier.state.currentIndex, start + 1);
        // The second word used to stay for 400 ms.
        async.elapse(const Duration(milliseconds: 198));
        expect(notifier.state.currentIndex, start + 1);
        async.elapse(const Duration(milliseconds: 2));
        expect(notifier.state.currentIndex, start + 2);
        async.elapse(const Duration(milliseconds: 200));
        expect(notifier.state.currentIndex, start + 3);
        notifier.pause();
      });
    });

    test('the first minute is only slower by the warm-up ramp', () {
      fakeAsync((async) {
        final notifier = WordTimerNotifier();
        addTearDown(notifier.dispose);
        notifier.loadDocument(200000);
        notifier.setWpm(300);
        notifier.play();
        async.elapse(const Duration(minutes: 1));
        final words = notifier.state.currentIndex;
        // Ten seconds ramping from 80% to full speed cost about five words.
        expect(words, greaterThan(285));
        expect(words, lessThanOrEqualTo(300));
        notifier.pause();
      });
    });
  });

  group('late ticks', () {
    test('a busy frame is made up on the next word', () {
      fakeAsync((async) {
        final notifier = WordTimerNotifier();
        addTearDown(notifier.dispose);
        notifier.loadDocument(200000);
        notifier.setWpm(300); // 200 ms a word
        notifier.play();
        async.elapse(const Duration(seconds: 20));
        final start = notifier.state.currentIndex;

        // For a minute, the UI thread stalls for 60 ms inside every second:
        // each stall delays one tick.
        for (var second = 0; second < 60; second++) {
          async.elapse(const Duration(milliseconds: 470));
          async.elapseBlocking(const Duration(milliseconds: 60));
          async.elapse(const Duration(milliseconds: 470));
        }
        final words = notifier.state.currentIndex - start;
        // Still a minute's worth of words, not 300 minus the stalls.
        expect(words, closeTo(300, 2));
        notifier.pause();
      });
    });

    test('a long stall never squeezes the next word below half its time', () {
      fakeAsync((async) {
        final notifier = WordTimerNotifier();
        addTearDown(notifier.dispose);
        notifier.loadDocument(1000);
        notifier.setWpm(300); // 200 ms a word
        notifier.play();
        async.elapse(const Duration(seconds: 15));

        // The app is frozen for three seconds; then the overdue tick fires.
        async.elapseBlocking(const Duration(seconds: 3));
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        final afterStall = notifier.state.currentIndex;

        // The word that came up is readable: at least 100 ms.
        async.elapse(const Duration(milliseconds: 99));
        expect(notifier.state.currentIndex, afterStall);
        async.elapse(const Duration(milliseconds: 2));
        expect(notifier.state.currentIndex, afterStall + 1);
        // And the stall is not paid back by racing through later words.
        async.elapse(const Duration(milliseconds: 198));
        expect(notifier.state.currentIndex, afterStall + 1);
        notifier.pause();
      });
    });
  });

  group('per-word pacing', () {
    test('a passage takes exactly the sum of its word durations', () {
      fakeAsync((async) {
        const sentence = [
          'The',
          'lighthouse',
          'keeper,',
          'unaccustomed',
          'to',
          'visitors,',
          'waited.',
        ];
        final words = [for (var i = 0; i < 40; i++) ...sentence];
        final notifier = WordTimerNotifier();
        addTearDown(notifier.dispose);
        notifier.loadDocument(words.length);
        notifier.attachWordSource(
          (i) => i >= 0 && i < words.length ? words[i] : null,
        );
        notifier.setWpm(300);
        notifier.play();
        // Warm-up over, then time one whole sentence from a clean start.
        async.elapse(const Duration(seconds: 12));
        notifier.pause();
        final at = (notifier.state.currentIndex ~/ 7 + 1) * 7;
        notifier.seekTo(at);
        notifier.resumeFromContextReveal(at);

        var expectedMs = 0;
        for (var i = at; i < at + 7; i++) {
          expectedMs += durationForWord(
            words[i],
            nextWord: words[i + 1],
            baseIntervalMs: notifier.state.intervalMs,
            config: notifier.state.pacingConfig,
          );
        }
        // Longer than seven bare intervals: pauses and long words count.
        expect(expectedMs, greaterThan(7 * 200));

        async.elapse(Duration(milliseconds: expectedMs - 1));
        expect(notifier.state.currentIndex, at + 6);
        async.elapse(const Duration(milliseconds: 2));
        expect(notifier.state.currentIndex, at + 7);
        notifier.pause();
      });
    });
  });
}
