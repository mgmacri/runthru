import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Dynamic font size calculation for 3D word display.
/// Adapts to viewport size and device pixel ratio.
double dynamicFontSize(BoxConstraints constraints) {
  final width = constraints.maxWidth;
  final height = constraints.maxHeight;
  final shorter = math.min(width, height);

  // ~20% of shorter dimension, clamped to readable range
  final calculated = shorter * 0.20;
  return calculated.clamp(28.0, 400.0);
}

/// Extrusion depth for pseudo-3D text effect.
double extrusionDepth(double fontSize) => fontSize * 0.08;
