import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/gradient_sweep_engine.dart';

void main() {
  group('GradientSweepEngine', () {
    test('isRunning is true after start', () {
      final engine = GradientSweepEngine();
      engine.start();

      expect(engine.isRunning, isTrue);
      expect(engine.isPaused, isFalse);

      engine.dispose();
    });

    test('pause and resume toggle isPaused', () {
      final engine = GradientSweepEngine();
      engine.start();

      engine.pause();
      expect(engine.isPaused, isTrue);
      expect(engine.isRunning, isTrue); // timer still ticks

      engine.resume();
      expect(engine.isPaused, isFalse);

      engine.dispose();
    });

    test('togglePause alternates state', () {
      final engine = GradientSweepEngine();
      engine.start();
      expect(engine.isPaused, isFalse);

      engine.togglePause();
      expect(engine.isPaused, isTrue);

      engine.togglePause();
      expect(engine.isPaused, isFalse);

      engine.dispose();
    });

    test('stop cancels timer and clears pause', () {
      final engine = GradientSweepEngine();
      engine.start();
      engine.pause();

      engine.stop();
      expect(engine.isRunning, isFalse);
      expect(engine.isPaused, isFalse);
    });

    test('reset restarts the timer and clears pause', () {
      final engine = GradientSweepEngine();
      engine.start();
      engine.pause();
      expect(engine.isPaused, isTrue);

      engine.reset();
      expect(engine.isRunning, isTrue);
      expect(engine.isPaused, isFalse);

      engine.dispose();
    });

    test('dispose stops the timer', () {
      final engine = GradientSweepEngine();
      engine.start();

      engine.dispose();
      expect(engine.isRunning, isFalse);
    });
  });
}
