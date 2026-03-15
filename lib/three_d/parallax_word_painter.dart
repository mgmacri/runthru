import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:speedy_boy/core/orp.dart';
import 'package:speedy_boy/design/typography.dart';
import 'package:speedy_boy/three_d/glyph_measurer.dart';
import 'package:speedy_boy/three_d/off_axis_projection.dart';
import 'package:speedy_boy/three_d/text_painter_pool.dart';

/// Renders the current word with shadow and glow on the marble box back wall.
///
/// Each glyph is projected at the text depth plane and painted once
/// (no extrusion layers). Shadow and warm glow passes run first.
class ParallaxWordPainter extends CustomPainter {
  ParallaxWordPainter({
    required this.word,
    required this.fontSize,
    required this.headX,
    required this.headY,
    required this.config,
    required this.painterPool,
    required this.animationValue,
    this.anchorColor,
    this.fontFamily = 'BricolageGrotesque',
    super.repaint,
  })  : _anchorIndex = orpIndexInOriginal(word),
        _glyphs = word.isNotEmpty
            ? GlyphMeasurer.instance.measureWord(
                word,
                fontSize,
                anchorIndex: orpIndexInOriginal(word),
              )
            : const [];

  final String word;
  final double fontSize;
  final double headX;
  final double headY;
  final RoomConfig config;
  final TextPainterPool painterPool;
  final double animationValue;
  final Color? anchorColor;
  final String fontFamily;

  final int _anchorIndex;
  final List<GlyphPosition> _glyphs;

  // ── Layout constants ─────────────────────────────────────────────────
  // Small gap between adjacent glyphs.
  static const double _glyphGap = 0.02;
  // Depth of bounding box (for shadow geometry only).
  static const double _glyphDepth = 2.0;

