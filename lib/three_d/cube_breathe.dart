import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:speedy_boy/design/design.dart';

/// Cube breathe animation controller mixin (A-011).
/// ±1.5° Y-axis oscillation, 8000ms period, active only when idle.
mixin CubeBreatheMixin<T extends StatefulWidget>
    on SingleTickerProviderStateMixin<T> {
  late final AnimationController breatheController;
  bool _breatheActive = false;

  void initBreathe({bool reducedMotion = false}) {
    breatheController = AnimationController(
      vsync: this,
      duration: reducedMotion
          ? Duration.zero
          : SpeedyBoyAnimations.cubeBreatheDuration,
    );
  }

  void startBreathe() {
    if (_breatheActive) return;
    _breatheActive = true;
    breatheController.repeat();
  }

  void stopBreathe() {
    if (!_breatheActive) return;
    _breatheActive = false;
    breatheController.stop();
    breatheController.value = 0;
  }

  double get breatheAngle {
    if (!_breatheActive) return 0.0;
    return math.sin(breatheController.value * 2 * math.pi) *
        1.5 *
        math.pi /
        180.0;
  }

  void disposeBreathe() {
    breatheController.dispose();
  }
}
