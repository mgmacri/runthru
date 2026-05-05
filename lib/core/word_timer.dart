import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/pacing/pacing_config.dart';
import 'package:runthru/features/reading/pacing/word_duration.dart';

/// State for the word timer.
class WordTimerState {
  const WordTimerState({
    this.currentIndex = 0,
    this.totalWords = 0,
    this.isPlaying = false,
    this.wpm = 300,
    this.pacingConfig = defaultPacingConfig,
    this.warmupProgress = 0.0,
    this.isWarmingUp = false,
  });

  final int currentIndex;
  final int totalWords;
  final bool isPlaying;
  final int wpm;

  /// Per-word adaptive pacing configuration.
  final PacingConfig pacingConfig;

  /// Warm-up progress from 0.0 (just started) to 1.0 (ramp complete).
  final double warmupProgress;

  /// Whether the warm-up ramp is currently active.
  final bool isWarmingUp;

  WordTimerState copyWith({
    int? currentIndex,
    int? totalWords,
    bool? isPlaying,
    int? wpm,
    PacingConfig? pacingConfig,
    double? warmupProgress,
    bool? isWarmingUp,
  }) {
    return WordTimerState(
      currentIndex: currentIndex ?? this.currentIndex,
      totalWords: totalWords ?? this.totalWords,
      isPlaying: isPlaying ?? this.isPlaying,
      wpm: wpm ?? this.wpm,
      pacingConfig: pacingConfig ?? this.pacingConfig,
      warmupProgress: warmupProgress ?? this.warmupProgress,
      isWarmingUp: isWarmingUp ?? this.isWarmingUp,
    );
  }

  /// Word interval in milliseconds.
  int get intervalMs => (60000 / wpm).round();

  /// Progress as 0.0..1.0.
  double get progress => totalWords > 0 ? currentIndex / totalWords : 0.0;

  /// Whether we've reached the end.
  bool get isFinished => totalWords > 0 && currentIndex >= totalWords - 1;
}

/// Duration of the warm-up ramp in milliseconds.
const int _warmupDurationMs = 10000;

/// Starting speed fraction (80% of target WPM = 1.25× interval).
const double _warmupStartFraction = 0.80;

/// Manages word-at-a-time timing with drift correction.
class WordTimerNotifier extends StateNotifier<WordTimerState> {
  WordTimerNotifier() : super(const WordTimerState());

  Timer? _timer;
  DateTime? _lastTick;
  bool _isFirstTick = false;

  // P18 Grade C — auto-rewind 3 words on resume from pause
  bool _wasPaused = false;
  bool _hasPlayedOnce = false;

  /// Word lookup callback for per-word adaptive pacing.
  String? Function(int index)? _wordAt;

  DateTime? _warmupStart;

  void loadDocument(int totalWords, {int startIndex = 0}) {
    _stopTimer();
    // P18 Grade C — reset auto-rewind flags on new document
    _wasPaused = false;
    _hasPlayedOnce = false;
    _wordAt = null;
    _warmupStart = null;
    state = WordTimerState(
      totalWords: totalWords,
      currentIndex: startIndex,
      pacingConfig: state.pacingConfig,
    );
  }

  /// Attaches a word lookup function for per-word adaptive pacing.
  ///
  /// Call after [loadDocument]. The callback returns the word at the given
  /// index, or null if out of bounds.
  void attachWordSource(String? Function(int index) wordAt) {
    _wordAt = wordAt;
  }

  void play() {
    if (state.isFinished || state.totalWords == 0) return;

    // Capture warmup-during-pause state BEFORE auto-rewind clears _wasPaused.
    final wasWarmupPaused =
        _wasPaused && state.warmupProgress < 1.0 && state.isWarmingUp;

    // P18 Grade C — silently rewind on resume from pause (not first play)
    if (_wasPaused && _hasPlayedOnce) {
      final rewindTarget = (state.currentIndex - RunThruTiming.autoRewindWords)
          .clamp(0, state.totalWords - 1);
      state = state.copyWith(currentIndex: rewindTarget);
      _wasPaused = false;
    }

    // Warm-up ramp logic
    if (!_hasPlayedOnce) {
      // First play — start warmup from scratch
      _warmupStart = clock.now();
      state = state.copyWith(isWarmingUp: true, warmupProgress: 0.0);
    } else if (wasWarmupPaused) {
      // Resume during warmup — adjust _warmupStart to account for elapsed
      // progress so the ramp continues from where it left off.
      final elapsedMs = (_warmupDurationMs * state.warmupProgress).round();
      _warmupStart = clock.now().subtract(Duration(milliseconds: elapsedMs));
    }

    _hasPlayedOnce = true;
    state = state.copyWith(isPlaying: true);
    _startTimer();
  }

