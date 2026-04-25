import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/core/context_reveal_notifier.dart';
import 'package:speedy_boy/core/context_reveal_state.dart';
import 'package:speedy_boy/core/word_timer.dart';

/// Integration tests for the gesture flow in reading mode.
///
/// Simulates the 7 gesture interactions from the spec:
/// 1. Tap (pause/resume + auto-rewind)
/// 2. Swipe left/right (sentence navigation — NOT in CR)
/// 3. Swipe up (CR entry)
/// 4. Swipe up in CR (tier advance)
/// 5. Swipe left/right in CR (window shift)
/// 6. Swipe down (CR dismiss + resume)
/// 7. Tap in CR (sweep pause/resume)
void main() {
  late ProviderContainer container;
  late ContextRevealNotifier crNotifier;
  late WordTimerNotifier wordTimer;

  setUp(() {
    container = ProviderContainer();
    crNotifier = container.read(contextRevealProvider.notifier);
    wordTimer = container.read(wordTimerProvider.notifier);
    wordTimer.loadDocument(200, startIndex: 0);
  });

  tearDown(() {
    container.dispose();
  });

  group('Gesture flow integration', () {
    test('1. Tap pause/resume with auto-rewind', () {
      wordTimer.play();
      wordTimer.seekTo(30);

      // Tap = pause
      wordTimer.pause();
      expect(container.read(wordTimerProvider).isPlaying, isFalse);

      // Tap = resume (with auto-rewind)
      wordTimer.play();
      expect(container.read(wordTimerProvider).isPlaying, isTrue);
      expect(container.read(wordTimerProvider).currentIndex, 27); // 30 - 3
    });

    test('3. Swipe up enters CR', () {
      wordTimer.play();
      wordTimer.seekTo(40);

      // Swipe up = pause + enter CR
      wordTimer.pause();
      crNotifier.enterSentence(40);

      expect(container.read(wordTimerProvider).isPlaying, isFalse);
      expect(container.read(contextRevealProvider).isActive, isTrue);
      expect(
        container.read(contextRevealProvider).tier,
        ContextRevealTier.sentence,
      );
    });

    test('4. Swipe up in CR at sentence is no-op (v4 ceiling)', () {
      wordTimer.pause();
      crNotifier.enterSentence(50);
      expect(
        container.read(contextRevealProvider).tier,
        ContextRevealTier.sentence,
      );

      // v4: no tier advancement, already at sentence
      // (elastic jiggle will be added in Sprint 2)
    });

    test('5. Swipe left/right in CR shifts window', () {
      crNotifier.enterSentence(60);

      crNotifier.shiftWindowForward(); // right
      expect(container.read(contextRevealProvider).windowOffset, 1);

      crNotifier.shiftWindowForward(); // right
      expect(container.read(contextRevealProvider).windowOffset, 2);

      crNotifier.shiftWindowBack(); // left
      expect(container.read(contextRevealProvider).windowOffset, 1);
    });

    test('6. Swipe down dismisses CR and resumes at correct word', () {
      wordTimer.play();
      wordTimer.seekTo(70);
      wordTimer.pause();
      crNotifier.enterSentence(70);

      // Shift window right
      crNotifier.shiftWindowForward();

      // Swipe down = dismiss + resume from leftmost visible word
      final resumeIndex = crNotifier.dismiss();
      expect(resumeIndex, 71); // 70 + 1 offset

      wordTimer.resumeFromContextReveal(resumeIndex);
      expect(container.read(wordTimerProvider).currentIndex, 71);
      expect(container.read(wordTimerProvider).isPlaying, isTrue);
      expect(container.read(contextRevealProvider).isActive, isFalse);
    });

    test('7. Tap in CR toggles sweep pause', () {
      crNotifier.enterSentence(80);
      expect(container.read(contextRevealProvider).isSweepPaused, isFalse);

      crNotifier.toggleSweepPause();
      expect(container.read(contextRevealProvider).isSweepPaused, isTrue);

      crNotifier.toggleSweepPause();
      expect(container.read(contextRevealProvider).isSweepPaused, isFalse);
    });

    test('full reading session: read → CR → resume → pause → resume', () {
      // Start reading
      wordTimer.play();
      wordTimer.seekTo(40);

      // Enter CR (v4: goes directly to sentence)
      wordTimer.pause();
      crNotifier.enterSentence(40);
      expect(container.read(contextRevealProvider).isActive, isTrue);

      // Shift window
      crNotifier.shiftWindowForward();
      crNotifier.shiftWindowForward();

      // Dismiss
      final resumeIndex = crNotifier.dismiss();
      expect(resumeIndex, 42); // 40 + 2

      // Resume without auto-rewind
      wordTimer.resumeFromContextReveal(resumeIndex);
      expect(container.read(wordTimerProvider).currentIndex, 42);

      // Normal pause
      wordTimer.pause();

      // Normal resume WITH auto-rewind
      wordTimer.play();
      expect(container.read(wordTimerProvider).currentIndex, 39); // 42 - 3
    });
  });
}
