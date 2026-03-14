import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Dynamic font size calculation for 3D word display.
/// Adapts to viewport size and device pixel ratio.
double dynamicFontSize(BoxConstraints constraints) {
  final width = constraints.maxWidth;
  final height = constraints.maxHeight;
  final shorter = math.min(width, height);

  // ~7% of width, clamped to readable range
  final calculated = shorter * 0.07;
  return calculated.clamp(24.0, 144.0);
}

/// Extrusion depth for pseudo-3D text effect.
double extrusionDepth(double fontSize) => fontSize * 0.08;