  void pause() {
    _stopTimer();
    // P18 Grade C — mark as paused for auto-rewind on next resume
    _wasPaused = true;
    state = state.copyWith(isPlaying: false);
  }

  void togglePlayPause() {
    if (state.isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void setWpm(int wpm) {
    final clamped = wpm.clamp(30, 1000);
    state = state.copyWith(wpm: clamped);
    if (state.isPlaying) {
      _stopTimer();
      _startTimer();
    }
  }

  void seekTo(int index) {
    if (state.totalWords == 0) return;
    final clamped = index.clamp(0, state.totalWords - 1);
    state = state.copyWith(currentIndex: clamped);
  }

  // P20 Grade C — resume from ContextReveal without auto-rewind
  void resumeFromContextReveal(int wordIndex) {
    seekTo(wordIndex);
    // Skip auto-rewind by clearing the paused flag before play
    _wasPaused = false;
    play();
  }

  /// Seek to [sentenceStartIndex] and resume playing (if was playing).
  ///
  /// Skips auto-rewind — the user explicitly chose this position.
  // P4 Grade C — double-tap restarts sentence without auto-rewind
  void restartCurrentSentence(int sentenceStartIndex) {
    final wasPlaying = state.isPlaying;
    if (wasPlaying) _stopTimer();
    seekTo(sentenceStartIndex);
    _wasPaused = false;
    if (wasPlaying) play();
  }

  void _startTimer() {
    _lastTick = clock.now();
    _isFirstTick = true;
    _scheduleNext();
  }

  void _scheduleNext() {
    final base = state.intervalMs;
    final word = _wordAt?.call(state.currentIndex);
    final next = _wordAt?.call(state.currentIndex + 1);
    final interval = word == null
        ? base
        : durationForWord(
            word,
            nextWord: next,
            baseIntervalMs: base,
            config: state.pacingConfig,
          );

    // ── Warm-up ramp ──
    var adjustedInterval = interval;
    if (_warmupStart != null) {
      final elapsedMs = clock.now().difference(_warmupStart!).inMilliseconds;
      final progress = (elapsedMs / _warmupDurationMs).clamp(0.0, 1.0);

      if (progress < 1.0) {
        // Linear ramp: speedFraction goes from _warmupStartFraction to 1.0.
        // Interval multiplier is 1/speedFraction (slower speed = longer
        // interval).
        final speedFraction =
            _warmupStartFraction + (1.0 - _warmupStartFraction) * progress;
        adjustedInterval = (interval / speedFraction).round();
        state = state.copyWith(warmupProgress: progress, isWarmingUp: true);
      } else if (state.isWarmingUp) {
        // Warmup just completed.
        _warmupStart = null;
        state = state.copyWith(warmupProgress: 1.0, isWarmingUp: false);
      }
    }

    var delay = adjustedInterval;

    // Skip drift correction on the first tick after play/resume —
    // _lastTick was just set in _startTimer(), so elapsed ≈ 0 and
    // the raw formula would produce delay ≈ 2×interval.
    if (_isFirstTick) {
      _isFirstTick = false;
    } else if (_lastTick != null) {
      final now = clock.now();
      final elapsed = now.difference(_lastTick!).inMilliseconds;
      final drift = elapsed - adjustedInterval;
      delay = (adjustedInterval - drift).clamp(1, adjustedInterval * 2);
    }

    _timer = Timer(Duration(milliseconds: delay), _tick);
  }

  void _tick() {
    _lastTick = clock.now();

    if (state.currentIndex < state.totalWords - 1) {
      state = state.copyWith(currentIndex: state.currentIndex + 1);
      if (state.isPlaying && !state.isFinished) {
        _scheduleNext();
      } else {
        state = state.copyWith(isPlaying: false);
      }
    } else {
      state = state.copyWith(isPlaying: false);
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _lastTick = null;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}

final wordTimerProvider =
    StateNotifierProvider.autoDispose<WordTimerNotifier, WordTimerState>(
      (ref) => WordTimerNotifier(),
    );
