import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';

/// 3D floating WPM dial with SweepGradient arc ring.
class WpmDial3D extends StatefulWidget {
  const WpmDial3D({
    super.key,
    required this.wpm,
    required this.onWpmChanged,
    required this.visible,
    required this.onDismissed,
  });

  final int wpm;
  final ValueChanged<int> onWpmChanged;
  final bool visible;
  final VoidCallback onDismissed;

  @override
  State<WpmDial3D> createState() => _WpmDial3DState();
}

class _WpmDial3DState extends State<WpmDial3D> with TickerProviderStateMixin {
  late final AnimationController _emergeController;
  late final Animation<double> _emergeAnimation;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _emergeController = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.dialEmergeDuration,
    );
    _emergeAnimation = CurvedAnimation(
      parent: _emergeController,
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(WpmDial3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _show();
    } else if (!widget.visible && oldWidget.visible) {
      _hide();
    }
  }

  void _show() {
    final reducedMotion = isReducedMotion(context);
    if (reducedMotion) {
      _emergeController.value = 1.0;
    } else {
      _emergeController.animateWith(
        SpeedyBoyAnimations.dialEmergeSimulation(),
      );
    }
    _resetAutoDismiss();
  }

  void _hide() {
    _autoDismissTimer?.cancel();
    final reducedMotion = isReducedMotion(context);
    if (reducedMotion) {
      _emergeController.value = 0.0;
    } else {
      _emergeController.animateTo(
        0.0,
        duration: SpeedyBoyAnimations.dialDismissDuration,
        curve: SpeedyBoyAnimations.dialDismissCurve,
      );
    }
  }

  void _resetAutoDismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(
      const Duration(seconds: 3),
      widget.onDismissed,
    );
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _emergeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _emergeAnimation,
      builder: (context, child) {
        if (_emergeAnimation.value == 0) {
          return const SizedBox.shrink();
        }
        return Opacity(
          opacity: _emergeAnimation.value,
          child: Transform.translate(
            offset: Offset(
              0,
              100 * (1 - _emergeAnimation.value),
            ),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onPanUpdate: (details) {
          // Circular drag → WPM change
          final delta = -details.delta.dy;
          final newWpm = (widget.wpm + delta.round()).clamp(30, 1000);
          widget.onWpmChanged(newWpm);
          _resetAutoDismiss();
        },
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _DialPainter(
              wpm: widget.wpm,
              progress: (widget.wpm - 30) / (1000 - 30),
            ),
            size: const Size(240, 240),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.wpm,
    required this.progress,
  });

  final int wpm;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;
    const ringWidth = 8.0;

    // ── Neumorphic shadow disc ──
    final shadowPaint = Paint()
      ..color = SpeedyBoyTokens.stageDarkShadow.withOpacity(0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(
      center + const Offset(3, 3),
      radius + ringWidth,
      shadowPaint,
    );

    final discPaint = Paint()..color = SpeedyBoyTokens.stageBase;
    canvas.drawCircle(center, radius + ringWidth, discPaint);

    // ── SweepGradient arc ring ──
    const gradient = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: -math.pi / 2 + 2 * math.pi,
      colors: [
        SpeedyBoyTokens.dialRingLow,
        SpeedyBoyTokens.dialRingMid,
        SpeedyBoyTokens.dialRingHigh,
      ],
      stops: [0.0, 0.5, 1.0],
    );

    final ringPaint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      ringPaint,
    );

    // ── Center badge ──
    final tp = TextPainter(
      text: TextSpan(
        text: '$wpm',
        style: SpeedyBoyTypography.badge,
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(
        center.dx - tp.width / 2,
        center.dy - tp.height / 2 - 6,
      ),
    );
    tp.dispose();

    final labelPainter = TextPainter(
      text: const TextSpan(
        text: 'WPM',
        style: SpeedyBoyTypography.caption,
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    labelPainter.paint(
      canvas,
      Offset(
        center.dx - labelPainter.width / 2,
        center.dy + 8,
      ),
    );
    labelPainter.dispose();
  }

  @override
  bool shouldRepaint(_DialPainter oldDelegate) {
    return wpm != oldDelegate.wpm || progress != oldDelegate.progress;
  }
}
