import 'package:flutter/material.dart';
import 'package:speedy_boy/design/tokens.dart';

/// 1dp progress hairline on the cube's top interior edge.
class ProgressHairline3D extends StatelessWidget {
  const ProgressHairline3D({
    super.key,
    required this.progress,
  });

  /// Progress as 0.0..1.0.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ProgressHairlinePainter(progress: progress),
        size: Size.infinite,
      ),
    );
  }
}

class _ProgressHairlinePainter extends CustomPainter {
  _ProgressHairlinePainter({required this.progress});

  final double progress;

  final Paint _paint = Paint()
    ..color = SpeedyBoyTokens.stageProgress
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width * progress.clamp(0.0, 1.0);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, 1),
      _paint,
    );
  }

  @override
  bool shouldRepaint(_ProgressHairlinePainter oldDelegate) {
    return progress != oldDelegate.progress;
  }
}
