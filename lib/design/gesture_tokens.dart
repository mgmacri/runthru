/// V4 gesture tokens — swipe distance and velocity thresholds for the
/// reading viewport gesture system. Consumed by [classifySwipe] in
/// `lib/core/gesture_classifier.dart`.
abstract final class RunThruGestures {
  // ── Horizontal Swipe (P3 Grade C) ──

  /// Minimum horizontal drag distance as a ratio of screen width.
  // P3 Grade C — calibrated from Android testing; 30% prevents accidental fires
  static const double horizontalDistanceRatio = 0.30;

  /// Minimum horizontal velocity in pixels per second.
  // P3 Grade C — 200 px/s filters out slow scrolls
  static const double horizontalMinVelocity = 200.0;

  // ── Vertical Swipe (P3 Grade C) ──

  /// Minimum vertical drag distance as a ratio of screen height.
  // P3 Grade C — 20% balances reachability vs. false positives
  static const double verticalDistanceRatio = 0.20;

  /// Minimum vertical velocity in pixels per second.
  // P3 Grade C — 150 px/s accommodates slower deliberate swipes
  static const double verticalMinVelocity = 150.0;
}
