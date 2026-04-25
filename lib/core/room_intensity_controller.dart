import 'package:speedy_boy/design/design.dart';

/// Visual complexity level of the parallax room.
enum RoomIntensityLevel { minimal, moderate, rich }

/// Controls room visual intensity based on rolling sentence difficulty.
///
/// Uses a rolling window of recent sentence difficulty scores and
/// hysteresis to prevent rapid flickering between intensity levels.
class RoomIntensityController {
  /// Creates a controller with an optional injectable [clock] for testing.
  RoomIntensityController({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  // P7 Grade C — rolling window of recent sentence difficulties
  final List<double> _window = [];

  // P7 Grade C — current intensity level
  RoomIntensityLevel _level = RoomIntensityLevel.moderate;

  // P7 Grade C — hysteresis: timestamp of last intensity change
  DateTime? _lastTransition;

  /// Current room intensity level.
  RoomIntensityLevel get level => _level;

  /// Running average of difficulty scores in the window.
  /// Returns 0.5 when the window is empty.
  // P7 Grade C — default 0.5 when no data available
  double get smoothedDifficulty {
    if (_window.isEmpty) return 0.5;
    return _window.reduce((a, b) => a + b) / _window.length;
  }

  /// Number of sentences currently in the rolling window.
  int get windowSize => _window.length;

  /// Records a completed sentence's difficulty score and evaluates
  /// whether the room intensity should change.
  void onSentenceComplete(double sentenceDifficulty) {
    // P7 Grade C — rolling window of SpeedyBoyTiming.roomDifficultyWindowSize
    _window.add(sentenceDifficulty);
    if (_window.length > SpeedyBoyTiming.roomDifficultyWindowSize) {
      _window.removeAt(0);
    }

    _evaluate();
  }

  void _evaluate() {
    final avg = smoothedDifficulty;
    RoomIntensityLevel target;

    // P7 Grade D — tunable thresholds
    if (avg >= SpeedyBoyTiming.roomDifficultyThresholdHigh) {
      target = RoomIntensityLevel.minimal;
    } else if (avg <= SpeedyBoyTiming.roomDifficultyThresholdLow) {
      target = RoomIntensityLevel.rich;
    } else {
      target = RoomIntensityLevel.moderate;
    }

    if (target == _level) return;

    // P7 Grade C — hysteresis prevents rapid intensity flickering
    final now = _clock();
    if (_lastTransition != null) {
      final elapsed = now.difference(_lastTransition!).inSeconds;
      if (elapsed < SpeedyBoyTiming.roomHysteresisHoldSeconds) return;
    }

    _level = target;
    _lastTransition = now;
  }

  /// Resets all state to defaults.
  void reset() {
    _window.clear();
    _level = RoomIntensityLevel.moderate;
    _lastTransition = null;
  }
}
