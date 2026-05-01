import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:runthru/three_d/off_axis_projection.dart';

/// CustomPainter rendering a static 3D marble box interior using off-axis
/// projection.
///
/// Draw order (back to front):
///   1. Background fill
///   2. Back wall surface with marble veining
///   3. Side wall surfaces (floor, ceiling, left, right)
///   4. Subtle etched grid lines on walls
///   5. Marble vein overlay details
///   6. Ambient light pooling (soft radial glow)
///   7. Vignette
class ParallaxRoomPainter extends CustomPainter {
  ParallaxRoomPainter({
    required this.headX,
    required this.headY,
    required this.config,
    this.buildProgress = 1.0,
    this.focusDim = 0.0,
    super.repaint,
  });

  final double headX;
  final double headY;
  final RoomConfig config;
  final double buildProgress;
  final double focusDim;

  // ── Marble palette ────────────────────────────────────────────────────
  static const Color _bg = Color(0xFFF2EDE7);
  static const Color _wallBack = Color(0xFFEDE8E2);
  static const Color _wallLeft = Color(0xFFE6DFD7);
  static const Color _wallRight = Color(0xFFE6DFD7);
  static const Color _wallTop = Color(0xFFE5DED6);
  static const Color _wallBottom = Color(0xFFE5DED6);
  static const Color _veinColor = Color(0xFFB8B0A8);
  static const Color _veinSoft = Color(0xFFD0C4B8);
  static const Color _glowColor = Color(0x24F0E0D0);
  static const Color _edgeShadow = Color(0xFFC8BEB0);
  static const Color _gridNear = Color(0xFFD0C8BE);
  static const Color _gridFar = Color(0xFFE8E2DC);
  static const Color _clear = Color(0x00000000);

  static const List<Color> _vignetteColors = [
    Color(0x00000000),
    Color(0x20887060),
  ];
  static const List<double> _vignetteStops = [0.50, 1.0];

  // ── Pre-allocated paints ──────────────────────────────────────────────
  static final Paint _bgPaint = Paint();
  static final Paint _wallPaint = Paint();
  static final Paint _glowPaint = Paint();
  static final Paint _vignettePaint = Paint();
  static final Paint _veinPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final Paint _gridPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final Path _path = Path();

  // ── Grid color LUT ────────────────────────────────────────────────────
  static List<Color>? _colorLut;
  static double _colorLutDepth = -1;

  List<Color> _lut(double depth) {
    if (_colorLut == null || _colorLutDepth != depth) {
      _colorLut = List<Color>.generate(33, (i) {
        return Color.lerp(_gridNear, _gridFar, i / 32.0)!;
      });
      _colorLutDepth = depth;
    }
    return _colorLut!;
  }

  Color _gridColor(double z, double depth, List<Color> lut) {
    final t = depth > 0 ? (z / depth).clamp(0.0, 1.0) : 0.0;
    return lut[(t * 32).round().clamp(0, 32)];
  }

  // ── Main paint ────────────────────────────────────────────────────────
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background fill
    _bgPaint.color = _bg;
    canvas.drawRect(Offset.zero & size, _bgPaint);

    final wallA = (1.0 - focusDim * 0.15).clamp(0.0, 1.0);
    final depth = config.roomDepth;
    final animD = depth * buildProgress.clamp(0.01, 1.0);
    final wg = config.wRoom;
    final hg = config.hRoom;
    final wp = config.wRoomPadded;
    final hp = config.hRoomPadded;
    final lut = _lut(depth);

    // 2. Back wall with subtle gradient (light pooling at center)
    _fillWallPts(canvas, size, [
      Point3D(-wp, hp, depth),
      Point3D(wp, hp, depth),
      Point3D(wp, -hp, depth),
      Point3D(-wp, -hp, depth),
    ], _wallBack.withAlpha((255 * wallA).round()));

    // Warm center glow on back wall
    final backLightCenter = _proj(Point3D(0, 0, depth), size);
    if (backLightCenter != null) {
      _glowPaint.shader = ui.Gradient.radial(
        backLightCenter,
        size.shortestSide * 0.7,
        [const Color(0x22FFFFFF), _clear],
        [0.0, 1.0],
      );
      canvas.drawRect(Offset.zero & size, _glowPaint);
    }

    // 3. Back wall marble veins
    _drawMarbleVeins(canvas, size, depth, wg, hg, wallA);

