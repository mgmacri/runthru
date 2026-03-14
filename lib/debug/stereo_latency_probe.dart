/// Debug instrumentation for stereoscopic latency.
/// Measures head-position-change → next CubeViewport repaint.
/// Target: ≤50ms.
class StereoLatencyProbe {
  StereoLatencyProbe._();

  static final Stopwatch _stopwatch = Stopwatch();
  static double _lastLatencyMs = 0;

  /// Call when head position changes.
  static void markHeadChange() {
    _stopwatch.reset();
    _stopwatch.start();
  }

  /// Call when CubeViewport repaints.
  static void markRepaint() {
    if (_stopwatch.isRunning) {
      _stopwatch.stop();
      _lastLatencyMs = _stopwatch.elapsedMicroseconds / 1000.0;
    }
  }

  /// Last measured latency in milliseconds.
  static double get lastLatencyMs => _lastLatencyMs;
}
