import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/widgets/water_ripple_painter.dart';

/// Reusable neumorphic water-ripple loading overlay.
///
/// Wraps any child widget. When [isLoading] is true, draws neumorphic ripple
/// rings on top of the child surface. Respects reduced-motion preference.
///
/// Usage:
/// ```dart
/// NeumorphicRippleLoading(
///   isLoading: isProcessing,
///   surface: SpeedyBoySurface.shell,
///   child: MyWidget(),
/// )
/// ```
class NeumorphicRippleLoading extends StatefulWidget {
  const NeumorphicRippleLoading({
    super.key,
    required this.child,
    required this.isLoading,
    this.surface = SpeedyBoySurface.shell,
    this.epicenter,
    this.borderRadius = 16.0,
  });

  final Widget child;
  final bool isLoading;
  final SpeedyBoySurface surface;
  final Offset? epicenter;
  final double borderRadius;

  @override
  State<NeumorphicRippleLoading> createState() =>
      _NeumorphicRippleLoadingState();
}

class _NeumorphicRippleLoadingState extends State<NeumorphicRippleLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.waterRippleDuration,
    );

    if (widget.isLoading) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(NeumorphicRippleLoading oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isLoading && !oldWidget.isLoading) {
      // Start from beginning
      _stopping = false;
      _controller.repeat();
    } else if (!widget.isLoading && oldWidget.isLoading) {
      // Let current cycle finish, then stop
      _stopping = true;
      _controller.addStatusListener(_onFinishCycle);
    }
  }

  void _onFinishCycle(AnimationStatus status) {
    if (_stopping && status == AnimationStatus.completed) {
      _controller.stop();
      _controller.removeStatusListener(_onFinishCycle);
      _stopping = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = isReducedMotion(context);

    if (reducedMotion) {
      // Reduced motion fallback: single slow opacity pulse
      return Stack(
        children: [
          widget.child,
          if (widget.isLoading)
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: widget.isLoading ? 0.15 : 0.0,
                duration: SpeedyBoyAnimations.processingPulseDuration,
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.surface == SpeedyBoySurface.shell
                        ? SpeedyBoyTokens.shellDarkShadow
                        : SpeedyBoyTokens.stageDarkShadow,
                    borderRadius:
                        BorderRadius.circular(widget.borderRadius),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Stack(
      children: [
        widget.child,
        if (_controller.isAnimating || widget.isLoading)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: WaterRipplePainter(
                      animationValue: _controller.value,
                      surface: widget.surface,
                      epicenter: widget.epicenter,
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
