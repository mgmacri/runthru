import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:speedy_boy/design/tokens.dart';

/// CustomPainter rendering the interior of a 3D box you look into.
/// Uses a "magic window" perspective — the back wall shifts with the
/// parallax offset so the viewer feels they can look around inside.
class CubeViewportPainter extends CustomPainter {
  CubeViewportPainter({
    required this.parallaxOffset,
    required this.breatheAngle,
    super.repaint,
  });

  final Offset parallaxOffset;
  final double breatheAngle;

  /// How far inset the back wall is from each edge (fraction of dimension).
  static const double _insetFraction = 0.18;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final insetX = w * _insetFraction;
    final insetY = h * _insetFraction;

    // Magic window: back wall shifts with parallax so you can
    // "look around corners" — the window is fixed, the room behind moves.
    final px = parallaxOffset.dx;
    final py = parallaxOffset.dy;

    final bLeft = insetX + px;
    final bRight = w - insetX + px;
    final bTop = insetY + py;
    final bBottom = h - insetY + py;

    const fLeft = 0.0;
    final fRight = w;
    const fTop = 0.0;
    final fBottom = h;

    canvas.save();

    if (breatheAngle != 0.0) {
      canvas.translate(w / 2, h / 2);
      canvas.skew(breatheAngle * 0.5, 0);
      canvas.translate(-w / 2, -h / 2);
    }

    // ── Back wall ──
    final backRect = Rect.fromLTRB(bLeft, bTop, bRight, bBottom);
    canvas.drawRect(backRect, Paint()..color = SpeedyBoyTokens.cubeBackWall);
    // Subtle centre glow
    canvas.drawRect(
      backRect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset((bLeft + bRight) / 2, (bTop + bBottom) / 2),
          (bRight - bLeft) * 0.6,
          [
            SpeedyBoyTokens.cubeDirectional.withAlpha(24),
            const Color(0x00000000),
          ],
        ),
    );

    // ── Left wall ──
    _drawWall(
      canvas,
      [
        const Offset(fLeft, fTop),
        Offset(bLeft, bTop),
        Offset(bLeft, bBottom),
        Offset(fLeft, fBottom),
      ],
      SpeedyBoyTokens.cubeLeftWall,
      ui.Gradient.linear(
        const Offset(fLeft, 0),
        Offset(bLeft, 0),
        [const Color(0x00000000), const Color(0x0A000000)],
      ),
    );

    // ── Right wall ──
    _drawWall(
      canvas,
      [
        Offset(fRight, fTop),
        Offset(bRight, bTop),
        Offset(bRight, bBottom),
        Offset(fRight, fBottom),
      ],
      SpeedyBoyTokens.cubeRightWall,
      ui.Gradient.linear(
        Offset(fRight, 0),
        Offset(bRight, 0),
        [const Color(0x00000000), const Color(0x0C000000)],
      ),
    );

    // ── Top wall ──
    _drawWall(
      canvas,
      [
        const Offset(fLeft, fTop),
        Offset(bLeft, bTop),
        Offset(bRight, bTop),
        Offset(fRight, fTop),
      ],
      SpeedyBoyTokens.cubeTopWall,
      ui.Gradient.linear(
        const Offset(0, fTop),
        Offset(0, bTop),
        [const Color(0x00000000), const Color(0x08000000)],
      ),
    );

    // ── Bottom wall ──
    _drawWall(
      canvas,
      [
        Offset(fLeft, fBottom),
        Offset(bLeft, bBottom),
        Offset(bRight, bBottom),
        Offset(fRight, fBottom),
      ],
      SpeedyBoyTokens.cubeBottomWall,
      ui.Gradient.linear(
        Offset(0, fBottom),
        Offset(0, bBottom),
        [const Color(0x00000000), const Color(0x0E000000)],
      ),
    );

    // ── Edge highlight lines (subtle neumorphic crease) ──
    final edgePaint = Paint()
      ..color = SpeedyBoyTokens.cubeNeuDark.withAlpha(40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(backRect, edgePaint);
    canvas.drawLine(const Offset(fLeft, fTop), Offset(bLeft, bTop), edgePaint);
    canvas.drawLine(Offset(fRight, fTop), Offset(bRight, bTop), edgePaint);
    canvas.drawLine(Offset(fLeft, fBottom), Offset(bLeft, bBottom), edgePaint);
    canvas.drawLine(
        Offset(fRight, fBottom), Offset(bRight, bBottom), edgePaint);

    // ── Neumorphic rim — light highlight top-left, dark shadow bottom-right ──
    final neuDarkRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..color = SpeedyBoyTokens.cubeNeuDark.withAlpha(35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawLine(Offset(0, h), Offset(w, h), neuDarkRim);
    canvas.drawLine(Offset(w, 0), Offset(w, h), neuDarkRim);

    final neuLightRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..color = SpeedyBoyTokens.cubeNeuLight.withAlpha(50)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawLine(Offset.zero, Offset(w, 0), neuLightRim);
    canvas.drawLine(Offset.zero, Offset(0, h), neuLightRim);

    canvas.restore();
  }

  void _drawWall(
    Canvas canvas,
    List<Offset> corners,
    Color baseColor,
    ui.Gradient gradient,
  ) {
    final path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();
    canvas.drawPath(path, Paint()..color = baseColor);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      const Rect.fromLTRB(-100, -100, 5000, 5000),
      Paint()..shader = gradient,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(CubeViewportPainter oldDelegate) {
    return parallaxOffset != oldDelegate.parallaxOffset ||
        breatheAngle != oldDelegate.breatheAngle;
  }
}
