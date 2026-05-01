import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Animation duration constants from the FR-022 catalogue.
class RunThruAnimations {
  RunThruAnimations._();

  // ── A-001: Word advance breathe ──
  static const Duration wordAdvanceDuration = Duration(milliseconds: 80);
  static const Curve wordAdvanceCurve = Curves.easeOut;

  // ── A-002: Card press (z-drop + tilt) ──
  static const Duration cardPressDuration = Duration(milliseconds: 100);
  static const Curve cardPressCurve = Curves.easeIn;

  // ── A-003: Card release (spring back) ──
  static const Duration cardReleaseDuration = Duration(milliseconds: 150);

  static const SpringDescription cardReleaseSpring = SpringDescription(
    mass: 1.0,
    stiffness: 800,
    damping: 22,
  );

  // ── A-004: Dial emerge (spring, 8% overshoot) ──
  static const Duration dialEmergeDuration = Duration(milliseconds: 220);

  static const SpringDescription dialEmergeSpring = SpringDescription(
    mass: 1.0,
    stiffness: 500,
    damping: 18,
  );

  // ── A-005: Dial dismiss ──
  static const Duration dialDismissDuration = Duration(milliseconds: 180);
  static const Curve dialDismissCurve = Curves.easeIn;

  // ── A-006: Pause fog in ──
  static const Duration pauseFogDuration = Duration(milliseconds: 200);
  static const Curve pauseFogCurve = Curves.easeIn;

  // ── A-007: Resume clear fog ──
  static const Duration resumeClearDuration = Duration(milliseconds: 150);
  static const Curve resumeClearCurve = Curves.easeOut;

  // ── A-008: Processing pulse ──
  static const Duration processingPulseDuration = Duration(milliseconds: 1200);
  static const Curve processingPulseCurve = Curves.easeInOut;

  // ── A-009: Status to ready ──
  static const Duration statusToReadyDuration = Duration(milliseconds: 400);
  static const Curve statusToReadyCurve = Curves.easeOut;

  // ── A-010: Cube rotation transition ──
  static const Duration cubeRotateDuration = Duration(milliseconds: 300);
  static const Curve cubeRotateCurve = Curves.easeInOut;

  // ── A-011: Cube breathe (idle oscillation) ──
  static const Duration cubeBreatheDuration = Duration(milliseconds: 8000);

  // ── A-012: Water Ripple Loading ──
  static const Duration waterRippleDuration = Duration(milliseconds: 2400);
  static const Curve waterRippleCurve = Curves.easeOut;
  static const int waterRippleRingCount = 3;
  static const Duration waterRippleStagger = Duration(milliseconds: 800);

  /// Vertical squash factor for neumorphic perspective on ripple ellipses.
  static const double waterRippleSquash = 0.85;

  // ── A-013: Word Depth Bounce-In ──
  // "Felt, not seen" — a barely perceptible depth cue.
  static const Duration wordDepthBounceDuration = Duration(milliseconds: 160);
  static const Curve wordDepthBounceCurve = SubtleBounceIn();

  /// Per-glyph stagger delay for the micro wave settling effect.
  static const int glyphStaggerMs = 6;

  /// Configure an AnimationController for a given animation.
  /// If [reducedMotion] is true, duration is zero (instant).
  static AnimationController createController({
    required TickerProvider vsync,
    required Duration duration,
    bool reducedMotion = false,
  }) {
    return AnimationController(
      vsync: vsync,
      duration: reducedMotion ? Duration.zero : duration,
    );
  }

  /// Create a spring simulation for A-003 card release.
  static SpringSimulation cardReleaseSimulation({
    double from = 1.0,
    double to = 0.0,
    double velocity = 0.0,
  }) {
    return SpringSimulation(cardReleaseSpring, from, to, velocity);
  }

  /// Create a spring simulation for A-004 dial emerge.
  static SpringSimulation dialEmergeSimulation({
    double from = 0.0,
    double to = 1.0,
    double velocity = 0.0,
  }) {
    return SpringSimulation(dialEmergeSpring, from, to, velocity);
  }

  // ── A-014: Elastic Jiggle (ceiling feedback) ──
  // P1 Grade C — underdamped spring for satisfying bounce-back
  // damping = 2 × dampingRatio × √(mass × stiffness) = 2 × 0.5 × √600 ≈ 24.5
  static const SpringDescription jiggleSpring = SpringDescription(
    mass: 1.0,
    stiffness: 600,
    damping: 24.5,
  );

  /// Create a spring simulation for the elastic jiggle spring-back phase.
  static SpringSimulation jiggleSimulation({
    double from = 1.0,
    double to = 0.0,
    double velocity = 0.0,
  }) {
    return SpringSimulation(jiggleSpring, from, to, velocity);
  }

  /// Cube breathe sine wave value for a given controller value.
  /// Returns ±1.5° in radians.
  static double cubeBreatheAngle(double controllerValue) {
    return math.sin(controllerValue * 2 * math.pi) * 1.5 * math.pi / 180.0;
  }
}

/// Custom curve with a single very subtle overshoot (4%).
///
/// t=0 → 0.0, t≈0.7 → 1.04 (4% overshoot), t=1.0 → 1.0.
/// The overshoot is imperceptible at reading speed — it's felt, not seen.
///
/// Implemented as a piecewise function:
/// - Phase 1 (0–0.7): quadratic ease-out to overshoot peak
/// - Phase 2 (0.7–1.0): settle back from overshoot to 1.0
class SubtleBounceIn extends Curve {
  const SubtleBounceIn();

  /// Maximum overshoot fraction (8%).
  static const double _overshoot = 0.08;

  @override
  double transformInternal(double t) {
    if (t <= 0.7) {
      // Phase 1: ease-out to 1.0 + overshoot
      final normalized = t / 0.7;
      // Quadratic ease-out: 1 - (1-t)^2, scaled to reach 1+overshoot
      final eased = 1.0 - (1.0 - normalized) * (1.0 - normalized);
      return eased * (1.0 + _overshoot);
    } else {
      // Phase 2: settle back from 1+overshoot to 1.0
      final normalized = (t - 0.7) / 0.3;
      const overshootValue = 1.0 + _overshoot;
      return overshootValue + (1.0 - overshootValue) * normalized;
    }
  }
}
