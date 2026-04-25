import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speedy_boy/design/design.dart';

/// 3D floating WPM dial with SweepGradient arc ring.
///
/// State (visibility, inactivity timer) is managed by [WpmDialNotifier].
/// This widget only handles rendering and drag input.
class WpmDial3D extends StatefulWidget {
  const WpmDial3D({
    super.key,
    required this.wpm,
    required this.visible,
    required this.onWpmChanged,
    required this.onDismissed,
  });

  /// Current WPM value to display (from notifier state).
  final int wpm;

  /// Whether the dial is visible (from notifier state).
  final bool visible;

  /// Called on drag to update WPM via notifier.
  final ValueChanged<int> onWpmChanged;

  /// Called when user taps outside the dial to dismiss immediately.
  final VoidCallback onDismissed;

  @override
  State<WpmDial3D> createState() => _WpmDial3DState();
}

class _WpmDial3DState extends State<WpmDial3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _emergeController;
  late final Animation<double> _emergeAnimation;

  /// Tracks last WPM to detect 25-step boundary crossings for haptic.
  int _lastHapticWpm = 0;

  /// Unsnapped WPM accumulator — preserves fractional progress between
  /// 25-step boundaries so small drag deltas are not lost.
  double _rawWpmAccumulator = 0;

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
    // Handle initial visible:true (State might be freshly created)
    if (widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _show();
      });
    }
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
    _lastHapticWpm = widget.wpm;
    _rawWpmAccumulator = widget.wpm.toDouble();
    final reducedMotion = isReducedMotion(context);
    if (reducedMotion) {
      _emergeController.value = 1.0;
    } else {
      _emergeController.animateWith(SpeedyBoyAnimations.dialEmergeSimulation());
    }
  }

  void _hide() {
    final reducedMotion = isReducedMotion(context);
    if (reducedMotion) {
      _emergeController.value = 0.0;
    } else {
      // P2 Grade C — fade out over 200ms on dismiss
      _emergeController.animateTo(
        0.0,
        duration: const Duration(milliseconds: SpeedyBoyTiming.wpmDialFadeMs),
        curve: SpeedyBoyAnimations.dialDismissCurve,
      );
    }
  }

  @override
  void dispose() {
    _emergeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _emergeAnimation,
      builder: (context, child) {
        if (_emergeAnimation.value == 0) {
          return const SizedBox.shrink();
        }
        // P2 Grade C — 40% dim overlay behind dial
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismissed,
                child: ColoredBox(
                  color: SpeedyBoyTokens.stageDarkShadow.withValues(
                    alpha: 0.4 * _emergeAnimation.value,
                  ),
                ),
              ),
            ),
            Center(
              child: Opacity(
                opacity: _emergeAnimation.value,
                child: Transform.translate(
                  offset: Offset(0, 100 * (1 - _emergeAnimation.value)),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
      child: GestureDetector(
        onPanUpdate: (details) {
          // Vertical drag → WPM change (up = increase, down = decrease)
          // Accumulate raw delta to avoid losing fractional progress
          // between 25-step snap boundaries.
          _rawWpmAccumulator += -details.delta.dy;
          final rawWpm = _rawWpmAccumulator.round();
          widget.onWpmChanged(rawWpm);

          // P2 Grade C — haptic feedback per 25 WPM increment
          final snapped =
              (rawWpm / SpeedyBoyTiming.wpmDialStep).round() *
              SpeedyBoyTiming.wpmDialStep;
          if (snapped != _lastHapticWpm) {
            _lastHapticWpm = snapped;
            HapticFeedback.selectionClick();
          }
        },
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _DialPainter(
              wpm: widget.wpm,
              progress: (widget.wpm - 100) / (600 - 100),
            ),
            size: const Size(240, 240),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  // P9 Grade A — TextPainters initialized at construct time, not in paint().
  // shouldRepaint() only returns true when wpm/progress changes, so a fresh
  // instance (with fresh painters) is created only when the dial value changes.
  _DialPainter({required this.wpm, required this.progress})
    : _wpmPainter = TextPainter(
        text: TextSpan(text: '$wpm', style: SpeedyBoyTypography.badge),
        textDirection: TextDirection.ltr,
      )..layout(),
      _labelPainter = TextPainter(
        text: const TextSpan(text: 'WPM', style: SpeedyBoyTypography.caption),
        textDirection: TextDirection.ltr,
      )..layout();

  final int wpm;
  final double progress;

  final TextPainter _wpmPainter;
  final TextPainter _labelPainter;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;
    const ringWidth = 8.0;

    // ── Neumorphic shadow disc ──
    final shadowPaint = Paint()
      ..color = SpeedyBoyTokens.stageDarkShadow.withValues(alpha: 0.5)
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
    _wpmPainter.paint(
      canvas,
      Offset(
        center.dx - _wpmPainter.width / 2,
        center.dy - _wpmPainter.height / 2 - 6,
      ),
    );

    _labelPainter.paint(
      canvas,
      Offset(center.dx - _labelPainter.width / 2, center.dy + 8),
    );
  }

  @override
  bool shouldRepaint(_DialPainter oldDelegate) {
    return wpm != oldDelegate.wpm || progress != oldDelegate.progress;
  }
}
