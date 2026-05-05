import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/dynamic_font_size.dart';

void main() {
  group('dynamicFontSize', () {
    test('sizes text so 30-char word fits in viewport width', () {
      final result = dynamicFontSize(
        const BoxConstraints(maxWidth: 500, maxHeight: 300),
      );
      // 90% of 500 / (30 * 0.55) ≈ 27.27
      expect(result, closeTo(27.27, 0.1));
    });

    test('clamps to minimum 16.0', () {
      final result = dynamicFontSize(
        const BoxConstraints(maxWidth: 100, maxHeight: 100),
      );
      // 90% of 100 / 16.5 ≈ 5.45, clamped to 16.0
      expect(result, 16.0);
    });

    test('clamps to maximum 400.0', () {
      final result = dynamicFontSize(
        const BoxConstraints(maxWidth: 8000, maxHeight: 8000),
      );
      // 90% of 8000 / 16.5 ≈ 436.4, clamped to 400
      expect(result, 400.0);
    });

    test('handles square constraints', () {
      final result = dynamicFontSize(
        const BoxConstraints(maxWidth: 400, maxHeight: 400),
      );
      // 90% of 400 / (30 * 0.55) ≈ 21.82
      expect(result, closeTo(21.82, 0.1));
    });
  });
}
