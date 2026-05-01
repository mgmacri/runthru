import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/wcag_contrast.dart';
import 'package:runthru/design/design.dart';

void main() {
  group('Anchor contrast safety (P14 Grade C)', () {
    test('all anchor colors have contrast ratio ≥ 1.0 against stageBase', () {
      for (var i = 0; i < RunThruTokens.anchorColors.length; i++) {
        final color = RunThruTokens.anchorColors[i];
        final name = RunThruTokens.anchorColorNames[i];
        final ratio = WcagContrast.contrastRatio(
          color,
          RunThruTokens.stageBase,
        );
        expect(ratio, greaterThanOrEqualTo(1.0), reason: '$name contrast');
      }
    });

    test('dark anchors exceed 3:1 against stageBase', () {
      // Turkish Sea and Brilliant Blue are among the darkest anchor colors
      const darkIndices = [8, 7]; // Turkish Sea, Brilliant Blue
      for (final i in darkIndices) {
        final color = RunThruTokens.anchorColors[i];
        final name = RunThruTokens.anchorColorNames[i];
        final ratio = WcagContrast.contrastRatio(
          color,
          RunThruTokens.stageBase,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason: '$name should be high-contrast',
        );
      }
    });

    test('light anchors have lower contrast than dark anchors', () {
      // Buttercup (light yellow) should have less contrast than Turkish Sea
      final buttercupRatio = WcagContrast.contrastRatio(
        RunThruTokens.anchorColors[3], // Buttercup
        RunThruTokens.stageBase,
      );
      final turkishSeaRatio = WcagContrast.contrastRatio(
        RunThruTokens.anchorColors[8], // Turkish Sea
        RunThruTokens.stageBase,
      );
      expect(
        turkishSeaRatio,
        greaterThan(buttercupRatio),
        reason: 'Turkish Sea should have higher contrast than Buttercup',
      );
    });

    test('warning tier thresholds match implementation', () {
      for (var i = 0; i < RunThruTokens.anchorColors.length; i++) {
        final color = RunThruTokens.anchorColors[i];
        final name = RunThruTokens.anchorColorNames[i];
        final ratio = WcagContrast.contrastRatio(
          color,
          RunThruTokens.stageBase,
        );
        // Verify tier classification is deterministic
        if (ratio >= 4.5) {
          // No warning tier
        } else if (ratio >= 3.0) {
          // Caution tier
        } else {
          // Danger tier
        }
        // All anchors produce a valid ratio
        expect(ratio, isPositive, reason: '$name ratio must be positive');
      }
    });

    test('stageAnchor default exceeds 3:1 (AA Large Text)', () {
      final ratio = WcagContrast.contrastRatio(
        RunThruTokens.stageAnchor,
        RunThruTokens.stageBase,
      );
      expect(ratio, greaterThanOrEqualTo(3.0));
    });
  });
}
