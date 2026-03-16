import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:speedy_boy/core/orp.dart';
import 'package:speedy_boy/design/materials.dart';
import 'package:speedy_boy/design/typography.dart';
import 'package:speedy_boy/three_d/glyph_measurer.dart';
import 'package:speedy_boy/three_d/off_axis_projection.dart';
import 'package:speedy_boy/three_d/text_painter_pool.dart';

/// Renders the current word with shadow and glow on the marble box back wall.
///
/// Each glyph is projected at the text depth plane and painted once
/// (no extrusion layers). Shadow and warm glow passes run first.
///
/// A-013 "Word Depth Bounce-In" adds barely perceptible forward Z motion
/// and expanding shadow, driven by [depthBounceValue]. The emphasis is
/// on !!!very subtle!!! — felt, not seen. Per-glyph micro-stagger creates
/// a wave-like settling at sub-conscious level.
class ParallaxWordPainter extends CustomPainter {
  ParallaxWordPainter({
    required this.word,
    required this.fontSize,
    required this.headX,
    required this.headY,
    required this.config,
    required this.painterPool,
    required this.animationValue,
    this.depthBounceValue = 1.0,
    this.reducedMotion = false,
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

  /// A-001 scale breathe value (0→1, 80ms).
  final double animationValue;

  /// A-013 depth bounce value (0→1, 120ms with SubtleBounceIn curve).
  final double depthBounceValue;

  /// Whether reduced motion is requested.
  final bool reducedMotion;
  final Color? anchorColor;
  final String fontFamily;

  final int _anchorIndex;
  final List<GlyphPosition> _glyphs;

  // ── Layout constants ─────────────────────────────────────────────────
  static const double _glyphGap = 0.02;
  static const double _glyphDepth = 2.0;

  // ── Pre-allocated paints ─────────────────────────────────────────────
  static final Paint _glowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
  static final Paint _shadowPaint = Paint();
  static final Paint _vignettePaint = Paint();
  static final Path _facePath = Path();

  // ── Pre-computed MaskFilter LUT for shadow blur animation ────────────
  // 8 entries covering blur range [44, 52]. Selected by nearest index
  // in paint() to avoid allocating MaskFilter objects per frame.
  static final List<MaskFilter> _shadowBlurLut = List.generate(
    8,
    (i) {
      final blur = SpeedyBoyMaterials.wordBounceShadowBlurMin +
          (SpeedyBoyMaterials.wordBounceShadowBlurMax -
                  SpeedyBoyMaterials.wordBounceShadowBlurMin) *
              i /
              7.0;
      return MaskFilter.blur(BlurStyle.normal, blur);
    },
  );

  // ── Colours (marble aesthetic) ───────────────────────────────────────
  static const Color _textColor = Color(0xFF2E272A);
  static const Color _glowColor = Color(0x30F0DCC0);
  static const Color _shadowColor = Color(0x30A09080);
  static const List<Color> _vignetteColors = [
    Color(0x00000000),
    Color(0x18A09080),
  ];
  static const List<double> _vignetteStops = [0.55, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    if (word.isEmpty || _glyphs.isEmpty) return;

    final baseTextZ = config.textZ;
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

    // ── A-013: Depth bounce Z motion ────────────────────────────────
    // Text starts at textZ + deltaZ (behind resting) and settles forward.
    // bounceValue follows SubtleBounceIn — includes 4% overshoot.
    final bounceValue = reducedMotion ? 1.0 : depthBounceValue;

    // ── A-013: Shadow animation ─────────────────────────────────────
    // Shadow blur scales with bounce: tighter when far, larger at rest.
    final shadowBlurNorm = bounceValue.clamp(0.0, 1.0);
    final lutIndex = (shadowBlurNorm * 7).round().clamp(0, 7);
    _shadowPaint.maskFilter = _shadowBlurLut[lutIndex];

    // Shadow opacity: faint → full strength
    final shadowOpacity = SpeedyBoyMaterials.wordBounceShadowOpacityMin +
        (SpeedyBoyMaterials.wordBounceShadowOpacityMax -
                SpeedyBoyMaterials.wordBounceShadowOpacityMin) *
            shadowBlurNorm;
    _shadowPaint.color = _shadowColor.withOpacity(shadowOpacity);

    // Shadow Y offset: shifts downward as text comes forward
    final shadowOffsetY =
        SpeedyBoyMaterials.wordBounceShadowOffsetY * bounceValue;

    // ── Pass 1: Shadow behind word ──────────────────────────────────
    final wordHalfW = (totalGlyphWidth / config.unitScale) / 2.0;
    final cx = -anchorOffsetRoomUnits;
    final halfH = ((textHeight / config.unitScale) / 2.0) * entranceScale;

    for (var i = 0; i < _glyphs.length; i++) {
      final glyph = _glyphs[i];
      // Per-glyph Z from stagger
      final glyphZ = _glyphZ(i, baseTextZ, bounceValue);
      // Shadow sits behind the text at a fixed depth offset
      final shadowZ = glyphZ + 1.0;

      final leftRoom = cx +
          ((glyph.xOffset / config.unitScale) - wordHalfW) * entranceScale +
          _glyphGap;
      final rightRoom = cx +
          (((glyph.xOffset + glyph.width) / config.unitScale) - wordHalfW) *
              entranceScale -
          _glyphGap;
      final midX = (leftRoom + rightRoom) / 2;

      final pMid =
          _p(Point3D(midX, -shadowOffsetY / config.unitScale, shadowZ), size);
      if (pMid == null) continue;

      final pLeft = _p(
          Point3D(leftRoom, halfH - shadowOffsetY / config.unitScale, shadowZ),
          size);
      final pRight = _p(
          Point3D(rightRoom, halfH - shadowOffsetY / config.unitScale, shadowZ),
          size);
      if (pLeft == null || pRight == null) continue;

      final projW = (pRight.dx - pLeft.dx).abs();
      final textScale = glyph.width > 0 ? projW / glyph.width : 1.0;
      final efs = fontSize * textScale;

      final poolIndex = i % TextPainterPool.maxSize;
      painterPool.configure(
        poolIndex,
        glyph.character,
        SpeedyBoyTypography.readingWord(efs, fontFamily: fontFamily),
      );
      final tp = painterPool[poolIndex];
      tp.paint(
        canvas,
        Offset(pMid.dx - tp.width / 2, pMid.dy - tp.height / 2),
      );
    }

    // ── Pass 2: Warm centered glow behind word ──────────────────
    _glowPaint.color = _glowColor;

    for (var i = 0; i < _glyphs.length; i++) {
      final glyphZ = _glyphZ(i, baseTextZ, bounceValue);
      final box = _glyphBox(i, glyphZ, totalGlyphWidth, textHeight,
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
    for (var i = 0; i < _glyphs.length; i++) {
      final glyph = _glyphs[i];
      final isAnchor = i == anchorIdx;
      final glyphZ = _glyphZ(i, baseTextZ, bounceValue);

      final leftRoom = cx +
          ((glyph.xOffset / config.unitScale) - wordHalfW) * entranceScale +
          _glyphGap;
      final rightRoom = cx +
          (((glyph.xOffset + glyph.width) / config.unitScale) - wordHalfW) *
              entranceScale -
          _glyphGap;
      final midX = (leftRoom + rightRoom) / 2;

      final pMid = _p(Point3D(midX, 0, glyphZ), size);
      final pLeft = _p(Point3D(leftRoom, halfH, glyphZ), size);
      final pRight = _p(Point3D(rightRoom, halfH, glyphZ), size);
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

  // ── Per-glyph Z with micro-stagger ────────────────────────────────
  // Each glyph arrives with a 6ms stagger (leftmost first).
  // Stagger applies to Z-axis only, not opacity or scale.
  double _glyphZ(int glyphIndex, double baseTextZ, double wordBounceValue) {
    if (reducedMotion) return baseTextZ;

    const deltaZ = SpeedyBoyMaterials.wordBounceDepthDeltaZ;
    // depthBounceValue is already transformed by SubtleBounceIn
    // For per-glyph stagger, we interpolate the raw progress
    final glyphBounce = wordBounceValue; // Base value for the word

    // Apply stagger: earlier glyphs are further along in the animation
    // At 300+ WPM the 6ms stagger is sub-conscious
    final staggerFraction =
        _glyphs.length > 1 ? glyphIndex / (_glyphs.length - 1) : 0.0;
    // Small Z offset from stagger (leftmost arrives first → closer to resting)
    final staggerZ = deltaZ *
        0.05 *
        (1.0 - staggerFraction) *
        (1.0 - glyphBounce.clamp(0.0, 1.0));

    return baseTextZ + deltaZ * (1.0 - glyphBounce) + staggerZ;
  }

  // ── Per-glyph bounding box ──────────────────────────────────────────

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
      depthBounceValue != oldDelegate.depthBounceValue ||
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
