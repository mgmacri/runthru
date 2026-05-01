import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/wcag_contrast.dart';
import 'package:runthru/design/design.dart';

void main() {
  group('WcagContrast', () {
    test('white on black is 21:1', () {
      final ratio = WcagContrast.contrastRatio(
        const Color(0xFFFFFFFF),
        const Color(0xFF000000),
      );
      expect(ratio, closeTo(21.0, 0.1));
    });

    test('identical colors return 1:1', () {
      const color = Color(0xFF808080);
      final ratio = WcagContrast.contrastRatio(color, color);
      expect(ratio, closeTo(1.0, 0.001));
    });

    test('stageText on stageBase exceeds 7:1', () {
      final ratio = WcagContrast.contrastRatio(
        RunThruTokens.stageText,
        RunThruTokens.stageBase,
      );
      expect(ratio, greaterThanOrEqualTo(7.0));
    });

    test('stageAnchor on stageBase exceeds 3:1', () {
      final ratio = WcagContrast.contrastRatio(
        RunThruTokens.stageAnchor,
        RunThruTokens.stageBase,
      );
      expect(ratio, greaterThanOrEqualTo(3.0));
    });

    test('known mid-contrast pair returns expected ratio', () {
      // Pure red (#FF0000) on white (#FFFFFF)
      // Relative luminance of red ≈ 0.2126, white = 1.0
      // Ratio = (1.0 + 0.05) / (0.2126 + 0.05) ≈ 4.0
      final ratio = WcagContrast.contrastRatio(
        const Color(0xFFFF0000),
        const Color(0xFFFFFFFF),
      );
      expect(ratio, closeTo(4.0, 0.1));
    });
  });
}
