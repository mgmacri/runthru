import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/stereo/head_position_notifier.dart';

/// Calibration overlay showing pointer/head position on target grid.
class CalibrationOverlay extends StatelessWidget {
  const CalibrationOverlay({
    super.key,
    required this.headNotifier,
  });

  final HeadPositionNotifier headNotifier;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: SpeedyBoyTokens.shellBase,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Parallax Calibration',
              style: SpeedyBoyTypography.title,
            ),
            const SizedBox(height: 16),

            // Target grid with position dot
            SizedBox(
              width: 200,
              height: 200,
              child: ValueListenableBuilder(
                valueListenable: headNotifier,
                builder: (context, headPos, _) {
                  return CustomPaint(
                    painter: _CalibrationGridPainter(
                      headX: headPos?.x ?? 0,
                      headY: headPos?.y ?? 0,
                    ),
                    size: const Size(200, 200),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Move your mouse or tilt your device. '
              'The dot should follow your movement.',
              style: SpeedyBoyTypography.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: SpeedyBoyTokens.shellAccent,
                foregroundColor: SpeedyBoyTokens.stageText,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Done',
                style: SpeedyBoyTypography.body.copyWith(
                  color: SpeedyBoyTokens.stageText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalibrationGridPainter extends CustomPainter {
  _CalibrationGridPainter({
    required this.headX,
    required this.headY,
  });

  final double headX;
  final double headY;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final gridPaint = Paint()
      ..color = SpeedyBoyTokens.shellDarkShadow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Concentric circles
    for (var r = 25.0; r <= 100; r += 25) {
      canvas.drawCircle(center, r, gridPaint);
    }

    // Crosshair
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      gridPaint,
    );

    // Head position dot
    final dotPaint = Paint()
      ..color = SpeedyBoyTokens.stereoIndicator
      ..style = PaintingStyle.fill;
    final dotPos = Offset(
      center.dx + headX * 0.5,
      center.dy + headY * 0.5,
    );
    canvas.drawCircle(dotPos, 6, dotPaint);
  }

  @override
  bool shouldRepaint(_CalibrationGridPainter oldDelegate) {
    return headX != oldDelegate.headX || headY != oldDelegate.headY;
  }
}
