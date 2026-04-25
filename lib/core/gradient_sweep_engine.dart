import 'dart:async';

/// Drives the gradient sweep highlight through displayed words in ContextReveal.
///
/// Interval is derived from the current WPM (60000 / wpm ms per word),
/// matching the RSVP reading speed. Call [updateWpm] when the user changes WPM.
/// Holds on the last word indefinitely (no loop, no auto-dismiss).
/// Navigation resets sweep to the new leftmost word.
// P17 Grade C — gradient sweep engine for ContextReveal
class GradientSweepEngine {
  GradientSweepEngine({this.onAdvance, int wpm = 300}) : _wpm = wpm;

  /// Called each time the sweep advances to the next word.
  final void Function()? onAdvance;

  Timer? _timer;
  bool _isPaused = false;
  int _wpm;

  bool get isRunning => _timer?.isActive ?? false;
  bool get isPaused => _isPaused;

  /// Interval per word in milliseconds, derived from current WPM.
  int get _intervalMs => (60000 / _wpm).round();

  /// Update the WPM. If currently running, restarts the timer at the new rate.
  void updateWpm(int wpm) {
    if (wpm == _wpm) return;
    _wpm = wpm;
    if (isRunning && !_isPaused) {
      // Restart with new interval
      stop();
      _isPaused = false;
      _startTimer();
    }
  }

  /// Start (or restart) the sweep timer.
  ///
  /// The timer fires every [_intervalMs] ms (derived from WPM).
  /// Each tick calls [onAdvance] unless paused.
  void start() {
    stop();
    _isPaused = false;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) {
      if (!_isPaused) {
        onAdvance?.call();
      }
    });
  }

  /// Pause the sweep. Timer keeps ticking but [onAdvance] is suppressed.
  void pause() {
    _isPaused = true;
  }

  /// Resume the sweep after a pause.
  void resume() {
    _isPaused = false;
  }

  /// Toggle between paused and running.
  void togglePause() {
    _isPaused = !_isPaused;
  }

  /// Reset the sweep (e.g. after window navigation). Restarts the timer.
  void reset() {
    start();
  }

  /// Stop and dispose the timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isPaused = false;
  }

  /// Clean up. Call when the engine is no longer needed.
  void dispose() {
    stop();
  }
}
