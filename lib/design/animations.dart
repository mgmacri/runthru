import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Animation duration constants from the FR-022 catalogue.
class SpeedyBoyAnimations {
  SpeedyBoyAnimations._();

  // ── A-001: Word advance breathe ──
  static const Duration wordAdvanceDuration = Duration(milliseconds: 80);
  static const Curve wordAdvanceCurve = Curves.easeOut;

  // ── A-002: Card press (z-drop + tilt) ──
  static const Duration cardPressDuration = Duration(milliseconds: 100);
  static const Curve cardPressCurve = Curves.easeIn;

  // ── A-003: Card release (spring back) ──
  static const Duration cardReleaseDuration = Duration(milliseconds: 150);

  static const SpringDescription cardReleaseSpring =
      SpringDescription(mass: 1.0, stiffness: 800, damping: 22);

  // ── A-004: Dial emerge (spring, 8% overshoot) ──
  static const Duration dialEmergeDuration = Duration(milliseconds: 220);

  static const SpringDescription dialEmergeSpring =
      SpringDescription(mass: 1.0, stiffness: 500, damping: 18);

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

  // ── A-012: Stereo lock-on ──
  static const Duration stereoLockOnDuration = Duration(milliseconds: 400);
  static const Curve stereoLockOnCurve = Curves.easeOut;

  // ── A-013: Stereo lost ──
  static const Duration stereoLostDuration = Duration(milliseconds: 300);
  static const Curve stereoLostCurve = Curves.easeIn;

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
    return SpringSimulation(
      cardReleaseSpring,
      from,
      to,
      velocity,
    );
  }

  /// Create a spring simulation for A-004 dial emerge.
  static SpringSimulation dialEmergeSimulation({
    double from = 0.0,
    double to = 1.0,
    double velocity = 0.0,
  }) {
    return SpringSimulation(
      dialEmergeSpring,
      from,
      to,
      velocity,
    );
  }

  /// Cube breathe sine wave value for a given controller value.
  /// Returns ±1.5° in radians.
  static double cubeBreatheAngle(double controllerValue) {
    return math.sin(controllerValue * 2 * math.pi) * 1.5 * math.pi / 180.0;
  }
}
