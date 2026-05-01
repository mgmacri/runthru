import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/design/design.dart';

/// Page transition where the reading room's 4 walls fold outward
/// (left, right, top fold first; bottom + back wall fold last),
/// revealing the library screen underneath which zooms in.
///
/// Forward: simple fade-in (the room has its own build animation).
/// Reverse: staggered wall fold-out.
Page<void> wallFoldTransitionPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    opaque: false, // let the library show through during fold-out
    transitionDuration: const Duration(milliseconds: 400),
    reverseTransitionDuration: const Duration(milliseconds: 850),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (isReducedMotion(context)) return child;

      // Forward enter: fade in
      if (animation.status == AnimationStatus.forward ||
          animation.status == AnimationStatus.completed) {
        return FadeTransition(opacity: animation, child: child);
      }

      // Reverse exit: wall fold-out
      // animation goes 1→0, so fold progress = 1 - animation.value
      return _WallFoldOut(
        foldProgress: 1.0 - animation.value,
        child: child,
      );
    },
  );
}

/// Page transition for the library screen that zooms in from 0.88→1.0
/// when uncovered (the reading page is popped).
///
/// Forward enter/exit uses the standard cube transition.
Page<void> libraryTransitionPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: RunThruAnimations.cubeRotateDuration,
    reverseTransitionDuration: const Duration(milliseconds: 850),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (isReducedMotion(context)) return child;

      // Primary animation: this page entering/leaving
      final curved = CurvedAnimation(
        parent: animation,
        curve: RunThruAnimations.cubeRotateCurve,
      );

      Widget result = FadeTransition(opacity: curved, child: child);

      // Secondary animation: another page is on top of this one.
      // When secondaryAnimation goes from 1→0 (other page popping),
      // zoom from small → normal.
      if (secondaryAnimation.status != AnimationStatus.dismissed) {
        final zoomCurved = CurvedAnimation(
          parent: secondaryAnimation,
          curve: Curves.easeOutCubic,
        );
        result = ListenableBuilder(
          listenable: zoomCurved,
          child: result,
          builder: (context, animChild) {
            // secondary 1.0 = covered (small), 0.0 = uncovered (normal)
            final scale = 1.0 - (zoomCurved.value * 0.12);
            return Transform.scale(scale: scale, child: animChild);
          },
        );
      }

      return result;
    },
  );
}

/// Renders the fold-out animation: 4 colored wall panels fold away
/// from the center while the main content fades out.
class _WallFoldOut extends StatelessWidget {
  const _WallFoldOut({
    required this.foldProgress,
    required this.child,
  });

  /// 0.0 = fully closed (normal view), 1.0 = fully folded out.
  final double foldProgress;
  final Widget child;

  /// Map [progress] into a sub-range [start..end], clamped to 0–1.
  static double _stagger(double progress, double start, double end) {
    return ((progress - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // Staggered fold progress per wall (eased)
    final leftT =
        Curves.easeInCubic.transform(_stagger(foldProgress, 0.0, 0.6));
    final rightT =
        Curves.easeInCubic.transform(_stagger(foldProgress, 0.05, 0.65));
    final topT =
        Curves.easeInCubic.transform(_stagger(foldProgress, 0.10, 0.70));
    final bottomT =
        Curves.easeInCubic.transform(_stagger(foldProgress, 0.30, 1.0));

    // Max fold angle (slightly less than 90° to avoid projection artifacts)
    const maxAngle = math.pi * 0.42; // ~75°

    // Content fades out as walls fold
    final contentOpacity = (1.0 - foldProgress * 1.6).clamp(0.0, 1.0);

    // Wall dimensions as fractions of the screen
    const topFrac = 0.20;
    const sideFrac = 0.20;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final topH = h * topFrac;
        final sideW = w * sideFrac;

        return Stack(
          fit: StackFit.expand,
          children: [
            // ── Main content fading out ──
            if (contentOpacity > 0.0)
              Opacity(opacity: contentOpacity, child: child),

            // ── Bottom + back wall panel (behind other panels, folds last) ──
            Positioned.fill(
              child: _FoldPanel(
                alignment: Alignment.bottomCenter,
                angle: bottomT * maxAngle,
                axisDirection: Axis.horizontal,
                color: RunThruTokens.cubeBottomWall,
                backWallColor: RunThruTokens.cubeBackWall,
              ),
            ),

            // ── Left wall panel ──
            Positioned(
              top: topH,
              left: 0,
              width: sideW,
              bottom: 0,
              child: _FoldPanel(
                alignment: Alignment.centerLeft,
                angle: leftT * maxAngle,
                axisDirection: Axis.vertical,
                color: RunThruTokens.cubeLeftWall,
              ),
            ),

            // ── Right wall panel ──
            Positioned(
              top: topH,
              right: 0,
              width: sideW,
              bottom: 0,
              child: _FoldPanel(
                alignment: Alignment.centerRight,
                angle: rightT * maxAngle,
                axisDirection: Axis.vertical,
                invertAngle: true,
                color: RunThruTokens.cubeRightWall,
              ),
            ),

            // ── Top wall panel ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topH,
              child: _FoldPanel(
                alignment: Alignment.topCenter,
                angle: topT * maxAngle,
                axisDirection: Axis.horizontal,
                invertAngle: true,
                color: RunThruTokens.cubeTopWall,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A single panel that folds outward from its [alignment] edge.
class _FoldPanel extends StatelessWidget {
  const _FoldPanel({
    required this.alignment,
    required this.angle,
    required this.axisDirection,
    required this.color,
    this.backWallColor,
    this.invertAngle = false,
  });

  final Alignment alignment;
  final double angle;
  final Axis axisDirection;
  final Color color;
  final Color? backWallColor;
  final bool invertAngle;

  @override
  Widget build(BuildContext context) {
    if (angle <= 0.001) {
      // Not yet folding — show flat panel
      return _panelContent();
    }

    final foldAngle = invertAngle ? -angle : angle;

    final transform = Matrix4.identity()..setEntry(3, 2, 0.0015);
    if (axisDirection == Axis.horizontal) {
      transform.rotateX(foldAngle);
    } else {
      transform.rotateY(foldAngle);
    }

    return Transform(
      alignment: alignment,
      transform: transform,
      child: _panelContent(),
    );
  }

  Widget _panelContent() {
    if (backWallColor != null) {
      // Bottom + back: gradient from back wall color to floor color
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [backWallColor!, color],
            stops: const [0.0, 0.6],
          ),
        ),
      );
    }
    return ColoredBox(color: color);
  }
}