    // 4. Side walls
    final fTL = _proj(Point3D(-wp, hp, 0), size);
    final fTR = _proj(Point3D(wp, hp, 0), size);
    final fBR = _proj(Point3D(wp, -hp, 0), size);
    final fBL = _proj(Point3D(-wp, -hp, 0), size);
    final bTL = _proj(Point3D(-wp, hp, depth), size);
    final bTR = _proj(Point3D(wp, hp, depth), size);
    final bBR = _proj(Point3D(wp, -hp, depth), size);
    final bBL = _proj(Point3D(-wp, -hp, depth), size);

    // Floor
    if (fBL != null && fBR != null && bBR != null && bBL != null) {
      _fillQuadGradient(
        canvas,
        [fBL, fBR, bBR, bBL],
        _wallBottom,
        wallA,
        Offset(0, size.height),
        Offset(0, size.height * 0.5),
      );
    }
    // Ceiling
    if (fTL != null && fTR != null && bTR != null && bTL != null) {
      _fillQuadGradient(
        canvas,
        [fTL, fTR, bTR, bTL],
        _wallTop,
        wallA,
        Offset.zero,
        Offset(0, size.height * 0.5),
      );
    }
    // Left wall
    if (fTL != null && bTL != null && bBL != null && fBL != null) {
      _fillQuadGradient(
        canvas,
        [fTL, bTL, bBL, fBL],
        _wallLeft,
        wallA,
        Offset.zero,
        Offset(size.width * 0.5, 0),
      );
    }
    // Right wall
    if (fTR != null && bTR != null && bBR != null && fBR != null) {
      _fillQuadGradient(
        canvas,
        [fTR, bTR, bBR, fBR],
        _wallRight,
        wallA,
        Offset(size.width, 0),
        Offset(size.width * 0.5, 0),
      );
    }

    // 5. Subtle etched grid lines (very faint, like marble tile seams)
    _drawSubtleGrid(canvas, size, wg, hg, animD, depth, lut, wallA);

    // 6. Edge creases — neumorphic marble edges
    _drawMarbleEdges(canvas, size, bTL, bTR, bBR, bBL, fTL, fTR, fBR, fBL);

    // 7. Ambient light pooling — warm glow from center
    _drawAmbientGlow(canvas, size);

