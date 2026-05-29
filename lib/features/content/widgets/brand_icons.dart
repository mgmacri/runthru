/// Official source brand marks used by content connectors.
library;

import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';

/// Google Drive triangular brand mark.
class GoogleDriveBrandIcon extends StatelessWidget {
  /// Creates a Google Drive brand icon.
  const GoogleDriveBrandIcon({super.key, this.size = 22});

  /// Square icon size.
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _GoogleDriveBrandPainter(RunThruTokens.shellAccent),
    );
  }
}

/// Instapaper app mark.
class InstapaperBrandIcon extends StatelessWidget {
  /// Creates an Instapaper brand icon.
  const InstapaperBrandIcon({super.key, this.size = 22});

  /// Square icon size.
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _InstapaperBrandPainter(RunThruTokens.shellAccent),
    );
  }
}

class _GoogleDriveBrandPainter extends CustomPainter {
  const _GoogleDriveBrandPainter(this.color);

  final Color color;

  static const _shadow = Color(0x22000000);

  @override
  void paint(Canvas canvas, Size size) {
    final tones = _greenTones(color);
    final w = size.width;
    final h = size.height;
    final sx = w / 24;
    final sy = h / 24;

    Offset p(double x, double y) => Offset(x * sx, y * sy);

    final topBand = Path()
      ..moveTo(p(3.0, 11.5).dx, p(3.0, 11.5).dy)
      ..lineTo(p(7.6, 3.6).dx, p(7.6, 3.6).dy)
      ..cubicTo(
        p(8.9, 1.3).dx,
        p(8.9, 1.3).dy,
        p(15.1, 1.3).dx,
        p(15.1, 1.3).dy,
        p(16.4, 3.6).dx,
        p(16.4, 3.6).dy,
      )
      ..lineTo(p(21.0, 11.5).dx, p(21.0, 11.5).dy)
      ..lineTo(p(16.7, 11.5).dx, p(16.7, 11.5).dy)
      ..lineTo(p(7.3, 11.5).dx, p(7.3, 11.5).dy)
      ..close();

    final rightBand = Path()
      ..moveTo(p(16.7, 11.5).dx, p(16.7, 11.5).dy)
      ..lineTo(p(21.0, 11.5).dx, p(21.0, 11.5).dy)
      ..lineTo(p(22.8, 14.6).dx, p(22.8, 14.6).dy)
      ..cubicTo(
        p(24.0, 16.8).dx,
        p(24.0, 16.8).dy,
        p(20.7, 22.5).dx,
        p(20.7, 22.5).dy,
        p(18.1, 22.5).dx,
        p(18.1, 22.5).dy,
      )
      ..lineTo(p(13.6, 22.5).dx, p(13.6, 22.5).dy)
      ..lineTo(p(12.0, 19.0).dx, p(12.0, 19.0).dy)
      ..close();

    final leftBand = Path()
      ..moveTo(p(3.0, 11.5).dx, p(3.0, 11.5).dy)
      ..lineTo(p(7.3, 11.5).dx, p(7.3, 11.5).dy)
      ..lineTo(p(12.0, 19.0).dx, p(12.0, 19.0).dy)
      ..lineTo(p(13.6, 22.5).dx, p(13.6, 22.5).dy)
      ..lineTo(p(5.9, 22.5).dx, p(5.9, 22.5).dy)
      ..cubicTo(
        p(3.3, 22.5).dx,
        p(3.3, 22.5).dy,
        p(0.0, 16.8).dx,
        p(0.0, 16.8).dy,
        p(1.2, 14.6).dx,
        p(1.2, 14.6).dy,
      )
      ..close();

    canvas.save();
    canvas.translate(0, h * 0.015);
    for (final path in [topBand, rightBand, leftBand]) {
      canvas.drawPath(path, Paint()..color = _shadow);
    }
    canvas.restore();

    void draw(Path path, Color color) {
      canvas.drawPath(path, Paint()..color = color);
    }

    draw(leftBand, tones.light);
    draw(rightBand, tones.base);
    draw(topBand, tones.dark);
  }

  _DriveGreenTones _greenTones(Color baseColor) {
    final hsl = HSLColor.fromColor(baseColor);
    return _DriveGreenTones(
      dark: hsl
          .withLightness((hsl.lightness * 0.72).clamp(0.0, 1.0))
          .withSaturation((hsl.saturation * 1.04).clamp(0.0, 1.0))
          .toColor(),
      base: baseColor,
      light: hsl
          .withLightness((hsl.lightness + 0.18).clamp(0.0, 1.0))
          .withSaturation((hsl.saturation * 0.84).clamp(0.0, 1.0))
          .toColor(),
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleDriveBrandPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DriveGreenTones {
  const _DriveGreenTones({
    required this.dark,
    required this.base,
    required this.light,
  });

  final Color dark;
  final Color base;
  final Color light;
}

class _InstapaperBrandPainter extends CustomPainter {
  const _InstapaperBrandPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'I',
        style: TextStyle(
          color: color,
          fontSize: size.width * 0.78,
          fontWeight: FontWeight.w700,
          fontFamily: 'Georgia',
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2 - size.height * 0.02,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _InstapaperBrandPainter oldDelegate) =>
      oldDelegate.color != color;
}
