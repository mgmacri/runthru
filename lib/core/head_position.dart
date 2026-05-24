/// Source of the head/viewer position estimate.
enum MotionSource {
  /// Gyroscope/accelerometer via sensors_plus.
  sensor,

  /// Mouse/pointer position on desktop.
  pointer,

  /// No sensor input; position is fixed at centre.
  static,
}

/// Normalised viewer/head position for off-axis parallax rendering.
///
/// [x] and [y] are in −1..1 range where (0,0) is the calibrated neutral.
class HeadPosition {
  const HeadPosition({
    required this.x,
    required this.y,
    required this.isAvailable,
    required this.isCalibrated,
    required this.source,
  });

  /// Horizontal viewer offset (−1 = left, +1 = right).
  final double x;

  /// Vertical viewer offset (−1 = top, +1 = bottom).
  final double y;

  /// Whether a live input source is active.
  final bool isAvailable;

  /// Whether the neutral calibration baseline has been captured.
  final bool isCalibrated;

  /// Where the position estimate comes from.
  final MotionSource source;

  /// Zero/neutral static position.
  static const zero = HeadPosition(
    x: 0,
    y: 0,
    isAvailable: false,
    isCalibrated: false,
    source: MotionSource.static,
  );

  HeadPosition copyWith({
    double? x,
    double? y,
    bool? isAvailable,
    bool? isCalibrated,
    MotionSource? source,
  }) {
    return HeadPosition(
      x: x ?? this.x,
      y: y ?? this.y,
      isAvailable: isAvailable ?? this.isAvailable,
      isCalibrated: isCalibrated ?? this.isCalibrated,
      source: source ?? this.source,
    );
  }
}
