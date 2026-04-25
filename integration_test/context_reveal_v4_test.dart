import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/core/context_reveal_notifier.dart';
import 'package:speedy_boy/core/context_reveal_state.dart';
import 'package:speedy_boy/core/word_timer.dart';

/// TASK-129 — Integration test: simplified ContextReveal flow (v4).
///
/// Validates the 2-state ContextReveal model (Rule 20):
/// 1. Enter sentence view via swipe up
/// 2. Swipe up again → elastic jiggle (no tier change)
/// 3. Swipe left/right → sentence window shift
/// 4. Swipe down → resume from leftmost visible word
/// 5. No micro/clause states reachable
void main() {
  late ProviderContainer container;
  late ContextRevealNotifier crNotifier;
  late WordTimerNotifier wordTimer;

  setUp(() {
    container = ProviderContainer();
    crNotifier = container.read(contextRevealProvider.notifier);
    wordTimer = container.read(wordTimerProvider.notifier);

    // Load a document with 200 words, starting at word 0.
    wordTimer.loadDocument(200, startIndex: 0);
  });

  tearDown(() {
    container.dispose();
  });

  group('ContextReveal v4 — simplified 2-state flow', () {
    test('1. Start reading → swipe up → enters sentence view', () {
      // Start reading and advance to word 25.
      wordTimer.play();
      wordTimer.seekTo(25);
      expect(container.read(wordTimerProvider).isPlaying, isTrue);

      // Swipe up — pause RSVP and enter sentence view.
      wordTimer.pause();
      crNotifier.enterSentence(25);

      final crState = container.read(contextRevealProvider);
      expect(crState.tier, ContextRevealTier.sentence);
      expect(crState.isActive, isTrue);
      expect(crState.triggerWordIndex, 25);
      expect(crState.windowOffset, 0);
      expect(crState.sweepPosition, 0);
      expect(crState.isSweepPaused, isFalse);
      expect(container.read(wordTimerProvider).isPlaying, isFalse);
    });

    test('2. Swipe up again in sentence → elastic jiggle, no tier change', () {
      // Enter sentence view.
      wordTimer.pause();
      crNotifier.enterSentence(30);
      expect(
        container.read(contextRevealProvider).tier,
        ContextRevealTier.sentence,
      );

      // Swipe up again — triggers jiggle, NOT a tier change.
      crNotifier.triggerJiggle();

      final afterJiggle = container.read(contextRevealProvider);
      expect(afterJiggle.isJiggling, isTrue);
      expect(
        afterJiggle.tier,
        ContextRevealTier.sentence,
        reason: 'Tier must NOT change — sentence is the ceiling',
      );
      expect(afterJiggle.isActive, isTrue);

      // Widget calls clearJiggle() after animation completes.
      crNotifier.clearJiggle();
      expect(container.read(contextRevealProvider).isJiggling, isFalse);
      expect(
        container.read(contextRevealProvider).tier,
        ContextRevealTier.sentence,
      );
    });

    test('3. Swipe left/right → sentence window shift', () {
      crNotifier.enterSentence(40);

      // Swipe right (forward) twice.
      crNotifier.shiftWindowForward();
      expect(container.read(contextRevealProvider).windowOffset, 1);
      expect(
        container.read(contextRevealProvider).sweepPosition,
        0,
        reason: 'Sweep resets on window shift',
      );

      // Advance sweep, then shift again — sweep resets.
      crNotifier.advanceSweep(5);
      expect(container.read(contextRevealProvider).sweepPosition, 1);
      crNotifier.shiftWindowForward();
      expect(container.read(contextRevealProvider).windowOffset, 2);
      expect(container.read(contextRevealProvider).sweepPosition, 0);

      // Swipe left (back).
      crNotifier.shiftWindowBack();
      expect(container.read(contextRevealProvider).windowOffset, 1);
      expect(container.read(contextRevealProvider).sweepPosition, 0);

      // Resume position tracks the window offset.
      expect(container.read(contextRevealProvider).resumeWordIndex, 41);
    });

    test('4. Swipe down → dismiss, resume from leftmost visible word', () {
      wordTimer.play();
      wordTimer.seekTo(50);
      wordTimer.pause();
      crNotifier.enterSentence(50);

      // Shift window forward 3 times.
      crNotifier.shiftWindowForward();
      crNotifier.shiftWindowForward();
      crNotifier.shiftWindowForward();
      expect(container.read(contextRevealProvider).resumeWordIndex, 53);

      // Swipe down — dismiss.
      final resumeIndex = crNotifier.dismiss();
      expect(resumeIndex, 53, reason: 'Resume at triggerWordIndex + offset');
      expect(
        container.read(contextRevealProvider).tier,
        ContextRevealTier.none,
      );
      expect(container.read(contextRevealProvider).isActive, isFalse);

      // Resume RSVP without auto-rewind (Rule 20).
      wordTimer.resumeFromContextReveal(resumeIndex);
      expect(container.read(wordTimerProvider).currentIndex, 53);
      expect(container.read(wordTimerProvider).isPlaying, isTrue);
    });

    test('4b. Swipe down with negative offset resumes earlier', () {
      wordTimer.seekTo(60);
      wordTimer.pause();
      crNotifier.enterSentence(60);

      crNotifier.shiftWindowBack();
      crNotifier.shiftWindowBack();
      expect(container.read(contextRevealProvider).resumeWordIndex, 58);

      final resumeIndex = crNotifier.dismiss();
      expect(resumeIndex, 58);

      wordTimer.resumeFromContextReveal(resumeIndex);
      expect(container.read(wordTimerProvider).currentIndex, 58);
    });

    test('5. No micro/clause states reachable — exactly 2 tiers', () {
      // v4: ContextRevealTier has exactly 2 values.
      expect(ContextRevealTier.values.length, 2);
      expect(ContextRevealTier.values, contains(ContextRevealTier.none));
      expect(ContextRevealTier.values, contains(ContextRevealTier.sentence));

      // Verify none.next goes to sentence, sentence.next is null.
      expect(ContextRevealTier.none.next, ContextRevealTier.sentence);
      expect(
        ContextRevealTier.sentence.next,
        isNull,
        reason: 'Sentence is the ceiling — no further tiers',
      );
    });

    test('full v4 session: read → CR → jiggle → shift → dismiss → resume', () {
      // Start reading.
      wordTimer.play();
      wordTimer.seekTo(35);

      // Enter sentence view.
      wordTimer.pause();
      crNotifier.enterSentence(35);
      expect(container.read(contextRevealProvider).isActive, isTrue);

      // Swipe up again — jiggle.
      crNotifier.triggerJiggle();
      expect(container.read(contextRevealProvider).isJiggling, isTrue);
      crNotifier.clearJiggle();

      // Shift window forward.
      crNotifier.shiftWindowForward();
      crNotifier.shiftWindowForward();
      expect(container.read(contextRevealProvider).windowOffset, 2);

      // Toggle sweep pause.
      crNotifier.toggleSweepPause();
      expect(container.read(contextRevealProvider).isSweepPaused, isTrue);
      crNotifier.toggleSweepPause();
      expect(container.read(contextRevealProvider).isSweepPaused, isFalse);

      // Dismiss and resume.
      final resumeIndex = crNotifier.dismiss();
      expect(resumeIndex, 37);
      wordTimer.resumeFromContextReveal(resumeIndex);
      expect(container.read(wordTimerProvider).currentIndex, 37);
      expect(container.read(wordTimerProvider).isPlaying, isTrue);

      // Regular pause/resume after CR should auto-rewind.
      wordTimer.pause();
      wordTimer.play();
      expect(container.read(wordTimerProvider).currentIndex, 34); // 37 - 3
    });
  });
}
