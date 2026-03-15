import 'package:flutter/material.dart';
import 'package:speedy_boy/core/orp.dart';
import 'package:speedy_boy/design/typography.dart';
import 'package:speedy_boy/three_d/glyph_measurer.dart';
import 'package:speedy_boy/three_d/text_painter_pool.dart';

/// CustomPainter for word rendering with ORP-anchored centering.
/// The anchor letter is always pinned to the horizontal center of the canvas.
///
/// Uses a [TextPainterPool] to avoid allocating TextPainters in paint().
class WordPainter extends CustomPainter {
  WordPainter({
    required this.word,
    required this.fontSize,
    required this.animationValue,
    required this.painterPool,
    this.anchorColor,
    this.fontFamily = 'BricolageGrotesque',
    super.repaint,
  })  : _anchorIndex = orpIndexInOriginal(word),
        _glyphs = GlyphMeasurer.instance.measureWord(
          word,
          fontSize,
          anchorIndex: orpIndexInOriginal(word),
        );

  final String word;
  final double fontSize;
  final double animationValue;
  final Color? anchorColor;
  final String fontFamily;
  final TextPainterPool painterPool;
  final int _anchorIndex;
  final List<GlyphPosition> _glyphs;

  @override
  void paint(Canvas canvas, Size size) {
    if (word.isEmpty || _glyphs.isEmpty) return;

    // Anchor glyph (1-indexed _anchorIndex → 0-indexed)
    final anchorIdx = (_anchorIndex - 1).clamp(0, _glyphs.length - 1);
    final anchorGlyph = _glyphs[anchorIdx];
    // Pin anchor glyph center to screen center
    final anchorCenterX = anchorGlyph.xOffset + anchorGlyph.width / 2;
    final startX = (size.width / 2) - anchorCenterX;
    final centerY = size.height / 2;

    // Subtle scale pulse from animation
    final scale = 1.0 + 0.015 * animationValue;
    canvas.save();
    canvas.translate(size.width / 2, centerY);
    canvas.scale(scale, scale);
    canvas.translate(-size.width / 2, -centerY);

    // ── Draw each glyph using pooled painters (round-robin) ──
    for (var i = 0; i < _glyphs.length; i++) {
      final glyph = _glyphs[i];
      final isAnchor = i == anchorIdx;

      final style = isAnchor
          ? SpeedyBoyTypography.readingAnchor(fontSize,
              color: anchorColor, fontFamily: fontFamily)
          : SpeedyBoyTypography.readingWord(fontSize, fontFamily: fontFamily);

      final poolIndex = i % TextPainterPool.maxSize;
      painterPool.configure(poolIndex, glyph.character, style);
      final tp = painterPool[poolIndex];

      tp.paint(
        canvas,
        Offset(
          startX + glyph.xOffset,
          centerY - tp.height / 2,
        ),
      );
    }

    // Anchor line removed — it was drawing through the middle of the letter.

    canvas.restore();
  }

  @override
  bool shouldRepaint(WordPainter oldDelegate) {
    return word != oldDelegate.word ||
        fontSize != oldDelegate.fontSize ||
        animationValue != oldDelegate.animationValue ||
        fontFamily != oldDelegate.fontFamily;
  }
}
