import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';

/// Stylized "Breathing Room" pause overlay — warm radial fog that
/// subtly pulses in sync with the cube breathe rhythm, with minimal
/// marble-vein pause bars at center.
class PauseFog3D extends StatefulWidget {
  const PauseFog3D({super.key, required this.isPaused, required this.wpm});

  final bool isPaused;
  final int wpm;

  @override
  State<PauseFog3D> createState() => _PauseFog3DState();
}

class _PauseFog3DState extends State<PauseFog3D> with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final CurvedAnimation _fade;
  late final AnimationController _breatheController;

  // P7 Grade D — tunable fog opacity range for breathing effect
  static const double _fogOpacityBase = 0.24;
  static const double _fogOpacityDelta = 0.06;

  @override
  void initState() {
    super.initState();

    // Fade in/out (A-006 / A-007 timing)
    _fadeController = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.pauseFogDuration,
      reverseDuration: SpeedyBoyAnimations.resumeClearDuration,
    );
    _fade = CurvedAnimation(
      parent: _fadeController,
      curve: SpeedyBoyAnimations.pauseFogCurve,
      reverseCurve: SpeedyBoyAnimations.resumeClearCurve,
    );

    // Breathing pulse (A-011 cube breathe rhythm)
    _breatheController = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.cubeBreatheDuration,
    );

    if (widget.isPaused) {
      _fadeController.value = 1.0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !isReducedMotion(context)) {
          _breatheController.repeat(reverse: true);
        }
      });
    }
  }

  @override
  void didUpdateWidget(PauseFog3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused != oldWidget.isPaused) {
      final reducedMotion = isReducedMotion(context);
      if (widget.isPaused) {
        if (reducedMotion) {
          _fadeController.value = 1.0;
        } else {
          _fadeController.forward();
          _breatheController.repeat(reverse: true);
        }
      } else {
        if (reducedMotion) {
          _fadeController.value = 0.0;
        } else {
          _fadeController.reverse();
        }
        _breatheController
          ..stop()
          ..value = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _fadeController.dispose();
    _breatheController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _fade,
      builder: (context, _) {
        if (_fade.value == 0) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: _breatheController,
          builder: (context, _) {
            final breatheT = _breatheController.value;
            final breatheOffset =
                math.sin(breatheT * math.pi) * _fogOpacityDelta;
            final fogOpacity = (_fogOpacityBase + breatheOffset) * _fade.value;

            return CustomPaint(
              painter: _BreathingFogPainter(
                fogColor: SpeedyBoyTokens.roomFog,
                fogOpacity: fogOpacity,
                barColor: SpeedyBoyTokens.marbleVeinPrimary,
                glowColor: SpeedyBoyTokens.marbleVeinSecondary,
                barOpacity: _fade.value * 0.6,
              ),
              size: Size.infinite,
            );
          },
        );
      },
    );
  }
}

class _BreathingFogPainter extends CustomPainter {
  _BreathingFogPainter({
    required this.fogColor,
    required this.fogOpacity,
    required this.barColor,
    required this.glowColor,
    required this.barOpacity,
  });

  final Color fogColor;
  final double fogOpacity;
  final Color barColor;
  final Color glowColor;
  final double barOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.sqrt(center.dx * center.dx + center.dy * center.dy);

    // ── Radial gradient fog — clearer center, denser edges ──
    final fogPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          fogColor.withValues(alpha: fogOpacity * 0.35),
          fogColor.withValues(alpha: fogOpacity * 0.7),
          fogColor.withValues(alpha: fogOpacity),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));
    canvas.drawRect(Offset.zero & size, fogPaint);

    // ── Pause bars — rounded rects with glow ──
    final barWidth = size.width * 0.035;
    final barHeight = size.height * 0.09;
    final barGap = barWidth * 1.6;
    final barRadius = Radius.circular(barWidth * 0.4);

    final leftCenter = Offset(center.dx - barGap / 2 - barWidth / 2, center.dy);
    final rightCenter = Offset(
      center.dx + barGap / 2 + barWidth / 2,
      center.dy,
    );

    // Glow halo behind bars
    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: barOpacity * 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    for (final c in [leftCenter, rightCenter]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: c,
            width: barWidth + 8,
            height: barHeight + 8,
          ),
          Radius.circular(barWidth * 0.6),
        ),
        glowPaint,
      );
    }

    // Solid bars
    final barPaint = Paint()
      ..color = barColor.withValues(alpha: barOpacity * 1.2);
    for (final c in [leftCenter, rightCenter]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: barWidth, height: barHeight),
          barRadius,
        ),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_BreathingFogPainter oldDelegate) =>
      fogOpacity != oldDelegate.fogOpacity ||
      barOpacity != oldDelegate.barOpacity;
}
