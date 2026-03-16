import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:speedy_boy/design/design.dart';

/// A-010 cube rotation page transition.
/// Falls back to instant transition when reduce-motion is active.
Page<void> cubeTransitionPage({
  required LocalKey key,
  required Widget child,
  int direction = 1,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: SpeedyBoyAnimations.cubeRotateDuration,
    reverseTransitionDuration: SpeedyBoyAnimations.cubeRotateDuration,
    transitionsBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      final reducedMotion = isReducedMotion(context);
      if (reducedMotion) return child;

      final curved = CurvedAnimation(
        parent: animation,
        curve: SpeedyBoyAnimations.cubeRotateCurve,
      );

      return ListenableBuilder(
        listenable: curved,
        builder: (BuildContext context, Widget? _) {
          final angle = direction * (math.pi / 2) * (1 - curved.value);
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle);
          return Transform(
            transform: transform,
            alignment:
                direction > 0 ? Alignment.centerRight : Alignment.centerLeft,
            child: child,
          );
        },
      );
    },
  );
}
