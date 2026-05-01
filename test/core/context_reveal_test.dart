import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/context_reveal_notifier.dart';
import 'package:runthru/core/context_reveal_state.dart';

void main() {
  group('ContextRevealTier', () {
    test('tier ordering: none → sentence', () {
      expect(ContextRevealTier.none.next, ContextRevealTier.sentence);
      expect(ContextRevealTier.sentence.next, isNull);
    });

    test('wordCount returns correct values', () {
      expect(ContextRevealTier.none.wordCount, 0);
      expect(ContextRevealTier.sentence.wordCount, -1);
    });
  });

  group('ContextRevealState', () {
    test('resumeWordIndex returns leftmost visible word', () {
      const state = ContextRevealState(
        tier: ContextRevealTier.sentence,
        triggerWordIndex: 42,
        windowOffset: -2,
      );
      // Resume at word 40 (trigger 42 + offset -2)
      expect(state.resumeWordIndex, 40);
    });

    test('isActive returns true when tier != none', () {
      expect(const ContextRevealState().isActive, isFalse);
      expect(
        const ContextRevealState(tier: ContextRevealTier.sentence).isActive,
        isTrue,
      );
    });

    test('copyWith preserves unmodified fields', () {
      const state = ContextRevealState(
        tier: ContextRevealTier.sentence,
        triggerWordIndex: 10,
        windowOffset: 3,
        sweepPosition: 2,
        isSweepPaused: true,
      );
      final copy = state.copyWith(sweepPosition: 0);
      expect(copy.tier, ContextRevealTier.sentence);
      expect(copy.triggerWordIndex, 10);
      expect(copy.windowOffset, 3);
      expect(copy.sweepPosition, 0);
      expect(copy.isSweepPaused, isTrue);
    });
  });

  group('ContextRevealNotifier', () {
    late ProviderContainer container;
    late ContextRevealNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(contextRevealProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('initial state is none', () {
      final state = container.read(contextRevealProvider);
      expect(state.tier, ContextRevealTier.none);
      expect(state.isActive, isFalse);
    });

    test('enter sets sentence tier and trigger index', () {
      notifier.enterSentence(25);
      final state = container.read(contextRevealProvider);
      expect(state.tier, ContextRevealTier.sentence);
      expect(state.triggerWordIndex, 25);
      expect(state.windowOffset, 0);
      expect(state.sweepPosition, 0);
    });

    test('dismiss returns resume index and resets to none', () {
      notifier.enterSentence(50);
      notifier.shiftWindowBack(); // offset = -1

      final resumeIndex = notifier.dismiss();
      expect(resumeIndex, 49); // 50 + (-1)
      expect(
        container.read(contextRevealProvider).tier,
        ContextRevealTier.none,
      );
    });

    test('shiftWindowBack decrements offset and resets sweep', () {
      notifier.enterSentence(20);
      notifier.advanceSweep(3); // sweep at 1
      notifier.shiftWindowBack();

      final state = container.read(contextRevealProvider);
      expect(state.windowOffset, -1);
      expect(state.sweepPosition, 0); // reset
      expect(state.resumeWordIndex, 19);
    });

    test('shiftWindowBack is no-op at word 0', () {
      notifier.enterSentence(0);
      notifier.shiftWindowBack();

      expect(container.read(contextRevealProvider).windowOffset, 0);
    });

    test('shiftWindowForward increments offset and resets sweep', () {
      notifier.enterSentence(10);
      notifier.shiftWindowForward();

      final state = container.read(contextRevealProvider);
      expect(state.windowOffset, 1);
      expect(state.sweepPosition, 0);
    });

    test('toggleSweepPause toggles pause state', () {
      notifier.enterSentence(5);
      expect(container.read(contextRevealProvider).isSweepPaused, isFalse);

      notifier.toggleSweepPause();
      expect(container.read(contextRevealProvider).isSweepPaused, isTrue);

      notifier.toggleSweepPause();
      expect(container.read(contextRevealProvider).isSweepPaused, isFalse);
    });

    test('advanceSweep holds on last word', () {
      notifier.enterSentence(10);

      notifier.advanceSweep(3); // position 0 → 1
      expect(container.read(contextRevealProvider).sweepPosition, 1);

      notifier.advanceSweep(3); // position 1 → 2
      expect(container.read(contextRevealProvider).sweepPosition, 2);

      notifier.advanceSweep(
        3,
      ); // position 2 → hold (3 words, 0-indexed max = 2)
      expect(container.read(contextRevealProvider).sweepPosition, 2);
    });

    test('advanceSweep is no-op when paused', () {
      notifier.enterSentence(10);
      notifier.toggleSweepPause();

      notifier.advanceSweep(3);
      expect(container.read(contextRevealProvider).sweepPosition, 0);
    });

    test('triggerJiggle sets isJiggling flag', () {
      notifier.enterSentence(10);
      expect(container.read(contextRevealProvider).isJiggling, isFalse);

      notifier.triggerJiggle();
      expect(container.read(contextRevealProvider).isJiggling, isTrue);
    });

    test('clearJiggle resets isJiggling flag', () {
      notifier.enterSentence(10);
      notifier.triggerJiggle();
      expect(container.read(contextRevealProvider).isJiggling, isTrue);

      notifier.clearJiggle();
      expect(container.read(contextRevealProvider).isJiggling, isFalse);
    });

    test('dismiss clears isJiggling', () {
      notifier.enterSentence(10);
      notifier.triggerJiggle();

      notifier.dismiss();
      final state = container.read(contextRevealProvider);
      expect(state.isJiggling, isFalse);
      expect(state.tier, ContextRevealTier.none);
    });
  });
}
