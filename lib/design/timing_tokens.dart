/// Timing tokens — all animation durations, thresholds, and window sizes.
/// Consumed by ContextReveal, Room Intensity, A-013 adaptive timing,
/// auto-rewind, elastic jiggle, WPM dial, and overlay hint systems.
abstract final class RunThruTiming {
  // ── Auto-Rewind (P18 Grade C) ──

  /// Number of words to rewind when resuming from pause.
  // P18 Grade C — auto-rewind 3 words on resume from pause
  static const int autoRewindWords = 3;

  // ── ContextReveal (P17 Grade C) ──

  /// Duration of the gradient sweep animation in milliseconds.
  // P17 Grade C — sweep reveals surrounding context over 400ms
  static const int contextRevealSweepMs = 400;

  /// Opacity applied to dimmed (non-highlighted) words in the overlay.
  // P17 Grade C — dim non-focus words to 60% opacity
  static const double contextRevealDimOpacity = 0.6;

  /// Duration of the ContextReveal enter animation.
  // P17 Grade C — overlay enters in 200ms
  static const Duration contextRevealEnter = Duration(milliseconds: 200);

  /// Duration of the ContextReveal exit animation.
  // P17 Grade C — overlay exits in 150ms
  static const Duration contextRevealExit = Duration(milliseconds: 150);

  /// Delay between sentences in sentence mode sweep, allowing the
  /// user's eyes to move from the last word (bottom-right) back to
  /// the first word (upper-left) of the new sentence.
  // Grade D — tunable
  static const int sentenceGapMs = 600;

  // ── Room Intensity (P7 Grade C/D) ──

  /// Seconds to hold current room intensity before allowing a change.
  // P7 Grade C — hysteresis prevents rapid intensity flickering
  static const int roomHysteresisHoldSeconds = 30;

  /// Number of recent words in the difficulty rolling window.
  // P7 Grade C — rolling window of 5 words for difficulty estimation
  static const int roomDifficultyWindowSize = 5;

  /// Difficulty score above which room intensity increases.
  // P7 Grade D — tunable
  static const double roomDifficultyThresholdHigh = 9.0;

  /// Difficulty score below which room intensity decreases.
  // P7 Grade D — tunable
  static const double roomDifficultyThresholdLow = 4.0;

  // ── A-013 Adaptive Timing (P6 Grade A) ──

  /// WPM threshold below which A-013 bounce-in is used instead of A-001.
  // P6 Grade A — below 300 WPM, use bounce-in for better readability
  static const int a013FallbackWpmThreshold = 300;

  /// Maximum fraction of the base word interval consumed by the transition.
  // P6 Grade A — transition never exceeds 60% of display time
  static const double a013MaxDisplayFraction = 0.6;

  /// Minimum base duration in milliseconds for adaptive timing floor.
  // P6 Grade A — hard floor prevents sub-perceptual display times
  static const int a013MinBaseDuration = 40;

  // ── Double-Tap (P4 Grade C) ──

  /// Duration of the flash highlight on sentence restart in milliseconds.
  // P4 Grade C — brief visual confirmation of sentence restart
  static const int restartHighlightMs = 200;

  /// Window in milliseconds to detect a double-tap (vs single-tap).
  // P4 Grade C — 300ms double-tap detection window (platform standard)
  static const int doubleTapWindowMs = 300;

  // ── v4: Elastic Jiggle (P1 Grade C) ──

  /// Duration of the scale-up phase in milliseconds.
  // P1 Grade C — quick scale-up for ceiling feedback on swipe-up in sentence view
  static const int jiggleScaleUpMs = 100;

  /// Duration of the spring-back phase in milliseconds.
  // P1 Grade C — damped spring return after jiggle
  static const int jiggleSpringBackMs = 200;

  /// Maximum scale factor during jiggle.
  // P1 Grade C — 20% overshoot for perceptible but non-jarring feedback
  static const double jiggleMaxScale = 1.2;

  /// Damping ratio for the jiggle spring-back (0.5 = underdamped).
  // P1 Grade C — underdamped spring for satisfying bounce
  static const double jiggleDampingRatio = 0.5;

  // ── v4: WPM Dial (P2 Grade C) ──

  /// Inactivity timeout before the WPM dial auto-dismisses in milliseconds.
  // P2 Grade C — auto-dismiss after 1.5s of no interaction
  static const int wpmDialInactivityMs = 1500;

  /// Fade duration for the WPM dial appear/dismiss in milliseconds.
  // P2 Grade C — quick fade for dial transitions
  static const int wpmDialFadeMs = 200;

  /// WPM increment per dial step.
  // P2 Grade D — tunable
  static const int wpmDialStep = 25;

  // ── v4: Overlay Hints (P6 Grade D) ──

  /// Auto-dismiss timeout for hint overlays in milliseconds.
  // P6 Grade D — tunable
  static const int hintAutoDismissMs = 4000;

  /// Slide-in animation duration for hint overlays in milliseconds.
  // P6 Grade D — tunable
  static const int hintSlideInMs = 200;
}
