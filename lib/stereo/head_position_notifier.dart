import 'package:flutter/foundation.dart';
import 'package:speedy_boy/stereo/models.dart';

/// Publishes smoothed head/pointer position via ValueNotifier.
/// Null means no tracking active.
class HeadPositionNotifier extends ValueNotifier<Offset3D?> {
  HeadPositionNotifier() : super(null);

  static const double _alpha = 0.15;
  static const double _deadZone = 3.0;

  Offset3D? _smoothed;

  /// Update from pointer position (normalized -1..1 from screen center).
  void updateFromPointer(double normalizedX, double normalizedY) {
    _updateRaw(Offset3D(normalizedX * 100, normalizedY * 100, 0));
  }

  /// Update from IMU/gyro sensor data.
  void updateFromSensor(double pitch, double yaw) {
    // Convert radians to a ±100 range roughly matching pointer scale
    _updateRaw(Offset3D(yaw * 50, pitch * 50, 0));
  }

  void _updateRaw(Offset3D raw) {
    if (_smoothed == null) {
      _smoothed = raw;
    } else {
      _smoothed = Offset3D(
        _alpha * raw.x + (1 - _alpha) * _smoothed!.x,
        _alpha * raw.y + (1 - _alpha) * _smoothed!.y,
        _alpha * raw.z + (1 - _alpha) * _smoothed!.z,
      );
    }

    final offset = _smoothed!;
    if (offset.x.abs() < _deadZone && offset.y.abs() < _deadZone) {
      value = Offset3D.zero;
    } else {
      value = offset;
    }
  }

  /// Clear tracking.
  void clearTracking() {
    _smoothed = null;
    value = null;
  }
}
