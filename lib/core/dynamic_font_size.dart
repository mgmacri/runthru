import 'package:flutter/widgets.dart';

/// Dynamic font size calculation for word display.
///
/// Sizes text so that a 30-character word fits within the viewport width
/// with a small horizontal margin (90% of available width). Uses a
/// monospace-equivalent average character width ratio of ~0.6.
///
/// NOTE: This is used only by the non-parallax reading_screen.dart.
/// The parallax reading screen uses [BackWallFontSizer] from
/// `lib/three_d/back_wall_font_sizer.dart` which sizes text relative
/// to the projected back wall width.
double dynamicFontSize(BoxConstraints constraints) {
  // 90% of viewport width to leave margin on each side.
  final availableWidth = constraints.maxWidth * 0.90;

  // Average character width is roughly 0.55× the font size for
  // proportional fonts like Bricolage Grotesque / Satoshi. A 30-char
  // word at fontSize F occupies approximately 30 × 0.55 × F pixels.
  const maxChars = 30;
  const avgCharWidthRatio = 0.55;
  final calculated = availableWidth / (maxChars * avgCharWidthRatio);
  return calculated.clamp(16.0, 400.0);
}

/// Extrusion depth for pseudo-3D text effect.
double extrusionDepth(double fontSize) => fontSize * 0.08;
