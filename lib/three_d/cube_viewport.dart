import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/three_d/cube_viewport_painter.dart';

/// The 3D cube viewport widget — a neumorphic inset box with visible
/// perspective depth. The outer shell surface frames the dark inner cube.
class CubeViewport extends StatelessWidget {
  const CubeViewport({
    super.key,
    this.parallaxOffset = Offset.zero,
    this.breatheAngle = 0.0,
    this.child,
  });

  final Offset parallaxOffset;
  final double breatheAngle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Outer shell surface with neumorphic inset shadow
      decoration: const BoxDecoration(
        color: SpeedyBoyTokens.shellBase,
        boxShadow: [
          // Outer neumorphic raised effect
          BoxShadow(
            color: SpeedyBoyTokens.shellLightShadow,
            offset: Offset(-6, -6),
            blurRadius: 12,
          ),
          BoxShadow(
            color: SpeedyBoyTokens.shellDarkShadow,
            offset: Offset(6, 6),
            blurRadius: 12,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Container(
        // Inner inset well — the "hole" you look into
        decoration: BoxDecoration(
          color: SpeedyBoyTokens.stageBase,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            // Inset shadow: dark on top-left, light on bottom-right
            BoxShadow(
              color: SpeedyBoyTokens.shellDarkShadow,
              offset: Offset(-4, -4),
              blurRadius: 8,
            ),
            BoxShadow(
              color: SpeedyBoyTokens.shellLightShadow,
              offset: Offset(4, 4),
              blurRadius: 8,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: RepaintBoundary(
          child: Stack(
            children: [
              // 3D interior walls
              Positioned.fill(
                child: CustomPaint(
                  painter: CubeViewportPainter(
                    parallaxOffset: parallaxOffset,
                    breatheAngle: breatheAngle,
                  ),
                ),
              ),
              // Content (word, progress, fog, dial)
              if (child != null) Positioned.fill(child: child!),
            ],
          ),
        ),
      ),
    );
  }
}
