import 'package:flutter/widgets.dart';

/// Debug instrumentation measuring word-change → next frame.
/// Target: ≤16ms at 1000 WPM.
class LatencyProbe {
  LatencyProbe._();

  static final Stopwatch _stopwatch = Stopwatch();
  static double _lastLatencyMs = 0;

  /// Call when word changes (before frame).
  static void markWordChange() {
    _stopwatch.reset();
    _stopwatch.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stopwatch.stop();
      _lastLatencyMs = _stopwatch.elapsedMicroseconds / 1000.0;
    });
  }

  /// Last measured latency in milliseconds.
  static double get lastLatencyMs => _lastLatencyMs;
}
