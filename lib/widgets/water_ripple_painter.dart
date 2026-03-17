import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';

/// CustomPainter that draws 3D neumorphic water-ripple rings.
///
/// Each ring is a slightly squashed ellipse with light/dark shadow arcs
/// to create a raised-surface illusion. Three rings are staggered in time,
/// driven by a single animation value (0–1 repeating).
///
/// Usage:
/// ```dart
/// CustomPaint(
///   painter: WaterRipplePainter(
///     animationValue: controller.value,
///     surface: SpeedyBoySurface.shell,
///   ),
/// )
/// ```
class WaterRipplePainter extends CustomPainter {
  WaterRipplePainter({
    required this.animationValue,
    this.surface = SpeedyBoySurface.shell,
    this.epicenter,
    super.repaint,
  });

  /// 0.0–1.0, repeating cycle.
  final double animationValue;
  final SpeedyBoySurface surface;
  final Offset? epicenter;

  // Pre-allocated paints for each ring (light + dark arc).
  static final List<Paint> _lightPaints = List.generate(
    SpeedyBoyAnimations.waterRippleRingCount,
    (_) => Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true,
  );
  static final List<Paint> _darkPaints = List.generate(
    SpeedyBoyAnimations.waterRippleRingCount,
    (_) => Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final center = epicenter ?? Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) * 0.45;
    const squash = SpeedyBoyAnimations.waterRippleSquash;

    final Color lightColor;
    final Color darkColor;
    switch (surface) {
      case SpeedyBoySurface.shell:
        lightColor = SpeedyBoyTokens.shellLightShadow;
        darkColor = SpeedyBoyTokens.shellDarkShadow;
      case SpeedyBoySurface.stage:
        lightColor = SpeedyBoyTokens.stageLightShadow;
        darkColor = SpeedyBoyTokens.stageDarkShadow;
    }

    for (var i = 0; i < SpeedyBoyAnimations.waterRippleRingCount; i++) {
      // Phase offset: ring i is delayed by i * (800ms / 2400ms)
      final phaseOffset = i / SpeedyBoyAnimations.waterRippleRingCount;
      var ringProgress = (animationValue - phaseOffset) % 1.0;
      if (ringProgress < 0) ringProgress += 1.0;

      // Apply easeOut to the ring's own progress
      final easedProgress = SpeedyBoyAnimations.waterRippleCurve.transform(
        ringProgress,
      );

      final radius = maxRadius * easedProgress;
      if (radius < 1.0) continue;

      // Stroke width: 3.0 → 0.5
      final strokeWidth = 3.0 - 2.5 * easedProgress;
      // Opacity: 0.6 → 0.0
      final opacity = (0.6 * (1.0 - easedProgress)).clamp(0.0, 1.0);
      // Blur radius grows with ring age
      final blur = 2.0 + 6.0 * easedProgress;

      // Light arc (upper-left emphasis)
      _lightPaints[i]
        ..color = lightColor.withValues(alpha: opacity * 0.4)
        ..strokeWidth = strokeWidth
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

      // Dark arc (lower-right emphasis)
      _darkPaints[i]
        ..color = darkColor.withValues(alpha: opacity * 0.4)
        ..strokeWidth = strokeWidth
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

      final rect = Rect.fromCenter(
        center: center,
        width: radius * 2,
        height: radius * 2 * squash,
      );

      // Light arc: top-left quadrant (-π to -π/2)
      canvas.drawArc(rect, -math.pi, math.pi / 2, false, _lightPaints[i]);
      // Also draw a subtle continuation on upper-right
      canvas.drawArc(rect, -math.pi / 2, math.pi / 4, false, _lightPaints[i]);

      // Dark arc: bottom-right quadrant (0 to π/2)
      canvas.drawArc(rect, 0, math.pi / 2, false, _darkPaints[i]);
      // Subtle continuation on lower-left
      canvas.drawArc(rect, math.pi / 2, math.pi / 4, false, _darkPaints[i]);
    }
  }

  @override
  bool shouldRepaint(WaterRipplePainter oldDelegate) =>
      animationValue != oldDelegate.animationValue ||
      surface != oldDelegate.surface;
}