  // ── Pre-allocated paints ─────────────────────────────────────────────
  static final Paint _shadowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 44);
  static final Paint _glowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
  static final Paint _vignettePaint = Paint();
  static final Path _facePath = Path();

  // ── Colours (marble aesthetic) ───────────────────────────────────────
  // Text: rich dark charcoal on marble
  static const Color _textColor = Color(0xFF2E272A);

  // Shadow & glow (warm, subtle on marble)
  static const Color _shadowColor = Color(0x5C685040);
  static const Color _glowColor = Color(0x30F0DCC0);

  // Vignette (warm, very soft)
  static const List<Color> _vignetteColors = [
    Color(0x00000000),
    Color(0x18A09080),
  ];
  static const List<double> _vignetteStops = [0.55, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    if (word.isEmpty || _glyphs.isEmpty) return;

    final textZ = config.textZ;
    final totalGlyphWidth = _glyphs.last.xOffset + _glyphs.last.width;
    final textHeight = fontSize * 1.2;

    // ORP-anchored centering
    final anchorIdx = (_anchorIndex - 1).clamp(0, _glyphs.length - 1);
    final anchorGlyph = _glyphs[anchorIdx];
    final anchorCenterLocal = anchorGlyph.xOffset + anchorGlyph.width / 2;
    final entranceScale = 0.95 + 0.05 * animationValue;
    final anchorOffsetRoomUnits =
        ((anchorCenterLocal - totalGlyphWidth / 2) / config.unitScale) *
            entranceScale;

    final headNormX = (headX / 16.0).clamp(-1.0, 1.0);
    final headNormY = (headY / 16.0).clamp(-1.0, 1.0);

    // ── Pass 2: Warm centered glow behind word ──────────────────
    _glowPaint.color = _glowColor;

    for (var i = 0; i < _glyphs.length; i++) {
      final box = _glyphBox(i, textZ, totalGlyphWidth, textHeight,
          anchorOffsetRoomUnits, entranceScale);
      if (box == null) continue;
      final corners = _projectFront(box, size);
      if (corners == null) continue;

      _facePath
        ..reset()
        ..moveTo(corners[0].dx - 3, corners[0].dy - 3)
        ..lineTo(corners[1].dx + 3, corners[1].dy - 3)
        ..lineTo(corners[2].dx + 3, corners[2].dy + 3)
        ..lineTo(corners[3].dx - 3, corners[3].dy + 3)
        ..close();
      canvas.drawPath(_facePath, _glowPaint);
    }

    // ── Pass 3: Single-layer text (no extrusion) ─────────────────────
    final halfH = ((textHeight / config.unitScale) / 2.0) * entranceScale;
    final wordHalfW = (totalGlyphWidth / config.unitScale) / 2.0;
    final cx = -anchorOffsetRoomUnits;

    for (var i = 0; i < _glyphs.length; i++) {
      final glyph = _glyphs[i];
      final isAnchor = i == anchorIdx;

      final leftRoom = cx +
          ((glyph.xOffset / config.unitScale) - wordHalfW) * entranceScale +
          _glyphGap;
      final rightRoom = cx +
          (((glyph.xOffset + glyph.width) / config.unitScale) - wordHalfW) *
              entranceScale -
          _glyphGap;
      final midX = (leftRoom + rightRoom) / 2;

      final pMid = _p(Point3D(midX, 0, textZ), size);
      final pLeft = _p(Point3D(leftRoom, halfH, textZ), size);
      final pRight = _p(Point3D(rightRoom, halfH, textZ), size);
      if (pMid == null || pLeft == null || pRight == null) continue;

      final projW = (pRight.dx - pLeft.dx).abs();
      final textScale = glyph.width > 0 ? projW / glyph.width : 1.0;
      final efs = fontSize * textScale;

      final color = isAnchor ? (anchorColor ?? _textColor) : _textColor;
      final style = isAnchor
          ? SpeedyBoyTypography.readingAnchor(efs,
              color: color, fontFamily: fontFamily)
          : SpeedyBoyTypography.readingWord(efs,
              color: color, fontFamily: fontFamily);

      final poolIndex = i % TextPainterPool.maxSize;
      painterPool.configure(poolIndex, glyph.character, style);
      final tp = painterPool[poolIndex];

      tp.paint(
        canvas,
        Offset(pMid.dx - tp.width / 2, pMid.dy - tp.height / 2),
      );
    }

    // ── Vignette (drawn last) — centered ──────────────────────────
    _vignettePaint.shader = ui.Gradient.radial(
      Offset(size.width / 2, size.height / 2),
      size.longestSide * 0.65,
      _vignetteColors,
      _vignetteStops,
    );
    canvas.drawRect(Offset.zero & size, _vignettePaint);
  }

  // ── Per-glyph bounding box (front face only — used for shadow/glow) ──

  _GlyphBox? _glyphBox(
    int idx,
    double textZ,
    double totalGlyphWidth,
    double textHeight,
    double anchorOffsetRoomUnits,
    double entranceScale,
  ) {
    final glyph = _glyphs[idx];
    final wordHalfW = (totalGlyphWidth / config.unitScale) / 2.0;
    final leftRoom =
        ((glyph.xOffset / config.unitScale) - wordHalfW) * entranceScale;
    final rightRoom =
        (((glyph.xOffset + glyph.width) / config.unitScale) - wordHalfW) *
            entranceScale;
    final cx = -anchorOffsetRoomUnits;
    final left = cx + leftRoom + _glyphGap;
    final right = cx + rightRoom - _glyphGap;
    final halfH = ((textHeight / config.unitScale) / 2.0) * entranceScale;
    const halfD = _glyphDepth / 2.0;

    return _GlyphBox(
      ftl: Point3D(left, halfH, textZ - halfD),
      ftr: Point3D(right, halfH, textZ - halfD),
      fbr: Point3D(right, -halfH, textZ - halfD),
      fbl: Point3D(left, -halfH, textZ - halfD),
    );
  }

  List<Offset>? _projectFront(_GlyphBox box, Size size) {
    final a = _p(box.ftl, size);
    final b = _p(box.ftr, size);
    final c = _p(box.fbr, size);
    final d = _p(box.fbl, size);
    if (a == null || b == null || c == null || d == null) return null;
    return [a, b, c, d];
  }

  Offset? _p(Point3D pt, Size size) => projectOffAxis(
        pt,
        headX: headX,
        headY: headY,
        config: config,
        screenWidth: size.width,
        screenHeight: size.height,
      );

  @override
  bool shouldRepaint(ParallaxWordPainter oldDelegate) =>
      word != oldDelegate.word ||
      headX != oldDelegate.headX ||
      headY != oldDelegate.headY ||
      animationValue != oldDelegate.animationValue ||
      fontFamily != oldDelegate.fontFamily;
}

/// Front four corners of a glyph's 3D bounding box (used for shadow/glow).
class _GlyphBox {
  const _GlyphBox({
    required this.ftl,
    required this.ftr,
    required this.fbr,
    required this.fbl,
  });
  final Point3D ftl, ftr, fbr, fbl;
}
