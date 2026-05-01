import 'package:runthru/design/design.dart';

/// Result of [classifySwipe] — the dominant direction of a pointer drag,
/// or `null` when the gesture does not meet both threshold gates.
enum SwipeDirection { left, right, up, down }

/// Classifies a completed pointer drag as a directional swipe.
///
/// Returns a [SwipeDirection] when **both** distance and velocity thresholds
/// are met for the dominant axis, or `null` when either gate fails.
///
/// * [dx], [dy] — signed drag deltas in logical pixels.
/// * [elapsedMs] — drag duration in milliseconds (pointer-down → pointer-up).
/// * [screenWidth], [screenHeight] — viewport dimensions for ratio gates.
///
/// Thresholds come from [RunThruGestures] tokens (Rule 24):
/// - Horizontal: 30 % of screen width **AND** 200 px/s
/// - Vertical:   20 % of screen height **AND** 150 px/s
SwipeDirection? classifySwipe({
  required double dx,
  required double dy,
  required int elapsedMs,
  required double screenWidth,
  required double screenHeight,
}) {
  final absDx = dx.abs();
  final absDy = dy.abs();

  // Avoid division by zero for instantaneous taps.
  if (elapsedMs <= 0) return null;

  final elapsedSec = elapsedMs / 1000.0;

  // Determine dominant axis from drag delta magnitude.
  if (absDy > absDx) {
    // ── Vertical candidate ──
    final velocityY = absDy / elapsedSec;
    final minDistance = screenHeight * RunThruGestures.verticalDistanceRatio;
    if (absDy >= minDistance &&
        velocityY >= RunThruGestures.verticalMinVelocity) {
      return dy < 0 ? SwipeDirection.up : SwipeDirection.down;
    }
  } else if (absDx > 0) {
    // ── Horizontal candidate ──
    final velocityX = absDx / elapsedSec;
    final minDistance = screenWidth * RunThruGestures.horizontalDistanceRatio;
    if (absDx >= minDistance &&
        velocityX >= RunThruGestures.horizontalMinVelocity) {
      return dx < 0 ? SwipeDirection.left : SwipeDirection.right;
    }
  }

  return null;
}
