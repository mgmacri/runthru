import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 3D animation transform factories for CustomPainter consumption.
/// Each returns a function: (double t) → Matrix4.
class RunThruAnimations3D {
  RunThruAnimations3D._();

  /// A-001: Word advance breathe — slight z-scale pulse.
  static Matrix4 Function(double t) wordAdvanceBreathe({
    bool reducedMotion = false,
  }) {
    if (reducedMotion) return (_) => Matrix4.identity();
    return (double t) {
      final scale = 1.0 + 0.02 * math.sin(t * math.pi);
      return Matrix4.identity()..scaleByDouble(scale, scale, scale, 1.0);
    };
  }

  /// A-004: Dial emerge from below with spring overshoot.
  static Matrix4 Function(double t) dialEmerge3D({
    required double emergeDy,
    bool reducedMotion = false,
  }) {
    if (reducedMotion) return (_) => Matrix4.identity();
    return (double t) {
      final dy = emergeDy * (1.0 - t);
      return Matrix4.translationValues(0, dy, 0);
    };
  }

  /// A-010: Cube rotation transition.
  /// [direction] +1 for clockwise, -1 for counter-clockwise.
  static Matrix4 Function(double t) cubeRotateTransition({
    int direction = 1,
    bool reducedMotion = false,
  }) {
    if (reducedMotion) return (_) => Matrix4.identity();
    return (double t) {
      final angle = direction * (math.pi / 2) * t;
      return Matrix4.identity()..rotateY(angle);
    };
  }

  /// A-011: Cube breathe idle oscillation.
  static Matrix4 Function(double t) cubeBreathe({bool reducedMotion = false}) {
    if (reducedMotion) return (_) => Matrix4.identity();
    return (double t) {
      final angle = math.sin(t * 2 * math.pi) * 1.5 * math.pi / 180.0;
      return Matrix4.identity()..rotateY(angle);
    };
  }
}
