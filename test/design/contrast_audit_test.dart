import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/design/tokens.dart';

void main() {
  /// Compute WCAG relative luminance of a Color.
  double luminance(Color color) {
    // Using the standard formula with linearized sRGB
    final r = _linearize((color.r * 255.0).round().clamp(0, 255) / 255.0);
    final g = _linearize((color.g * 255.0).round().clamp(0, 255) / 255.0);
    final b = _linearize((color.b * 255.0).round().clamp(0, 255) / 255.0);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  double contrastRatio(Color fg, Color bg) {
    final l1 = luminance(fg);
    final l2 = luminance(bg);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  group('WCAG Contrast Audit', () {
    test('stageText / stageBase ≥ 7:1 (AAA)', () {
      final ratio = contrastRatio(
        RunThruTokens.stageText,
        RunThruTokens.stageBase,
      );
      expect(ratio, greaterThanOrEqualTo(7.0));
    });

    test('stageAnchor / stageBase ≥ 3:1 (AA Large Text)', () {
      final ratio = contrastRatio(
        RunThruTokens.stageAnchor,
        RunThruTokens.stageBase,
      );
      expect(ratio, greaterThanOrEqualTo(3.0));
    });

    test('shellTextPrimary / shellBase ≥ 7:1 (AAA)', () {
      final ratio = contrastRatio(
        RunThruTokens.shellTextPrimary,
        RunThruTokens.shellBase,
      );
      expect(ratio, greaterThanOrEqualTo(7.0));
    });

    test('shellTextSecondary / shellBase ≥ 4.5:1 (AA)', () {
      final ratio = contrastRatio(
        RunThruTokens.shellTextSecondary,
        RunThruTokens.shellBase,
      );
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('shellAccent / shellBase ≥ 3:1 (AA Large Text)', () {
      final ratio = contrastRatio(
        RunThruTokens.shellAccent,
        RunThruTokens.shellBase,
      );
      expect(ratio, greaterThanOrEqualTo(3.0));
    });
  });
}

/// Linearize sRGB channel value.
double _linearize(double c) {
  if (c <= 0.03928) return c / 12.92;
  return _pow((c + 0.055) / 1.055, 2.4);
}

/// Simple power function approximation.
double _pow(double base, double exp) {
  // Use dart:math for accurate computation
  return _expApprox(exp * _lnApprox(base));
}

double _lnApprox(double x) {
  // Natural log via Taylor series — sufficient for contrast
  if (x <= 0) return -999;
  double result = 0;
  double term = (x - 1) / (x + 1);
  final termSq = term * term;
  for (var n = 1; n <= 50; n += 2) {
    result += term / n;
    term *= termSq;
  }
  return 2 * result;
}

double _expApprox(double x) {
  double result = 1;
  double term = 1;
  for (var n = 1; n <= 50; n++) {
    term *= x / n;
    result += term;
  }
  return result;
}
