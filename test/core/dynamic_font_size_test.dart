import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/dynamic_font_size.dart';

void main() {
  group('dynamicFontSize', () {
    test('returns 20% of shorter dimension', () {
      final result = dynamicFontSize(
        const BoxConstraints(maxWidth: 500, maxHeight: 300),
      );
      // 20% of 300 = 60
      expect(result, closeTo(60.0, 0.1));
    });

    test('clamps to minimum 28.0', () {
      final result = dynamicFontSize(
        const BoxConstraints(maxWidth: 100, maxHeight: 100),
      );
      // 20% of 100 = 20, but clamped to 28
      expect(result, 28.0);
    });

    test('clamps to maximum 400.0', () {
      final result = dynamicFontSize(
        const BoxConstraints(maxWidth: 3000, maxHeight: 3000),
      );
      // 20% of 3000 = 600, but clamped to 400
      expect(result, 400.0);
    });

    test('handles square constraints', () {
      final result = dynamicFontSize(
        const BoxConstraints(maxWidth: 400, maxHeight: 400),
      );
      // 20% of 400 = 80
      expect(result, closeTo(80.0, 0.1));
    });
  });
}
