// v4 — simplified from v3's { none, micro, clause, sentence }
/// The 2 states of ContextReveal comprehension recovery.
///
/// Swipe up enters sentence view. Swipe down dismisses.
/// Dismissal always jumps directly to [none].
// P17 Grade C — ContextReveal state machine (Rule 20)
enum ContextRevealTier {
  /// RSVP running normally, no context overlay.
  none,

  /// Full current sentence.
  sentence;

  /// Returns the next tier, or null if already at [sentence].
  ContextRevealTier? get next => switch (this) {
    none => sentence,
    sentence => null,
  };

  /// Number of words visible in this tier (0 for none, -1 for sentence = full).
  int get wordCount => switch (this) {
    none => 0,
    sentence => -1, // full sentence
  };
}

/// Immutable state for the ContextReveal comprehension recovery system.
///
/// [triggerWordIndex] is the word index at the moment the user entered CR.
/// [windowOffset] shifts the visible window left/right from the trigger.
/// [sweepPosition] is the 0-indexed position within the visible words
/// that the gradient sweep is currently highlighting.
class ContextRevealState {
  const ContextRevealState({
    this.tier = ContextRevealTier.none,
    this.triggerWordIndex = 0,
    this.windowOffset = 0,
    this.sweepPosition = 0,
    this.isSweepPaused = false,
    this.isJiggling = false,
  });

  final ContextRevealTier tier;

  /// Word index at the moment the user entered ContextReveal.
  final int triggerWordIndex;

  /// Offset from trigger to shift the visible window (negative = left).
  final int windowOffset;

  /// Current sweep highlight position (0-indexed within visible words).
  final int sweepPosition;

  /// Whether the gradient sweep is paused.
  final bool isSweepPaused;

  /// Transient flag — true when the elastic jiggle animation should play.
  /// Widget observes this, runs the animation, then calls clearJiggle().
  // P1 Grade C — ceiling feedback when swiping up in sentence view
  final bool isJiggling;

  /// Whether ContextReveal is active (any tier other than none).
  bool get isActive => tier != ContextRevealTier.none;

  /// The leftmost visible word index — this is where RSVP resumes on dismiss.
  // P17 Grade C — resume position is leftmost visible word, NOT trigger word
  int get resumeWordIndex => triggerWordIndex + windowOffset;

  ContextRevealState copyWith({
    ContextRevealTier? tier,
    int? triggerWordIndex,
    int? windowOffset,
    int? sweepPosition,
    bool? isSweepPaused,
    bool? isJiggling,
  }) => ContextRevealState(
    tier: tier ?? this.tier,
    triggerWordIndex: triggerWordIndex ?? this.triggerWordIndex,
    windowOffset: windowOffset ?? this.windowOffset,
    sweepPosition: sweepPosition ?? this.sweepPosition,
    isSweepPaused: isSweepPaused ?? this.isSweepPaused,
    isJiggling: isJiggling ?? this.isJiggling,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContextRevealState &&
          tier == other.tier &&
          triggerWordIndex == other.triggerWordIndex &&
          windowOffset == other.windowOffset &&
          sweepPosition == other.sweepPosition &&
          isSweepPaused == other.isSweepPaused &&
          isJiggling == other.isJiggling;

  @override
  int get hashCode => Object.hash(
    tier,
    triggerWordIndex,
    windowOffset,
    sweepPosition,
    isSweepPaused,
    isJiggling,
  );
}
