import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/core/context_reveal_state.dart';

/// Riverpod notifier for ContextReveal state management.
///
/// AutoDispose: state is automatically reset when the reading screen is
/// popped (no listeners remain). This prevents stale `tier: sentence`
/// from persisting into a new reading session.
/// Rule 20: 2-state model (none ↔ sentence). No tier progression.
/// RSVP MUST be paused the instant state != none.
// P17 Grade C — ContextReveal notifier with auto-dispose
class ContextRevealNotifier extends AutoDisposeNotifier<ContextRevealState> {
  @override
  ContextRevealState build() => const ContextRevealState();

  /// Enter ContextReveal from RSVP at the given [wordIndex].
  ///
  /// Goes directly to [ContextRevealTier.sentence]. RSVP should be paused by
  /// the caller immediately before or after calling this.
  // v4 — enters directly at sentence (no micro/clause tiers)
  void enterSentence(int wordIndex) {
    state = ContextRevealState(
      tier: ContextRevealTier.sentence,
      triggerWordIndex: wordIndex,
      windowOffset: 0,
      sweepPosition: 0,
      isSweepPaused: false,
    );
  }

  /// Dismiss ContextReveal. Returns the resume word index (leftmost visible).
  ///
  /// Caller should use this index to resume RSVP at the correct position.
  // P17 Grade C — dismiss returns leftmost visible word, not trigger word
  int dismiss() {
    final resumeIndex = state.resumeWordIndex;
    state = const ContextRevealState();
    return resumeIndex;
  }

  /// Shift the visible window one word to the left (earlier in text).
  ///
  /// No-op if shifting would go below word index 0.
  void shiftWindowBack() {
    if (state.resumeWordIndex <= 0) return;
    state = state.copyWith(
      windowOffset: state.windowOffset - 1,
      sweepPosition: 0, // reset sweep on navigation
    );
  }

  /// Shift the visible window one word to the right (later in text).
  ///
  /// Caller must validate against document length before calling;
  /// this method has no upper-bound guard.
  void shiftWindowForward() {
    state = state.copyWith(
      windowOffset: state.windowOffset + 1,
      sweepPosition: 0, // reset sweep on navigation
    );
  }

  /// Toggle the gradient sweep between paused and running.
  void toggleSweepPause() {
    state = state.copyWith(isSweepPaused: !state.isSweepPaused);
  }

  /// Advance the sweep position by one word.
  ///
  /// [visibleWordCount] is the number of words currently displayed.
  /// Returns `true` if the sweep reached the last word (end of sentence).
  bool advanceSweep(int visibleWordCount) {
    if (state.isSweepPaused) return false;
    if (visibleWordCount <= 0) return false;
    final next = state.sweepPosition + 1;
    if (next >= visibleWordCount) return true; // signal end of sentence
    state = state.copyWith(sweepPosition: next);
    return false;
  }

  /// Reset the sweep position to the first word.
  ///
  /// Used by double-tap in sentence view (TASK-106).
  // P4 Grade C — double-tap restarts sweep from first word
  void resetSweep() {
    state = state.copyWith(sweepPosition: 0);
  }

  /// Signal that an elastic jiggle animation should play.
  ///
  /// Used when swipe-up fires while already in sentence view (ceiling
  /// feedback). The overlay widget observes [isJiggling], runs the animation,
  /// and calls [clearJiggle] when complete.
  // P1 Grade C — elastic jiggle ceiling feedback
  void triggerJiggle() {
    state = state.copyWith(isJiggling: true);
  }

  /// Clear the jiggle flag after the animation completes.
  void clearJiggle() {
    state = state.copyWith(isJiggling: false);
  }
}

final contextRevealProvider =
    NotifierProvider.autoDispose<ContextRevealNotifier, ContextRevealState>(
      ContextRevealNotifier.new,
    );
