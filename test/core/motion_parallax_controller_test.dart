import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/head_position.dart';
import 'package:runthru/core/motion_parallax_controller.dart';

void main() {
  group('applySmoothing', () {
    test('returns raw when current equals raw', () {
      expect(applySmoothing(0.5, 0.5, 0.12), closeTo(0.5, 1e-10));
    });

    test('blends toward raw by alpha fraction', () {
      // current=0, raw=1, alpha=0.12 → result = 0*0.88 + 1*0.12 = 0.12
      expect(applySmoothing(0.0, 1.0, 0.12), closeTo(0.12, 1e-10));
    });

    test('converges toward raw over many iterations', () {
      double v = 0.0;
      for (var i = 0; i < 200; i++) {
        v = applySmoothing(v, 1.0, 0.12);
      }
      expect(v, greaterThan(0.99));
    });

    test('alpha=1 snaps immediately to raw', () {
      expect(applySmoothing(0.0, 0.8, 1.0), closeTo(0.8, 1e-10));
    });
  });

  group('applyDeadZone', () {
    test('values below dead zone snap to zero', () {
      expect(applyDeadZone(0.01, 0.025), 0.0);
      expect(applyDeadZone(-0.01, 0.025), 0.0);
      expect(applyDeadZone(0.024, 0.025), 0.0);
    });

    test('values at or above dead zone pass through', () {
      expect(applyDeadZone(0.025, 0.025), closeTo(0.025, 1e-10));
      expect(applyDeadZone(0.5, 0.025), closeTo(0.5, 1e-10));
      expect(applyDeadZone(-0.5, 0.025), closeTo(-0.5, 1e-10));
    });

    test('zero dead zone passes all values', () {
      expect(applyDeadZone(0.001, 0.0), closeTo(0.001, 1e-10));
    });
  });

  group('normalizeTilt', () {
    test('zero angle produces zero', () {
      expect(normalizeTilt(0.0, 0.35), 0.0);
    });

    test('max angle produces 1.0', () {
      expect(normalizeTilt(0.35, 0.35), closeTo(1.0, 1e-10));
    });

    test('clamps values beyond maxRad', () {
      expect(normalizeTilt(1.0, 0.35), 1.0);
      expect(normalizeTilt(-1.0, 0.35), -1.0);
    });

    test('half max angle produces 0.5', () {
      expect(normalizeTilt(0.175, 0.35), closeTo(0.5, 1e-10));
    });
  });

  group('MotionParallaxController', () {
    late MotionParallaxController ctrl;

    setUp(() => ctrl = MotionParallaxController());
    tearDown(() => ctrl.dispose());

    test('initial state is zero static', () {
      expect(ctrl.positionNotifier.value, Offset.zero);
      expect(ctrl.state.source, MotionSource.static);
      expect(ctrl.state.isAvailable, false);
    });

    test('start with reducedMotion keeps position at zero', () {
      ctrl.start(reducedMotion: true);
      expect(ctrl.positionNotifier.value, Offset.zero);
      expect(ctrl.state.source, MotionSource.static);
    });

    test('start with isDesktop sets pointer source', () {
      ctrl.start(reducedMotion: false, isDesktop: true);
      expect(ctrl.state.source, MotionSource.pointer);
      expect(ctrl.state.isAvailable, true);
    });

    test('onPointerMove updates position on desktop', () {
      ctrl.start(reducedMotion: false, isDesktop: true);
      // Centre of screen → zero offset
      ctrl.onPointerMove(
        const Offset(200, 300),
        const Size(400, 600),
      );
      expect(ctrl.positionNotifier.value, Offset.zero);
    });

    test('onPointerMove applies dead zone', () {
      ctrl.start(reducedMotion: false, isDesktop: true);
      // Slightly off centre — within dead zone → still zero
      ctrl.onPointerMove(
        const Offset(201, 300), // 0.5% of width → normalised ~0.005
        const Size(400, 600),
      );
      expect(ctrl.positionNotifier.value, Offset.zero);
    });

    test('onPointerMove clamps to −1..1', () {
      ctrl.start(reducedMotion: false, isDesktop: true);
      // Far left edge → x should be clamped to −1
      ctrl.onPointerMove(const Offset(0, 300), const Size(400, 600));
      expect(ctrl.positionNotifier.value.dx, -1.0);
    });

    test('onPointerMove ignored in reduced motion mode', () {
      ctrl.start(reducedMotion: true);
      ctrl.onPointerMove(const Offset(0, 0), const Size(400, 600));
      expect(ctrl.positionNotifier.value, Offset.zero);
    });

    test('recalibrate resets position to zero', () {
      ctrl.start(reducedMotion: false, isDesktop: true);
      ctrl.onPointerMove(const Offset(0, 0), const Size(400, 600));
      // Position is now non-zero
      ctrl.recalibrate();
      expect(ctrl.positionNotifier.value, Offset.zero);
    });

    test('stop resets position and marks unavailable', () {
      ctrl.start(reducedMotion: false, isDesktop: true);
      ctrl.stop();
      expect(ctrl.positionNotifier.value, Offset.zero);
      expect(ctrl.state.isAvailable, false);
    });

    test('calibration marks isCalibrated true', () {
      ctrl.start(reducedMotion: false, isDesktop: true);
      expect(ctrl.state.isCalibrated, true);
    });
  });
}
