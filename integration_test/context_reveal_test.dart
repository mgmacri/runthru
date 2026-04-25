import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/core/context_reveal_notifier.dart';
import 'package:speedy_boy/core/context_reveal_state.dart';
import 'package:speedy_boy/core/word_timer.dart';

/// Integration tests for the ContextReveal → WordTimer interaction.
///
/// These verify the full flow: enter CR, advance tiers, shift window,
/// dismiss, and resume from the correct word index.
void main() {
  late ProviderContainer container;
  late ContextRevealNotifier crNotifier;
  late WordTimerNotifier wordTimer;

  setUp(() {
    container = ProviderContainer();
    crNotifier = container.read(contextRevealProvider.notifier);
    wordTimer = container.read(wordTimerProvider.notifier);

    // Load a document with 100 words, starting at word 0
    wordTimer.loadDocument(100, startIndex: 0);
  });

  tearDown(() {
    container.dispose();
  });

  group('ContextReveal full flow integration', () {
    test('enter → sentence → dismiss resumes correctly', () {
      // Start reading at word 20
      wordTimer.seekTo(20);
      wordTimer.play();
      expect(container.read(wordTimerProvider).isPlaying, isTrue);

      // Swipe up — pause and enter CR at word 20 (v4: directly to sentence)
      wordTimer.pause();
      crNotifier.enterSentence(20);
      final afterEnter = container.read(contextRevealProvider);
      expect(afterEnter.tier, ContextRevealTier.sentence);
      expect(afterEnter.triggerWordIndex, 20);
      expect(container.read(wordTimerProvider).isPlaying, isFalse);

      // Swipe down — dismiss and resume
      final resumeIndex = crNotifier.dismiss();
      expect(resumeIndex, 20); // no window shift, so resume at trigger
      expect(
        container.read(contextRevealProvider).tier,
        ContextRevealTier.none,
      );

      // Resume without auto-rewind
      wordTimer.resumeFromContextReveal(resumeIndex);
      expect(container.read(wordTimerProvider).currentIndex, 20);
      expect(container.read(wordTimerProvider).isPlaying, isTrue);
    });

    test('window shift changes resume position', () {
      wordTimer.seekTo(30);
      wordTimer.pause();
      crNotifier.enterSentence(30);

      // Shift window right twice
      crNotifier.shiftWindowForward();
      crNotifier.shiftWindowForward();
      expect(container.read(contextRevealProvider).windowOffset, 2);

      // Dismiss — resume from offset position
      final resumeIndex = crNotifier.dismiss();
      expect(resumeIndex, 32); // 30 + 2

      wordTimer.resumeFromContextReveal(resumeIndex);
      expect(container.read(wordTimerProvider).currentIndex, 32);
    });

    test('window shift back then dismiss resumes earlier', () {
      wordTimer.seekTo(50);
      wordTimer.pause();
      crNotifier.enterSentence(50);

      crNotifier.shiftWindowBack();
      crNotifier.shiftWindowBack();
      expect(container.read(contextRevealProvider).windowOffset, -2);

      final resumeIndex = crNotifier.dismiss();
      expect(resumeIndex, 48); // 50 + (-2)

      wordTimer.resumeFromContextReveal(resumeIndex);
      expect(container.read(wordTimerProvider).currentIndex, 48);
    });

    test('sweep advance holds on last word', () {
      crNotifier.enterSentence(10);
      const visibleWords = 5; // simulate 5 visible words in sentence view

      // Advance sweep through all words
      for (var i = 0; i < visibleWords + 2; i++) {
        crNotifier.advanceSweep(visibleWords);
      }

      // Should hold at last word (index 4 for 5 words)
      expect(
        container.read(contextRevealProvider).sweepPosition,
        visibleWords - 1,
      );
    });

    test('sweep resets on window shift', () {
      crNotifier.enterSentence(10);
      crNotifier.advanceSweep(3); // sweep to 1
      expect(container.read(contextRevealProvider).sweepPosition, 1);

      crNotifier.shiftWindowForward();
      expect(container.read(contextRevealProvider).sweepPosition, 0); // reset
    });

    test('CR exit then regular pause-resume still auto-rewinds', () {
      // Initial play
      wordTimer.play();
      wordTimer.seekTo(50);

      // Enter and exit CR
      wordTimer.pause();
      crNotifier.enterSentence(50);
      final resumeIndex = crNotifier.dismiss();
      wordTimer.resumeFromContextReveal(resumeIndex);

      // Now regular pause and resume
      wordTimer.pause();
      wordTimer.play();

      // Should have auto-rewound 3 words
      expect(container.read(wordTimerProvider).currentIndex, 47);
    });

    test('CR does not auto-rewind on resume', () {
      wordTimer.play();
      wordTimer.seekTo(50);

      // Pause (sets _wasPaused = true)
      wordTimer.pause();

      // Enter CR
      crNotifier.enterSentence(50);

      // Dismiss CR and resume via resumeFromContextReveal
      final resumeIndex = crNotifier.dismiss();
      wordTimer.resumeFromContextReveal(resumeIndex);

      // Should NOT have auto-rewound — resumeFromContextReveal skips it
      expect(container.read(wordTimerProvider).currentIndex, 50);
    });
  });
}
