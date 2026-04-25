import 'dart:math' as math;

import 'package:speedy_boy/design/design.dart';

/// Which word-entrance animation to use.
enum WordTransition { a001Breathe, a013BounceIn }

/// Result of [selectWordTransition]: which animation to play and its base
/// duration in milliseconds.
typedef WordTransitionResult = ({
  WordTransition transition,
  int baseDurationMs,
});

/// Select the word entrance animation based on WPM and word characteristics.
///
/// - Above [SpeedyBoyTiming.a013FallbackWpmThreshold] WPM: falls back to
///   A-001 breathe to eliminate timing overrun at high speeds.
/// - At or below the threshold: uses A-013 bounce-in with duration capped at
///   [SpeedyBoyTiming.a013MaxDisplayFraction] of [displayMs], accounting for
///   per-glyph stagger, and floored at [SpeedyBoyTiming.a013MinBaseDuration].
WordTransitionResult selectWordTransition({
  required int wpm,
  required int charCount,
  required int displayMs,
}) {
  // P6 Grade A — above threshold, A-013 overruns the display budget; fall back
  if (wpm > SpeedyBoyTiming.a013FallbackWpmThreshold) {
    return (
      transition: WordTransition.a001Breathe,
      baseDurationMs: SpeedyBoyAnimations.wordAdvanceDuration.inMilliseconds,
    );
  }

  // P6 Grade A — at or below threshold, use A-013 with adaptive capping
  final int staggerTotal =
      SpeedyBoyAnimations.glyphStaggerMs * math.max<int>(0, charCount - 1);
  final int budget =
      (displayMs * SpeedyBoyTiming.a013MaxDisplayFraction).floor() -
      staggerTotal;

  // P6 Grade A — hard floor prevents sub-perceptual display times
  final int baseDurationMs = math.max<int>(
    SpeedyBoyTiming.a013MinBaseDuration,
    budget,
  );

  return (
    transition: WordTransition.a013BounceIn,
    baseDurationMs: baseDurationMs,
  );
}
