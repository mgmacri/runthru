/// Debug FPS counter measuring frame timing.
/// Target: ≥30fps sustained, ≥60fps flagship.
class FpsProbe {
  FpsProbe._();

  static int _frameCount = 0;
  static double _fps = 0;
  static DateTime _lastSample = DateTime.now();

  /// Call in a Ticker or per-frame callback.
  static void onFrame() {
    _frameCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastSample);
    if (elapsed.inMilliseconds >= 1000) {
      _fps = _frameCount * 1000.0 / elapsed.inMilliseconds;
      _frameCount = 0;
      _lastSample = now;
    }
  }

  /// Current FPS measurement.
  static double get fps => _fps;
}
