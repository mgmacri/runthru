import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Computes cube geometry from viewport size.
class CubeGeometry {
  CubeGeometry(this.viewportSize);

  final Size viewportSize;

  /// Cube depth = min(W, H) * 0.6.
  double get depth => math.min(viewportSize.width, viewportSize.height) * 0.6;

  /// Focal length for perspective projection.
  double get focalLength => viewportSize.height * 1.5;

  /// Center of viewport.
  Offset get center => Offset(
        viewportSize.width / 2,
        viewportSize.height / 2,
      );

  /// Half-width/height for wall sizing.
  double get halfWidth => viewportSize.width / 2;
  double get halfHeight => viewportSize.height / 2;
}
