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

  /// When the word now on screen is due to be replaced; null before the
  /// first word of a run is scheduled. A tick that fires late takes its
  /// lateness out of the next word, so the long-run rate is the set speed.
  DateTime? _dueAt;

  // P18 Grade C — auto-rewind 3 words on resume from pause
  bool _wasPaused = false;
  bool _hasPlayedOnce = false;

  /// Word lookup callback for per-word adaptive pacing.
  String? Function(int index)? _wordAt;

  /// Optional per-word difficulty multiplier from on-device model
  /// annotations (`modelAnnotations['difficultyPerWord']`). Ring 1 never
  /// calls a model — it only reads this hint when one was attached.
  double? Function(int index)? _difficultyAt;
  bool Function(int index)? _endsParagraphAt;

  DateTime? _warmupStart;

  void loadDocument(int totalWords, {int startIndex = 0}) {
    _stopTimer();
    // P18 Grade C — reset auto-rewind flags on new document
    _wasPaused = false;
    _hasPlayedOnce = false;
    _wordAt = null;
    _difficultyAt = null;
    _endsParagraphAt = null;
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

  /// Attaches a per-word difficulty multiplier source (edge AI hook).
  ///
  /// The callback returns a multiplier for the word at the given index
  /// (1.0 = neutral, >1.0 = dwell longer), or null when no annotation
  /// exists. Used only if attached — pacing is unchanged otherwise.
  void attachDifficultySource(double? Function(int index)? difficultyAt) {
    _difficultyAt = difficultyAt;
  }

  /// Attaches a lookup for where paragraphs end.
  ///
  /// Call after [loadDocument]. The callback says whether the word at the
  /// given index is the last of its paragraph; such a word is held as long
  /// as the end of a sentence, whatever its own punctuation. Without it
  /// pacing goes by each word's punctuation alone.
  void attachParagraphEnds(bool Function(int index)? endsParagraphAt) {
    _endsParagraphAt = endsParagraphAt;
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

  /// Sets the extra time long words, complex words and punctuation get (the
  /// reader's Word Pacing settings). The word on screen keeps its time; the
  /// next one uses [config].
  void setPacingConfig(PacingConfig config) {
    if (config == state.pacingConfig) return;
    state = state.copyWith(pacingConfig: config);
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
    _dueAt = null;
    _scheduleNext();
  }

  void _scheduleNext() {
    final base = state.intervalMs;
    final word = _wordAt?.call(state.currentIndex);
    final next = _wordAt?.call(state.currentIndex + 1);
    var interval = word == null
        ? base
        : durationForWord(
            word,
            nextWord: next,
            baseIntervalMs: base,
            config: state.pacingConfig,
            endsParagraph: _endsParagraphAt?.call(state.currentIndex) ?? false,
          );

    // Model-annotated difficulty override — applied only when present.
    final difficulty = _difficultyAt?.call(state.currentIndex);
    if (difficulty != null) {
      interval = (interval * difficulty.clamp(0.5, 3.0)).round();
    }

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

    // Drift correction: take out of this word however late the tick that
    // brought it up fired, but never more than half the word's time (one
    // long frame must not make a word flash by unread).
    //
    // This used to compare the time since the tick itself, which is always
    // about zero, with the whole interval. The "drift" was therefore minus
    // one interval on every word after the first, each word was shown for
    // twice its time, and the reader ran at half the speed it displayed
    // (125 words a minute at "250 WPM").
    final now = clock.now();
    var delay = adjustedInterval;
    final due = _dueAt;
    if (due != null) {
      final late = now.difference(due).inMilliseconds;
      if (late > 0) {
        delay = (adjustedInterval - late).clamp(
          (adjustedInterval / 2).ceil(),
          adjustedInterval,
        );
      }
    }
    _dueAt = now.add(Duration(milliseconds: delay));

    _timer = Timer(Duration(milliseconds: delay), _tick);
  }

  void _tick() {
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
    _dueAt = null;
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
