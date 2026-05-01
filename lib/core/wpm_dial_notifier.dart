import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/core/wpm_dial_state.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/store/config.dart';

/// Callback to pause/resume the reading engine when the dial is shown/hidden.
typedef ReadingPauseCallback = void Function(bool pause);

/// Riverpod StateNotifier for the WPM dial overlay.
///
/// Manages visibility, WPM value, and the inactivity auto-dismiss timer
/// (Rule 26 — 1.5s after last interaction → auto-dismiss and resume).
class WpmDialNotifier extends StateNotifier<WpmDialState> {
  WpmDialNotifier({
    required this.configNotifier,
    required this.onPauseChanged,
    Timer Function(Duration, void Function())? timerFactory,
  }) : _timerFactory = timerFactory ?? Timer.new,
       super(const WpmDialState());

  final ConfigNotifier configNotifier;
  final ReadingPauseCallback onPauseChanged;
  final Timer Function(Duration, void Function()) _timerFactory;

  Timer? _inactivityTimer;

  /// Show the dial at [position] with the current [wpm].
  /// Pauses reading immediately (Rule 26).
  void show(Offset position, int wpm) {
    _inactivityTimer?.cancel();
    state = WpmDialState(isVisible: true, currentWpm: wpm, position: position);
    onPauseChanged(true);
    _startInactivityTimer();
  }

  /// Update WPM from drag input. Clamps to [100, 600], snaps to 25-step
  /// increments (RunThruTiming.wpmDialStep), and resets the inactivity timer.
  void updateWpm(int wpm) {
    if (!state.isVisible) return;
    // P2 Grade C — snap to 25 WPM increments
    final snapped =
        (wpm / RunThruTiming.wpmDialStep).round() *
        RunThruTiming.wpmDialStep;
    final clamped = snapped.clamp(100, 600);
    state = state.copyWith(currentWpm: clamped);
    _startInactivityTimer();
  }

  /// Dismiss the dial, persist the final WPM, and resume reading.
  void dismiss() {
    if (!state.isVisible) return;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;

    final finalWpm = state.currentWpm;
    state = state.copyWith(isVisible: false);

    // Persist to AppConfig (fire-and-forget)
    configNotifier.setDefaultWpm(finalWpm);
    onPauseChanged(false);
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    // P2 Grade C — auto-dismiss after 1.5s inactivity
    _inactivityTimer = _timerFactory(
      const Duration(milliseconds: RunThruTiming.wpmDialInactivityMs),
      dismiss,
    );
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }
}

/// Auto-dispose provider for the WPM dial notifier.
///
/// Requires [configProvider] for persistence. Pause/resume is handled via
/// ref.listen<WpmDialState> in the reading screen's build(); the default
/// [onPauseChanged] in this factory is a no-op.
final wpmDialProvider =
    StateNotifierProvider.autoDispose<WpmDialNotifier, WpmDialState>((ref) {
      final configNotifier = ref.read(configProvider.notifier);
      return WpmDialNotifier(
        configNotifier: configNotifier,
        onPauseChanged: (_) {
          // Default no-op; overridden in reading screen via provider override.
        },
      );
    });
