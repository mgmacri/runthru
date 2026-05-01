import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/gesture_classifier.dart';

void main() {
  // Reference screen dimensions for threshold calculations.
  const screenWidth = 1080.0;
  const screenHeight = 2400.0;

  // Pre-computed thresholds:
  // horizontal min distance = 1080 * 0.30 = 324 px
  // horizontal min velocity = 200 px/s
  // vertical min distance   = 2400 * 0.20 = 480 px
  // vertical min velocity   = 150 px/s

  group('Gesture threshold — horizontal swipe', () {
    test('accepted at exactly 30% screen width + 200 px/s', () {
      // 324 px in 1.62 s = exactly 200 px/s
      final result = classifySwipe(
        dx: -324.0,
        dy: 0.0,
        elapsedMs: 1620,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(result, SwipeDirection.left);
    });

    test('rejected at 29% screen width (distance gate fails)', () {
      // 29% of 1080 = 313.2 px — below 324 threshold
      // Velocity is adequate: 313.2 / 1.0 = 313.2 px/s
      final result = classifySwipe(
        dx: -313.2,
        dy: 0.0,
        elapsedMs: 1000,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(result, isNull);
    });

    test(
      'rejected at 30% screen width but only 199 px/s (velocity gate fails)',
      () {
        // 324 px in 1.629 s ≈ 199 px/s
        final result = classifySwipe(
          dx: -324.0,
          dy: 0.0,
          elapsedMs: 1629,
          screenWidth: screenWidth,
          screenHeight: screenHeight,
        );
        expect(result, isNull);
      },
    );
  });

  group('Gesture threshold — vertical swipe', () {
    test('accepted at exactly 20% screen height + 150 px/s', () {
      // 480 px in 3.2 s = exactly 150 px/s
      final result = classifySwipe(
        dx: 0.0,
        dy: -480.0,
        elapsedMs: 3200,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(result, SwipeDirection.up);
    });

    test('rejected below both thresholds', () {
      // Small, slow drag — should never fire
      final result = classifySwipe(
        dx: 0.0,
        dy: -100.0,
        elapsedMs: 2000,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(result, isNull);
    });
  });

  group('Gesture threshold — direction correctness', () {
    test('positive dx → SwipeDirection.right', () {
      final result = classifySwipe(
        dx: 400.0,
        dy: 0.0,
        elapsedMs: 500,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(result, SwipeDirection.right);
    });

    test('positive dy → SwipeDirection.down', () {
      final result = classifySwipe(
        dx: 0.0,
        dy: 600.0,
        elapsedMs: 500,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(result, SwipeDirection.down);
    });

    test('zero elapsed returns null (tap)', () {
      final result = classifySwipe(
        dx: 400.0,
        dy: 0.0,
        elapsedMs: 0,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(result, isNull);
    });
  });
}
