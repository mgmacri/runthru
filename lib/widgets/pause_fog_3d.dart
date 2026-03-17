import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';

/// Semi-transparent pause fog overlay on the cube interior.
class PauseFog3D extends StatefulWidget {
  const PauseFog3D({super.key, required this.isPaused, required this.wpm});

  final bool isPaused;
  final int wpm;

  @override
  State<PauseFog3D> createState() => _PauseFog3DState();
}

class _PauseFog3DState extends State<PauseFog3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.pauseFogDuration,
      reverseDuration: SpeedyBoyAnimations.resumeClearDuration,
    );
    _opacity = Tween<double>(begin: 0.0, end: 0.4).animate(
      CurvedAnimation(
        parent: _controller,
        curve: SpeedyBoyAnimations.pauseFogCurve,
        reverseCurve: SpeedyBoyAnimations.resumeClearCurve,
      ),
    );

    if (widget.isPaused) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(PauseFog3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused != oldWidget.isPaused) {
      final reducedMotion = isReducedMotion(context);
      if (widget.isPaused) {
        if (reducedMotion) {
          _controller.value = 1.0;
        } else {
          _controller.forward();
        }
      } else {
        if (reducedMotion) {
          _controller.value = 0.0;
        } else {
          _controller.reverse();
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _opacity,
      builder: (context, _) {
        if (_opacity.value == 0) return const SizedBox.shrink();
        return Container(
          color: SpeedyBoyTokens.stagePauseOverlay.withValues(
            alpha: _opacity.value,
          ),
          child: widget.isPaused
              ? Center(
                  child: Text(
                    '${widget.wpm} WPM',
                    style: SpeedyBoyTypography.stageBadge,
                  ),
                )
              : null,
        );
      },
    );
  }
}
