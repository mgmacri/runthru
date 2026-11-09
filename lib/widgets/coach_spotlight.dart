import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';

/// Full-screen scrim with a rounded-rect cut-out that spotlights a target area.
///
/// The cut-out is rendered via [CustomPaint] using path difference — the dim
/// scrim covers everything except the target rect (inflated by [inflate]).
/// A 2.5px accent ring and soft glow surround the hole.
/// The hole animates between positions over 420ms easeOutCubic; under
/// `isReducedMotion`, the position jumps instantly.
class CoachSpotlight extends StatefulWidget {
  const CoachSpotlight({
    super.key,
    required this.targetRect,
    required this.accent,
    this.inflate = 9.0,
    this.borderRadius = 16.0,
    this.scrimOpacity = 0.52,
    this.onScrimTap,
  });

  final Rect targetRect;
  final Color accent;
  final double inflate;
  final double borderRadius;
  final double scrimOpacity;
  final VoidCallback? onScrimTap;

  @override
  State<CoachSpotlight> createState() => _CoachSpotlightState();
}

class _CoachSpotlightState extends State<CoachSpotlight>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Rect _oldRect;
  late Rect _currentRect;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _oldRect = widget.targetRect;
    _currentRect = widget.targetRect;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..value = 1.0;
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(CoachSpotlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetRect != widget.targetRect) {
      _oldRect = _lerpRect(_oldRect, _currentRect, _animation.value);
      _currentRect = widget.targetRect;
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (isReducedMotion(context)) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static Rect _lerpRect(Rect a, Rect b, double t) {
    return Rect.fromLTRB(
      a.left + (b.left - a.left) * t,
      a.top + (b.top - a.top) * t,
      a.right + (b.right - a.right) * t,
      a.bottom + (b.bottom - a.bottom) * t,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final rect = _lerpRect(_oldRect, _currentRect, _animation.value);
        final inflated = rect.inflate(widget.inflate);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onScrimTap,
          child: CustomPaint(
            size: Size.infinite,
            painter: _SpotlightPainter(
              holeRect: inflated,
              accent: widget.accent,
              borderRadius: widget.borderRadius,
              scrimOpacity: widget.scrimOpacity,
            ),
          ),
        );
      },
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.holeRect,
    required this.accent,
    required this.borderRadius,
    required this.scrimOpacity,
  });

  final Rect holeRect;
  final Color accent;
  final double borderRadius;
  final double scrimOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    // scrim cut-out, not a surface shadow
    final fullRect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      holeRect,
      Radius.circular(borderRadius),
    );

    final scrimPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(fullRect),
      Path()..addRRect(rrect),
    );

    canvas.drawPath(
      scrimPath,
      Paint()..color = const Color(0xFF241C10).withValues(alpha: scrimOpacity),
    );

    // 2.5px accent ring
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Soft accent glow
    canvas.drawRRect(
      rrect.inflate(3),
      Paint()
        ..color = accent.withValues(alpha: 0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      holeRect != old.holeRect ||
      accent != old.accent ||
      scrimOpacity != old.scrimOpacity;
}
