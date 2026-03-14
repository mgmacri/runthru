import 'package:flutter/widgets.dart';
import 'package:speedy_boy/stereo/head_position_notifier.dart';

/// Drives parallax from pointer (desktop) or device sensors (mobile).
/// No camera required — purely input-driven spatial effect.
class StereoscopicEngine {
  StereoscopicEngine();

  final HeadPositionNotifier headNotifier = HeadPositionNotifier();
  bool _active = false;

  bool get isActive => _active;

  /// Start tracking. On desktop, call [updateFromPointer] from
  /// a Listener widget. On mobile, hook up sensor streams.
  void start() {
    _active = true;
  }

  /// Update from a pointer hover/move event.
  /// [normalizedX] and [normalizedY] should be in the range -1..1
  /// relative to the widget center.
  void updateFromPointer(double normalizedX, double normalizedY) {
    if (!_active) return;
    headNotifier.updateFromPointer(normalizedX, normalizedY);
  }

  /// Update from device orientation/acceleration sensors.
  void updateFromSensor(double pitch, double yaw) {
    if (!_active) return;
    headNotifier.updateFromSensor(pitch, yaw);
  }

  /// Convenience: compute normalized coordinates from a pointer
  /// position and widget size.
  void handlePointerEvent(Offset localPosition, Size widgetSize) {
    if (!_active) return;
    final nx = (localPosition.dx / widgetSize.width) * 2 - 1;
    final ny = (localPosition.dy / widgetSize.height) * 2 - 1;
    headNotifier.updateFromPointer(nx, ny);
  }

  /// Stop tracking and reset.
  void stop() {
    _active = false;
    headNotifier.clearTracking();
  }

  void dispose() {
    stop();
  }
}
