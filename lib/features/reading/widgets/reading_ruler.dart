import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';

/// Two horizontal hairlines that flank the focal word zone, helping the
/// eye lock to the ORP column at speed.
class ReadingRuler extends StatelessWidget {
  const ReadingRuler({
    super.key,
    required this.visible,
    required this.viewportHeight,
  });

  final bool visible;
  final double viewportHeight;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    // Focal word sits at vertical center; hairlines flank a ~72px slot around it.
    const slotHeight = 72.0;
    final centerY = viewportHeight * 0.5;
    final topLine = centerY - slotHeight / 2;
    final bottomLine = centerY + slotHeight / 2;

    final duration = isReducedMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return Semantics(
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: duration,
        child: CustomPaint(
          size: Size(double.infinity, viewportHeight),
          painter: _RulerPainter(
            topLine: topLine,
            bottomLine: bottomLine,
            color: RunThruTokens.shellAccent.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter({
    required this.topLine,
    required this.bottomLine,
    required this.color,
  });

  final double topLine;
  final double bottomLine;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, topLine), Offset(size.width, topLine), paint);
    canvas.drawLine(
      Offset(0, bottomLine),
      Offset(size.width, bottomLine),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.topLine != topLine ||
      old.bottomLine != bottomLine ||
      old.color != color;
}
