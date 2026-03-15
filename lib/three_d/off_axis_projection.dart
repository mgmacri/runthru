import 'dart:ui';

/// A point in 3D room space (abstract units).
class Point3D {
  const Point3D(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  static const Point3D zero = Point3D(0, 0, 0);

  Point3D operator +(Point3D other) =>
      Point3D(x + other.x, y + other.y, z + other.z);

  Point3D operator -(Point3D other) =>
      Point3D(x - other.x, y - other.y, z - other.z);

  Point3D operator *(double factor) =>
      Point3D(x * factor, y * factor, z * factor);
}

/// Configuration for the 3D parallax room.
///
/// Uses abstract units with [unitScale] (pixels-per-unit). The near face
/// at Z=0 maps exactly to screen edges when head is at (0,0):
///   wRoom * unitScale = screenWidth / 2
///
/// Matches the Python reference: eyeDepth=10, roomDepth=30, unitScale=100.
class RoomConfig {
  /// Derive room geometry so the near face fills [screenSize] exactly.
  factory RoomConfig.fromScreen(Size screenSize,
      {double overdrawMargin = 0.2}) {
    const unitScale = 100.0;
    return RoomConfig(
      eyeDepth: 10.0,
      roomDepth: 12.0,
      wRoom: screenSize.width / (2.0 * unitScale),
      hRoom: screenSize.height / (2.0 * unitScale),
      unitScale: unitScale,
      gridSpacing: 2.0,
      textDepthFraction: 0.15,
      overdrawMargin: overdrawMargin,
    );
  }

  const RoomConfig({
    this.eyeDepth = 10.0,
    this.roomDepth = 12.0,
    this.wRoom = 6.4,
    this.hRoom = 3.6,
    this.unitScale = 100.0,
    this.gridSpacing = 2.0,
    this.textDepthFraction = 0.15,
    this.overdrawMargin = 0.2,
  });

  /// Distance from eye to screen plane (abstract units).
  final double eyeDepth;

  /// Depth of the room along Z axis (abstract units).
  final double roomDepth;

  /// Room half-width (abstract units).
  final double wRoom;

  /// Room half-height (abstract units).
  final double hRoom;

  /// Pixels per abstract unit.
  final double unitScale;

  /// Spacing between grid lines (abstract units).
  final double gridSpacing;

  /// Fraction of roomDepth where text floats (0 = near, 1 = far).
  final double textDepthFraction;

  /// Extra margin beyond screen edges for wall geometry.
  final double overdrawMargin;

  /// Z coordinate where text is displayed.
  double get textZ => roomDepth * textDepthFraction;

  /// Padded half-width including overdraw margin.
  double get wRoomPadded => wRoom * (1.0 + overdrawMargin);

  /// Padded half-height including overdraw margin.
  double get hRoomPadded => hRoom * (1.0 + overdrawMargin);
}

/// Off-axis perspective projection matching the Python reference exactly.
///
/// [headX] and [headY] are in abstract room units (same as point coords).
/// +Y = up in room space, flipped to screen coords internally.
///
/// Returns projected screen-space [Offset], or null if behind the eye.
Offset? projectOffAxis(
  Point3D point, {
  required double headX,
  required double headY,
  required RoomConfig config,
  required double screenWidth,
  required double screenHeight,
}) {
  final totalDepth = config.eyeDepth + point.z;
  if (totalDepth <= 0.1) return null;

  final ratio = config.eyeDepth / totalDepth;

  // Off-axis projection (headX/headY already in abstract units)
  final projX = headX + (point.x - headX) * ratio;
  final projY = headY + (point.y - headY) * ratio;

  // Map to screen pixels: +X = right, +Y = up → Y flipped for screen
  final pixelX = screenWidth / 2.0 + projX * config.unitScale;
  final pixelY = screenHeight / 2.0 - projY * config.unitScale;

  return Offset(pixelX, pixelY);
}
