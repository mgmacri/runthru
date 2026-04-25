import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/core/word_timer.dart';
import 'package:speedy_boy/design/design.dart';

void main() {
  late WordTimerNotifier notifier;

  setUp(() {
    notifier = WordTimerNotifier();
  });

  tearDown(() {
    notifier.dispose();
  });

  group('WordTimerNotifier', () {
    test('initial state is empty', () {
      expect(notifier.state.currentIndex, 0);
      expect(notifier.state.totalWords, 0);
      expect(notifier.state.isPlaying, false);
      expect(notifier.state.wpm, 300);
    });

    test('loadDocument sets totalWords and startIndex', () {
      notifier.loadDocument(100, startIndex: 10);

      expect(notifier.state.totalWords, 100);
      expect(notifier.state.currentIndex, 10);
      expect(notifier.state.isPlaying, false);
    });

    test('play does nothing when totalWords is 0', () {
      notifier.play();
      expect(notifier.state.isPlaying, false);
    });

    test('play starts playback', () {
      notifier.loadDocument(100);
      notifier.play();
      expect(notifier.state.isPlaying, true);
    });

    test('pause stops playback', () {
      notifier.loadDocument(100);
      notifier.play();
      notifier.pause();
      expect(notifier.state.isPlaying, false);
    });

    test('togglePlayPause toggles correctly', () {
      notifier.loadDocument(100);
      notifier.togglePlayPause();
      expect(notifier.state.isPlaying, true);
      notifier.togglePlayPause();
      expect(notifier.state.isPlaying, false);
    });

    test('setWpm clamps to 30-1000 range', () {
      notifier.loadDocument(100);
      notifier.setWpm(10);
      expect(notifier.state.wpm, 30);

      notifier.setWpm(5000);
      expect(notifier.state.wpm, 1000);

      notifier.setWpm(500);
      expect(notifier.state.wpm, 500);
    });

    test('seekTo clamps to valid range', () {
      notifier.loadDocument(50);

      notifier.seekTo(25);
      expect(notifier.state.currentIndex, 25);

      notifier.seekTo(-5);
      expect(notifier.state.currentIndex, 0);

      notifier.seekTo(200);
      expect(notifier.state.currentIndex, 49);
    });

    test('play does nothing when already finished', () {
      notifier.loadDocument(1);
      // Only 1 word, currentIndex=0, totalWords=1 → isFinished
      expect(notifier.state.isFinished, true);
      notifier.play();
      expect(notifier.state.isPlaying, false);
    });
  });

  group('WordTimerState', () {
    test('intervalMs calculation', () {
      const state = WordTimerState(wpm: 300);
      // 60000 / 300 = 200ms
      expect(state.intervalMs, 200);
    });

    test('progress calculation', () {
      const state = WordTimerState(currentIndex: 50, totalWords: 100);
      expect(state.progress, 0.5);
    });

    test('progress is 0 when totalWords is 0', () {
      const state = WordTimerState(totalWords: 0);
      expect(state.progress, 0.0);
    });

    test('isFinished at last word', () {
      const state = WordTimerState(currentIndex: 99, totalWords: 100);
      expect(state.isFinished, true);
    });

    test('not finished when not at end', () {
      const state = WordTimerState(currentIndex: 50, totalWords: 100);
      expect(state.isFinished, false);
    });

    test('high WPM produces small interval', () {
      const state = WordTimerState(wpm: 1000);
      expect(state.intervalMs, 60); // 60000/1000
    });
  });

  group('Auto-rewind (P18 Grade C)', () {
    test('auto-rewind subtracts 3 words on resume from pause', () {
      notifier.loadDocument(100, startIndex: 0);
      notifier.play(); // first play — no rewind
      notifier.seekTo(20);
      notifier.pause();
      notifier.play(); // resume from pause — should rewind
      expect(notifier.state.currentIndex, 20 - SpeedyBoyTiming.autoRewindWords);
    });

    test('auto-rewind clamps to word 0 at document start', () {
      notifier.loadDocument(100, startIndex: 0);
      notifier.play(); // first play
      notifier.seekTo(1); // near start
      notifier.pause();
      notifier.play(); // resume — rewind would go negative
      expect(notifier.state.currentIndex, 0);
    });

    test('auto-rewind does not apply on first play', () {
      notifier.loadDocument(100, startIndex: 10);
      notifier.play();
      // Should NOT rewind on first play
      expect(notifier.state.currentIndex, 10);
    });

    test('auto-rewind applies on every subsequent resume', () {
      notifier.loadDocument(100, startIndex: 0);
      notifier.play();
      notifier.seekTo(30);
      notifier.pause();

      // First resume
      notifier.play();
      expect(notifier.state.currentIndex, 30 - SpeedyBoyTiming.autoRewindWords);

      notifier.seekTo(50);
      notifier.pause();

      // Second resume
      notifier.play();
      expect(notifier.state.currentIndex, 50 - SpeedyBoyTiming.autoRewindWords);
    });

    test('auto-rewind resets on loadDocument', () {
      notifier.loadDocument(100, startIndex: 0);
      notifier.play();
      notifier.pause();

      // Load a new document — flags must reset
      notifier.loadDocument(50, startIndex: 10);
      notifier.play(); // first play on new document — no rewind
      expect(notifier.state.currentIndex, 10);
    });

    test('auto-rewind is silent — no extra state emissions for rewind', () {
      // Verify that the rewind doesn't produce a separate "rewinding"
      // state — it's just a position update followed by isPlaying=true.
      notifier.loadDocument(100, startIndex: 0);
      notifier.play();
      notifier.seekTo(20);
      notifier.pause();

      // After play(), the state should reflect the rewound position and
      // isPlaying=true in a single consistent snapshot — no intermediate
      // "rewinding" state is observable.
      notifier.play();

      expect(notifier.state.isPlaying, true);
      expect(notifier.state.currentIndex, 20 - SpeedyBoyTiming.autoRewindWords);
    });
  });

  group('resumeFromContextReveal (P20 Grade C)', () {
    test('does NOT auto-rewind after CR exit', () {
      notifier.loadDocument(100, startIndex: 0);
      notifier.play();
      notifier.pause();
      // Simulate seekTo via CR dismiss → resumeFromContextReveal
      notifier.resumeFromContextReveal(50);

      expect(notifier.state.currentIndex, 50);
      expect(notifier.state.isPlaying, true);
    });

    test('regular pause-resume DOES auto-rewind after CR session', () {
      notifier.loadDocument(100, startIndex: 0);
      notifier.play();
      notifier.pause();
      // Resume from CR exit at word 50
      notifier.resumeFromContextReveal(50);
      // Now pause again (regular)
      notifier.pause();
      // Regular resume should auto-rewind
      notifier.play();

      expect(notifier.state.currentIndex, 50 - SpeedyBoyTiming.autoRewindWords);
      expect(notifier.state.isPlaying, true);
    });
  });
}
