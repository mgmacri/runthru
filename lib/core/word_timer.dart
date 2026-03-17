import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the word timer.
class WordTimerState {
  const WordTimerState({
    this.currentIndex = 0,
    this.totalWords = 0,
    this.isPlaying = false,
    this.wpm = 300,
  });

  final int currentIndex;
  final int totalWords;
  final bool isPlaying;
  final int wpm;

  WordTimerState copyWith({
    int? currentIndex,
    int? totalWords,
    bool? isPlaying,
    int? wpm,
  }) {
    return WordTimerState(
      currentIndex: currentIndex ?? this.currentIndex,
      totalWords: totalWords ?? this.totalWords,
      isPlaying: isPlaying ?? this.isPlaying,
      wpm: wpm ?? this.wpm,
    );
  }

  /// Word interval in milliseconds.
  int get intervalMs => (60000 / wpm).round();

  /// Progress as 0.0..1.0.
  double get progress => totalWords > 0 ? currentIndex / totalWords : 0.0;

  /// Whether we've reached the end.
  bool get isFinished => totalWords > 0 && currentIndex >= totalWords - 1;
}

/// Manages word-at-a-time timing with drift correction.
class WordTimerNotifier extends StateNotifier<WordTimerState> {
  WordTimerNotifier() : super(const WordTimerState());

  Timer? _timer;
  DateTime? _lastTick;
  bool _isFirstTick = false;

  void loadDocument(int totalWords, {int startIndex = 0}) {
    _stopTimer();
    state = WordTimerState(
      totalWords: totalWords,
      currentIndex: startIndex,
    );
  }

  void play() {
    if (state.isFinished || state.totalWords == 0) return;
    state = state.copyWith(isPlaying: true);
    _startTimer();
  }

  void pause() {
    _stopTimer();
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

  void _startTimer() {
    _lastTick = DateTime.now();
    _isFirstTick = true;
    _scheduleNext();
  }

  void _scheduleNext() {
    final interval = state.intervalMs;
    var delay = interval;

    // Skip drift correction on the first tick after play/resume —
    // _lastTick was just set in _startTimer(), so elapsed ≈ 0 and
    // the raw formula would produce delay ≈ 2×interval.
    if (_isFirstTick) {
      _isFirstTick = false;
    } else if (_lastTick != null) {
      final now = DateTime.now();
      final elapsed = now.difference(_lastTick!).inMilliseconds;
      final drift = elapsed - interval;
      delay = (interval - drift).clamp(1, interval * 2);
    }

    _timer = Timer(Duration(milliseconds: delay), _tick);
  }

  void _tick() {
    _lastTick = DateTime.now();

    if (state.currentIndex < state.totalWords - 1) {
      state = state.copyWith(
        currentIndex: state.currentIndex + 1,
      );
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
