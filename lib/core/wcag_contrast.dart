import 'dart:math' as math;
import 'dart:ui';

// P14 Grade C — anchor contrast safety net

/// WCAG 2.1 contrast ratio utilities for runtime contrast checks.
abstract final class WcagContrast {
  /// Returns the contrast ratio between [fg] and [bg].
  ///
  /// Result is always ≥ 1.0 (identical colors → 1.0, white/black → 21.0).
  static double contrastRatio(Color fg, Color bg) {
    final l1 = relativeLuminance(fg);
    final l2 = relativeLuminance(bg);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Computes WCAG 2.1 relative luminance per
  /// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
  static double relativeLuminance(Color color) {
    final r = _linearize(color.r);
    final g = _linearize(color.g);
    final b = _linearize(color.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Linearize an sRGB channel value to linear RGB.
  static double _linearize(double c) {
    if (c <= 0.03928) return c / 12.92;
    return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }
}
