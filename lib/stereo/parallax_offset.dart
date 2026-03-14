import 'dart:ui';

import 'package:speedy_boy/stereo/models.dart';

/// Compute parallax offset for a layer at depth [z].
/// Uses the stereoscopic disparity formula: disparity = B * f / Z
///
/// [headPosition] — normalized head/pointer offset (from HeadPositionNotifier).
/// [parallaxFactor] — user-configurable intensity multiplier.
/// [z] — depth of this layer (higher = further back = less movement).
/// [baseline] — virtual inter-ocular distance (default 0.06).
/// [focalScale] — focal scale factor (default 1.0).
Offset parallaxOffset(
  Offset3D? headPosition, {
  double parallaxFactor = 1.0,
  double z = 1.0,
  double baseline = 0.06,
  double focalScale = 1.0,
}) {
  if (headPosition == null || parallaxFactor == 0 || z == 0) {
    return Offset.zero;
  }

  final disparity = (baseline * focalScale) / z;
  return Offset(
    headPosition.x * disparity * parallaxFactor,
    headPosition.y * disparity * parallaxFactor * 0.5,
  );
}