    // 8. Vignette (warm, soft)
    _drawVignette(canvas, size);
  }

  // ── Marble veins on back wall ─────────────────────────────────────────
  void _drawMarbleVeins(
    Canvas canvas,
    Size size,
    double depth,
    double w,
    double h,
    double wallA,
  ) {
    // Draw organic diagonal veining strokes on back wall
    final rng = math.Random(42); // deterministic for consistency
    final veinAlpha = (60 * wallA).round().clamp(0, 255);

    for (var i = 0; i < 8; i++) {
      final startX = (rng.nextDouble() * 2 - 1) * w * 0.9;
      final startY = (rng.nextDouble() * 2 - 1) * h * 0.9;
      final endX = startX + (rng.nextDouble() * 2 - 1) * w * 0.6;
      final endY = startY + (rng.nextDouble() * 0.4 + 0.1) * h;

      final p1 = _proj(Point3D(startX, startY, depth), size);
      final p2 = _proj(Point3D(endX, endY, depth), size);
      if (p1 == null || p2 == null) continue;

      final color = i.isEven ? _veinColor : _veinSoft;
      _veinPaint
        ..color = Color.fromARGB(
          veinAlpha,
          (color.r * 255.0).round().clamp(0, 255),
          (color.g * 255.0).round().clamp(0, 255),
          (color.b * 255.0).round().clamp(0, 255),
        )
        ..strokeWidth = (i.isEven ? 1.5 : 2.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, i.isEven ? 1.0 : 2.0);

      // Draw slightly curved veins using quadratic bezier
      final midX = (p1.dx + p2.dx) / 2 + (rng.nextDouble() - 0.5) * 30;
      final midY = (p1.dy + p2.dy) / 2 + (rng.nextDouble() - 0.5) * 20;

      _path
        ..reset()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(midX, midY, p2.dx, p2.dy);
      canvas.drawPath(_path, _veinPaint);
    }

    // A few fainter background veins for depth
    for (var i = 0; i < 5; i++) {
      final startX = (rng.nextDouble() * 2 - 1) * w * 0.95;
      final startY = (rng.nextDouble() * 2 - 1) * h * 0.95;
      final endX = startX + (rng.nextDouble() - 0.3) * w * 0.8;
      final endY = startY - (rng.nextDouble() * 0.3 + 0.05) * h;

      final p1 = _proj(Point3D(startX, startY, depth), size);
      final p2 = _proj(Point3D(endX, endY, depth), size);
      if (p1 == null || p2 == null) continue;

      _veinPaint
        ..color = Color.fromARGB(
          (25 * wallA).round().clamp(0, 255),
          (_veinSoft.r * 255.0).round().clamp(0, 255),
          (_veinSoft.g * 255.0).round().clamp(0, 255),
          (_veinSoft.b * 255.0).round().clamp(0, 255),
        )
        ..strokeWidth = 3.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

      final midX = (p1.dx + p2.dx) / 2 + (rng.nextDouble() - 0.5) * 50;
      final midY = (p1.dy + p2.dy) / 2 + (rng.nextDouble() - 0.5) * 30;

      _path
        ..reset()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(midX, midY, p2.dx, p2.dy);
      canvas.drawPath(_path, _veinPaint);
    }
  }

  // ── Subtle etched grid (marble tile seams) ────────────────────────────
  void _drawSubtleGrid(
    Canvas canvas,
    Size size,
    double w,
    double h,
    double animD,
    double totalDepth,
    List<Color> lut,
    double wallA,
  ) {
    // Transversal rings (far-to-near)
    final zValues = <double>[];
    var z = 0.0;
    while (z <= animD + 0.01) {
      zValues.add(z);
      z += config.gridSpacing;
    }

    for (var i = zValues.length - 1; i >= 0; i--) {
      final zv = zValues[i];
      final color = _gridColor(zv, totalDepth, lut);
      final alpha = ((color.a * 255.0).round().clamp(0, 255) * 0.35 * wallA)
          .round()
          .clamp(0, 255);

      _gridPaint
        ..color = Color.fromARGB(
          alpha,
          (color.r * 255.0).round().clamp(0, 255),
          (color.g * 255.0).round().clamp(0, 255),
          (color.b * 255.0).round().clamp(0, 255),
        )
        ..strokeWidth = 0.5;

      final tl = _proj(Point3D(-w, h, zv), size);
      final tr = _proj(Point3D(w, h, zv), size);
      final br = _proj(Point3D(w, -h, zv), size);
      final bl = _proj(Point3D(-w, -h, zv), size);

      if (tl != null && tr != null) canvas.drawLine(tl, tr, _gridPaint);
      if (bl != null && br != null) canvas.drawLine(bl, br, _gridPaint);
      if (tl != null && bl != null) canvas.drawLine(tl, bl, _gridPaint);
      if (tr != null && br != null) canvas.drawLine(tr, br, _gridPaint);
    }

    // Longitudinal lines
    final nearColor = _gridColor(0, totalDepth, lut);
    final nearAlpha =
        ((nearColor.a * 255.0).round().clamp(0, 255) * 0.3 * wallA)
            .round()
            .clamp(0, 255);
    _gridPaint
      ..color = Color.fromARGB(
        nearAlpha,
        (nearColor.r * 255.0).round().clamp(0, 255),
        (nearColor.g * 255.0).round().clamp(0, 255),
        (nearColor.b * 255.0).round().clamp(0, 255),
      )
      ..strokeWidth = 0.5;

    var x = -w;
    while (x <= w + 0.01) {
      void line(Point3D a, Point3D b) {
        final pa = _proj(a, size);
        final pb = _proj(b, size);
        if (pa != null && pb != null) canvas.drawLine(pa, pb, _gridPaint);
      }

      line(Point3D(x, -h, 0), Point3D(x, -h, animD)); // floor
      line(Point3D(x, h, 0), Point3D(x, h, animD)); // ceiling
      x += config.gridSpacing;
    }
    var y = -h;
    while (y <= h + 0.01) {
      void line(Point3D a, Point3D b) {
        final pa = _proj(a, size);
        final pb = _proj(b, size);
        if (pa != null && pb != null) canvas.drawLine(pa, pb, _gridPaint);
      }

      line(Point3D(-w, y, 0), Point3D(-w, y, animD)); // left
      line(Point3D(w, y, 0), Point3D(w, y, animD)); // right
      y += config.gridSpacing;
    }
  }

  // ── Marble edge highlights ────────────────────────────────────────────
  void _drawMarbleEdges(
    Canvas canvas,
    Size size,
    Offset? bTL,
    Offset? bTR,
    Offset? bBR,
    Offset? bBL,
    Offset? fTL,
    Offset? fTR,
    Offset? fBR,
    Offset? fBL,
  ) {
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = _edgeShadow.withAlpha(80)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    // Back wall rect edges
    if (bTL != null && bTR != null) canvas.drawLine(bTL, bTR, edgePaint);
    if (bBL != null && bBR != null) canvas.drawLine(bBL, bBR, edgePaint);
    if (bTL != null && bBL != null) canvas.drawLine(bTL, bBL, edgePaint);
    if (bTR != null && bBR != null) canvas.drawLine(bTR, bBR, edgePaint);

    // Corner edges (connecting near to far)
    if (fTL != null && bTL != null) canvas.drawLine(fTL, bTL, edgePaint);
    if (fTR != null && bTR != null) canvas.drawLine(fTR, bTR, edgePaint);
    if (fBL != null && bBL != null) canvas.drawLine(fBL, bBL, edgePaint);
    if (fBR != null && bBR != null) canvas.drawLine(fBR, bBR, edgePaint);
  }

  // ── Ambient glow ──────────────────────────────────────────────────────
  void _drawAmbientGlow(Canvas canvas, Size size) {
    _glowPaint.shader = ui.Gradient.radial(
      Offset(size.width * 0.5, size.height * 0.5),
      size.longestSide * 0.6,
      [_glowColor, _clear],
      [0.0, 0.7],
    );
    canvas.drawRect(Offset.zero & size, _glowPaint);
  }

  // ── Wall helpers ──────────────────────────────────────────────────────

  void _fillWallPts(
    Canvas canvas,
    Size size,
    List<Point3D> pts3d,
    Color color,
  ) {
    final a = _proj(pts3d[0], size);
    final b = _proj(pts3d[1], size);
    final c = _proj(pts3d[2], size);
    final d = _proj(pts3d[3], size);
    if (a == null || b == null || c == null || d == null) return;
    _fillQuad(canvas, [a, b, c, d], color);
  }

  void _fillQuad(Canvas canvas, List<Offset> corners, Color color) {
    _wallPaint.color = color;
    _path
      ..reset()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();
    canvas.drawPath(_path, _wallPaint);
  }

  void _fillQuadGradient(
    Canvas canvas,
    List<Offset> corners,
    Color baseColor,
    double alpha,
    Offset gradStart,
    Offset gradEnd,
  ) {
    _path
      ..reset()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    // Base fill
    _wallPaint.color = baseColor.withAlpha((255 * alpha).round());
    canvas.drawPath(_path, _wallPaint);

    // Subtle gradient overlay for depth — stronger for dramatic lighting
    canvas.save();
    canvas.clipPath(_path);
    _wallPaint.shader = ui.Gradient.linear(gradStart, gradEnd, [
      const Color(0x00000000),
      const Color(0x10000000),
    ]);
    canvas.drawRect(Offset.zero & const Size(5000, 5000), _wallPaint);
    _wallPaint.shader = null;
    canvas.restore();
  }

  // ── Vignette ──────────────────────────────────────────────────────────

  void _drawVignette(Canvas canvas, Size size) {
    _vignettePaint.shader = ui.Gradient.radial(
      Offset(size.width * 0.5, size.height * 0.5),
      size.longestSide * 0.65,
      _vignetteColors,
      _vignetteStops,
    );
    canvas.drawRect(Offset.zero & size, _vignettePaint);
  }

  // ── Projection helper ─────────────────────────────────────────────────

  Offset? _proj(Point3D pt, Size size) => projectOffAxis(
    pt,
    headX: headX,
    headY: headY,
    config: config,
    screenWidth: size.width,
    screenHeight: size.height,
  );

  @override
  bool shouldRepaint(ParallaxRoomPainter oldDelegate) =>
      headX != oldDelegate.headX ||
      headY != oldDelegate.headY ||
      buildProgress != oldDelegate.buildProgress ||
      focusDim != oldDelegate.focusDim ||
      config != oldDelegate.config;
}
