import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speedy_boy/core/clipboard_document.dart';
import 'package:speedy_boy/core/context_reveal_notifier.dart';
import 'package:speedy_boy/core/context_reveal_state.dart';
import 'package:speedy_boy/core/dynamic_font_size.dart';
import 'package:speedy_boy/core/gesture_classifier.dart';
import 'package:speedy_boy/core/gradient_sweep_engine.dart';
import 'package:speedy_boy/core/hint_controller.dart';
import 'package:speedy_boy/core/logger.dart';
import 'package:speedy_boy/core/reading_goal_presets.dart';
import 'package:speedy_boy/core/reading_range_resolver.dart';
import 'package:speedy_boy/core/sentence_resolver.dart';
import 'package:speedy_boy/core/word_timer.dart';
import 'package:speedy_boy/core/wpm_dial_notifier.dart';
import 'package:speedy_boy/core/wpm_dial_state.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/hooks/bookmark_notifier.dart';
import 'package:speedy_boy/services/analytics_service.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/services/preprocessing_queue.dart';
import 'package:speedy_boy/store/analytics_models.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';
import 'package:speedy_boy/three_d/parallax_room.dart';
import 'package:speedy_boy/three_d/text_painter_pool.dart';
import 'package:speedy_boy/three_d/word_painter.dart';
import 'package:speedy_boy/widgets/context_reveal_overlay.dart';
import 'package:speedy_boy/widgets/finished_range_overlay.dart';
import 'package:speedy_boy/widgets/hint_overlay.dart';
import 'package:speedy_boy/widgets/pause_fog_3d.dart';
import 'package:speedy_boy/widgets/progress_hairline_3d.dart';
import 'package:speedy_boy/widgets/reading_goal_presets.dart';
import 'package:speedy_boy/widgets/wpm_dial_3d.dart';
import 'package:window_manager/window_manager.dart';

class ParallaxReadingScreen extends ConsumerStatefulWidget {
  const ParallaxReadingScreen({
    super.key,
    required this.filePath,
    this.clipboardDocument,
  });

  final String filePath;

  /// Optional clipboard document (Rule 28 — ephemeral, session-only).
  final ClipboardDocument? clipboardDocument;

  @override
  ConsumerState<ParallaxReadingScreen> createState() =>
      _ParallaxReadingScreenState();
}

class _ParallaxReadingScreenState extends ConsumerState<ParallaxReadingScreen>
    with WidgetsBindingObserver {
  final ValueNotifier<String> _wordNotifier = ValueNotifier('');
  final FocusNode _focusNode = FocusNode();
  List<String> _words = [];
  List<String> _allDocWords = [];
  int _wordAdvanceCount = 0;

  /// Offset of the current word slice in the global word stream.
  int _sliceOffset = 0;

  /// Active reading range, if any.
  ReadingRange? _readingRange;

  /// Whether the user has completed the reading range.
  bool _isRangeComplete = false;

  /// The full extracted document (kept for "Continue Reading" past range end).
  ExtractedDocument? _fullDoc;

  bool _isFullScreen = false;
  bool _showReadingGoalOnboarding = false;

  // ── ContextReveal ──
  late final GradientSweepEngine _sweepEngine;
  bool _showCROnboarding = false;

  // ── Onboarding Hints (Rule 27) ──
  late final HintController _hintController;
  HintInfo? _activeHint;
  bool _hasPausedOnce = false;
  bool _hasNavigatedSentence = false;

  // ── Gesture tracking ──
  Offset? _panStart;
  Offset? _panLast;
  DateTime? _panStartTime;

  /// Brief flash on double-tap sentence restart (200ms).
  bool _showRestartFlash = false;
  Timer? _restartFlashTimer;

  // ── Analytics session tracking ──
  DateTime? _sessionStart;
  int _sessionWordCount = 0;

  /// Cached reference for safe use in dispose().
  late final PreprocessingQueue _queue;

  /// Cached analytics service for safe use in dispose().
  late final AnalyticsService _analyticsService;

  /// TextPainter pool for the flat 2D word painter (None intensity).
  // P7 Grade C — reused pool avoids paint()-time allocation (Rule 9)
  final TextPainterPool _flatPainterPool = TextPainterPool();

  /// Whether this is an ephemeral clipboard reading session (Rule 28).
  bool get _isClipboard => widget.clipboardDocument != null;

  static bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  @override
  void initState() {
    super.initState();
    _queue = ref.read(preprocessingQueueProvider.notifier);
    _analyticsService = ref.read(analyticsServiceProvider);
    final initWpm =
        (ref.read(configProvider).valueOrNull ?? const AppConfig()).defaultWpm;
    _sweepEngine = GradientSweepEngine(
      onAdvance: _onSweepAdvance,
      wpm: initWpm,
    );
    _hintController = HintController(
      configNotifier: ref.read(configProvider.notifier),
    );
    _hintController.onLongPressHintTimerFired = _showLongPressHint;
    appLog('ParallaxReadingScreen', 'initState filePath=${widget.filePath}');
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (_isDesktop) _enterDesktopFullScreen();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      appLog('ParallaxReadingScreen', 'post-frame: loading document');
      if (_isClipboard) {
        _initClipboardReading();
      } else {
        _initReading();
      }
    });
  }

  @override
  void dispose() {
    _endAnalyticsSession();
    _restartFlashTimer?.cancel();
    _sentenceGapTimer?.cancel();
    _hintController.dispose();
    _wordNotifier.dispose();
    _focusNode.dispose();
    _flatPainterPool.dispose();
    _sweepEngine.dispose();
    _queue.resumeBackground();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_isDesktop && _isFullScreen) windowManager.setFullScreen(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _endAnalyticsSession() {
    if (_sessionStart == null || _sessionWordCount <= 0) return;
    final duration = DateTime.now().difference(_sessionStart!);
    if (duration.inSeconds < 1) return;

    final minutes = duration.inMilliseconds / 60000.0;
    final avgWpm = minutes > 0 ? _sessionWordCount / minutes : 0.0;

    final session = ReadingSession(
      startTime: _sessionStart!,
      endTime: DateTime.now(),
      wordsRead: _sessionWordCount,
      avgWpm: avgWpm,
      filePath: widget.filePath,
    );
    _sessionStart = null;
    _sessionWordCount = 0;

    // Fire-and-forget — don't block dispose.
    // Use cached reference since ref may be invalid during dispose().
    _analyticsService.saveSession(session);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _endAnalyticsSession();
      if (!_isClipboard) {
        ref.read(bookmarkProvider(widget.filePath).notifier).save();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (ref.read(wordTimerProvider).isPlaying) {
        _sessionStart = DateTime.now();
        _sessionWordCount = 0;
      }
    }
  }

  Future<void> _enterDesktopFullScreen() async {
    await windowManager.ensureInitialized();
    await windowManager.setFullScreen(true);
    setState(() => _isFullScreen = true);
  }

  Future<void> _exitDesktopFullScreen() async {
    await windowManager.setFullScreen(false);
    setState(() => _isFullScreen = false);
  }

  Future<void> _initReading() async {
    appLog('ParallaxReadingScreen', '_initReading() start');
    final queue = ref.read(preprocessingQueueProvider.notifier);
    await queue.prioritize(widget.filePath);

    final processed = ref.read(preprocessingQueueProvider);
    final entry = processed[widget.filePath];
    appLog(
      'ParallaxReadingScreen',
      'after prioritize: status=${entry?.status} hasDoc=${entry?.document != null}',
    );

    if (entry?.document != null) {
      _loadDocument(entry!.document!);
    } else {
      appLog(
        'ParallaxReadingScreen',
        'WARN: document null — words never load. entry=$entry',
      );
    }
  }

  /// Initialize reading from a clipboard document (Rule 28 — ephemeral).
  /// Skips the preprocessing queue and loads the document directly.
  void _initClipboardReading() {
    final clipDoc = widget.clipboardDocument;
    if (clipDoc == null || clipDoc.words.isEmpty) {
      appLog('ParallaxReadingScreen', 'WARN: clipboard document empty');
      return;
    }
    appLog(
      'ParallaxReadingScreen',
      '_initClipboardReading: ${clipDoc.words.length} words',
    );
    _loadClipboardDocument(clipDoc.document);
  }

  /// Load a clipboard [ExtractedDocument] — no bookmarks, no range.
  void _loadClipboardDocument(ExtractedDocument doc) {
    _fullDoc = doc;
    _allDocWords = doc.allWords;
    _words = _allDocWords;
    _sliceOffset = 0;
    _readingRange = null;

    _wordNotifier.value = _words.first;

    final config = ref.read(configProvider).valueOrNull ?? const AppConfig();
    final timer = ref.read(wordTimerProvider.notifier);
    timer.loadDocument(_words.length, startIndex: 0);
    timer.setWpm(config.defaultWpm);
    _sessionStart = DateTime.now();
    _sessionWordCount = 0;
    timer.play();
    appLog(
      'ParallaxReadingScreen',
      'clipboard timer.play() wpm=${config.defaultWpm}',
    );
  }

  void _loadDocument(ExtractedDocument doc) {
    _fullDoc = doc;
    _allDocWords = doc.allWords;
    appLog(
      'ParallaxReadingScreen',
      '_loadDocument: totalWords=${_allDocWords.length}',
    );

    if (_allDocWords.isEmpty) {
      appLog('ParallaxReadingScreen', 'WARN: allWords is empty');
      return;
    }

    final config = ref.read(configProvider).valueOrNull ?? const AppConfig();
    final bookmark = config.bookmarks[widget.filePath];
    final range = bookmark?.readingRange;

    if (range != null && doc.hasPageBoundaries) {
      // Resolve the range to global indices.
      final resolved = resolveAndValidateRange(
        range,
        doc.pageBoundaries,
        _allDocWords,
      );
      if (resolved != null) {
        _readingRange = resolved;
        final rangeStart = resolved.resolvedStartWordIndex;
        final rangeEnd = resolved.resolvedEndWordIndex.clamp(
          0,
          _allDocWords.length - 1,
        );
        _sliceOffset = rangeStart;
        _words = _allDocWords.sublist(rangeStart, rangeEnd + 1);

        // Compute start index within the slice.
        final lastPosition = bookmark?.wordIndex ?? 0;
        int startIndex;
        if (lastPosition <= rangeStart) {
          startIndex = 0;
        } else if (lastPosition >= rangeEnd) {
          // Finished range — show overlay.
          startIndex = _words.length - 1;
          _isRangeComplete = true;
        } else {
          // Resume within slice — resolve sentence boundary.
          final globalResume = resumeIndex(bookmark!, doc);
          startIndex = (globalResume - rangeStart).clamp(0, _words.length - 1);
        }

        appLog(
          'ParallaxReadingScreen',
          'range: $rangeStart-$rangeEnd, sliceLen=${_words.length}, startIdx=$startIndex',
        );

        _wordNotifier.value = _words[startIndex.clamp(0, _words.length - 1)];
        final timer = ref.read(wordTimerProvider.notifier);
        timer.loadDocument(_words.length, startIndex: startIndex);
        timer.setWpm(config.defaultWpm);

        if (_isRangeComplete) {
          timer.pause();
        } else {
          _sessionStart = DateTime.now();
          _sessionWordCount = 0;
          timer.play();
        }
        appLog(
          'ParallaxReadingScreen',
          'timer loaded with range slice, wpm=${config.defaultWpm}',
        );
        return;
      }
    }

    // No range — full document.
    _words = _allDocWords;
    _sliceOffset = 0;
    _readingRange = null;

    final startIndex = bookmark != null ? resumeIndex(bookmark, doc) : 0;
    appLog('ParallaxReadingScreen', 'startIndex=$startIndex');

    _wordNotifier.value = _words[startIndex.clamp(0, _words.length - 1)];
    appLog(
      'ParallaxReadingScreen',
      'wordNotifier seeded: "${_wordNotifier.value}"',
    );

    final timer = ref.read(wordTimerProvider.notifier);
    timer.loadDocument(_words.length, startIndex: startIndex);
    timer.setWpm(config.defaultWpm);
    _sessionStart = DateTime.now();
    _sessionWordCount = 0;

    // P8 Grade B — show reading goal onboarding once before first session
    if (!config.hasSeenReadingGoalOnboarding) {
      timer.pause();
      setState(() => _showReadingGoalOnboarding = true);
    } else {
      timer.play();
    }
    appLog('ParallaxReadingScreen', 'timer.play() wpm=${config.defaultWpm}');
  }

  void _togglePause() {
    appLog('gestures', 'detected: tap');
    // P20 — tap during ContextReveal toggles sweep pause, not RSVP
    final crState = ref.read(contextRevealProvider);
    if (crState.isActive) {
      ref.read(contextRevealProvider.notifier).toggleSweepPause();
      if (crState.isSweepPaused) {
        _sweepEngine.resume();
      } else {
        _sweepEngine.pause();
      }
      return;
    }
    final timer = ref.read(wordTimerProvider.notifier);
    if (ref.read(wordTimerProvider).isPlaying) {
      timer.pause();
      if (!_isClipboard) {
        ref.read(bookmarkProvider(widget.filePath).notifier).save();
      }
      _endAnalyticsSession();
      // P27 — show swipe-lr hint on first pause
      if (!_hasPausedOnce) {
        _hasPausedOnce = true;
        _tryShowHint(HintId.swipeLr);
      }
    } else {
      _sessionStart = DateTime.now();
      _sessionWordCount = 0;
      timer.play();
    }
  }

  // P4 Grade C — double-tap restarts current sentence
  void _handleDoubleTap() {
    appLog('gestures', 'detected: doubleTap');

    final crState = ref.read(contextRevealProvider);
    if (crState.isActive) {
      // Sentence view: restart sweep from first word
      ref.read(contextRevealProvider.notifier).resetSweep();
      _sweepEngine.reset();
      _sweepEngine.start();
      appLog('gestures', 'action: doubleTap → restart sweep');
      return;
    }

    // RSVP mode: restart current sentence
    if (_fullDoc == null) return;
    final globalIdx = _currentGlobalIndex;
    var cumulative = 0;
    int previousSentenceStart = 0;

    for (final sentence in _fullDoc!.sentences) {
      final sentenceEnd = cumulative + sentence.words.length;
      if (globalIdx < sentenceEnd) {
        // If already at sentence start, seek to previous sentence.
        final targetGlobal = globalIdx == cumulative
            ? previousSentenceStart
            : cumulative;
        final localTarget = (targetGlobal - _sliceOffset).clamp(
          0,
          _words.length - 1,
        );
        ref
            .read(wordTimerProvider.notifier)
            .restartCurrentSentence(localTarget);
        _flashRestartHighlight();
        appLog(
          'gestures',
          'action: doubleTap → restart sentence at word $targetGlobal',
        );
        return;
      }
      previousSentenceStart = cumulative;
      cumulative = sentenceEnd;
    }
  }

  /// Brief anchor highlight flash to confirm sentence restart.
  // P4 Grade C — 200ms flash using SpeedyBoyTiming.restartHighlightMs
  void _flashRestartHighlight() {
    _restartFlashTimer?.cancel();
    setState(() => _showRestartFlash = true);
    _restartFlashTimer = Timer(
      const Duration(milliseconds: SpeedyBoyTiming.restartHighlightMs),
      () {
        if (mounted) setState(() => _showRestartFlash = false);
      },
    );
  }

  // ── Hint trigger helpers (Rule 27) ──

  /// Show a hint if it hasn't been shown before. Does nothing if another
  /// hint is already active or if the word timer is actively advancing
  /// (hints don't interrupt word display).
  void _tryShowHint(String hintId) {
    if (_activeHint != null) return;
    final hint = _hintController.check(hintId);
    if (hint != null) {
      setState(() => _activeHint = hint);
    }
  }

  void _dismissActiveHint() {
    final hint = _activeHint;
    if (hint == null) return;
    _hintController.markShown(hint.id);
    setState(() => _activeHint = null);
  }

  void _showLongPressHint() {
    if (!mounted) return;
    _tryShowHint(HintId.longPress);
  }

  /// Extends reading past the original range end to the end of the document.
  void _continueReadingPastRange() {
    if (_fullDoc == null || _readingRange == null) return;

    final rangeEnd = _readingRange!.resolvedEndWordIndex;
    final remaining = _allDocWords.sublist(rangeEnd + 1);
    if (remaining.isEmpty) return;

    _endAnalyticsSession();

    setState(() {
      _isRangeComplete = false;
      _words = remaining;
      _sliceOffset = rangeEnd + 1;
    });

    _wordNotifier.value = _words.first;
    final timer = ref.read(wordTimerProvider.notifier);
    timer.loadDocument(_words.length, startIndex: 0);
    _sessionStart = DateTime.now();
    _sessionWordCount = 0;
    timer.play();
  }

  void _toggleFullScreen() {
    if (_isDesktop) {
      if (_isFullScreen) {
        _exitDesktopFullScreen();
      } else {
        _enterDesktopFullScreen();
      }
    } else {
      setState(() => _isFullScreen = !_isFullScreen);
      SystemChrome.setEnabledSystemUIMode(
        _isFullScreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
  }

  void _goBack() {
    if (!mounted) return;
    // Dismiss ContextReveal if active before navigating away.
    final crState = ref.read(contextRevealProvider);
    if (crState.isActive) {
      ref.read(contextRevealProvider.notifier).dismiss();
      _sentenceGapTimer?.cancel();
      _sweepEngine.stop();
    }
    if (!_isClipboard) {
      ref.read(bookmarkProvider(widget.filePath).notifier).save();
    }
    ref.read(wordTimerProvider.notifier).pause();
    if (mounted) context.pop();
  }

  // ── ContextReveal gesture handlers ──

  /// Current global word index from the timer.
  int get _currentGlobalIndex {
    final localIdx = ref.read(wordTimerProvider).currentIndex;
    return _sliceOffset + localIdx;
  }

  /// Extract visible words for the current CR tier + window.
  List<String> _contextRevealWords() {
    final crState = ref.read(contextRevealProvider);
    if (!crState.isActive) return [];

    final leftmost = crState.resumeWordIndex;
    final tier = crState.tier;

    if (tier == ContextRevealTier.sentence) {
      return _sentenceWordsAt(leftmost);
    }

    final count = tier.wordCount;
    final half = count ~/ 2;
    final start = (leftmost - half).clamp(0, _allDocWords.length - 1);
    final end = (start + count).clamp(0, _allDocWords.length);
    return _allDocWords.sublist(start, end);
  }

  /// Get all words in the sentence containing [globalIndex].
  List<String> _sentenceWordsAt(int globalIndex) {
    if (_fullDoc == null) return [];
    var cumulative = 0;
    for (final sentence in _fullDoc!.sentences) {
      final sentenceEnd = cumulative + sentence.words.length;
      if (globalIndex < sentenceEnd) {
        return sentence.words;
      }
      cumulative = sentenceEnd;
    }
    // Past end — return last sentence
    return _fullDoc!.sentences.isNotEmpty ? _fullDoc!.sentences.last.words : [];
  }

  /// Get the global start index of the sentence containing [globalIndex].
  int _sentenceStartAt(int globalIndex) {
    if (_fullDoc == null) return globalIndex;
    var cumulative = 0;
    for (final sentence in _fullDoc!.sentences) {
      final sentenceEnd = cumulative + sentence.words.length;
      if (globalIndex < sentenceEnd) return cumulative;
      cumulative = sentenceEnd;
    }
    // Past end — return start of last sentence
    if (_fullDoc!.sentences.isNotEmpty) {
      return cumulative - _fullDoc!.sentences.last.words.length;
    }
    return globalIndex;
  }

  void _onSwipeUp() {
    final crState = ref.read(contextRevealProvider);
    if (!crState.isActive) {
      appLog('gestures', 'action: swipeUp → entering ContextReveal');
      // P20 — Enter ContextReveal — pause RSVP immediately
      ref.read(wordTimerProvider.notifier).pause();

      // v4 — show onboarding hint once before entering CR
      final config = ref.read(configProvider).valueOrNull ?? const AppConfig();
      if (!config.shownHints.contains('hint_swipe_up')) {
        setState(() => _showCROnboarding = true);
        // Auto-dismiss after 3 seconds, then enter CR
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _showCROnboarding) {
            _dismissCROnboarding();
          }
        });
        return;
      }

      ref
          .read(contextRevealProvider.notifier)
          .enterSentence(_currentGlobalIndex);
      _sweepEngine.start();
    } else {
      // P1 Grade C — elastic jiggle ceiling feedback
      appLog('gestures', 'action: swipeUp → jiggle (already in sentence view)');
      ref.read(contextRevealProvider.notifier).triggerJiggle();
    }
  }

  // v4 — dismiss CR onboarding, mark hint shown, then enter CR
  void _dismissCROnboarding() {
    setState(() => _showCROnboarding = false);
    ref.read(configProvider.notifier).markHintShown('hint_swipe_up');
    ref.read(contextRevealProvider.notifier).enterSentence(_currentGlobalIndex);
    _sweepEngine.start();
  }

  void _onSwipeDown() {
    final crState = ref.read(contextRevealProvider);
    if (!crState.isActive) {
      appLog('gestures', 'action: swipeDown → CR not active, ignoring');
      return;
    }
    appLog('gestures', 'action: swipeDown → dismissing ContextReveal');

    // Compute the global index of the currently highlighted word (sweep
    // position within the visible sentence) so RSVP resumes at that word.
    final sweepPos = crState.sweepPosition;
    final sentenceStartGlobal = _sentenceStartAt(crState.resumeWordIndex);
    final resumeGlobal = sentenceStartGlobal + sweepPos;

    ref.read(contextRevealProvider.notifier).dismiss();
    _sentenceGapTimer?.cancel();
    _sweepEngine.stop();
    final localIndex = (resumeGlobal - _sliceOffset).clamp(
      0,
      _words.length - 1,
    );
    ref.read(wordTimerProvider.notifier).resumeFromContextReveal(localIndex);
  }

  void _onSwipeLeft() {
    final crState = ref.read(contextRevealProvider);
    if (crState.isActive) {
      // v4 — sentence mode: navigate to next sentence
      if (_fullDoc == null) return;
      final currentStart = _sentenceStartAt(crState.resumeWordIndex);
      final sentenceWords = _sentenceWordsAt(currentStart);
      final nextStart = currentStart + sentenceWords.length;
      if (nextStart < _allDocWords.length) {
        _sentenceGapTimer?.cancel();
        ref.read(contextRevealProvider.notifier).enterSentence(nextStart);
        _sweepEngine.reset();
        _sweepEngine.start();
        appLog(
          'gestures',
          'action: swipeLeft → next sentence at word $nextStart',
        );
      } else {
        appLog('gestures', 'action: swipeLeft → already at last sentence');
      }
    } else {
      // v4 — RSVP mode: navigate to next sentence
      _seekToNextSentence();
      // P27 — show double-tap hint after first sentence navigation
      if (!_hasNavigatedSentence) {
        _hasNavigatedSentence = true;
        _tryShowHint(HintId.doubleTap);
      }
    }
  }

  void _onSwipeRight() {
    final crState = ref.read(contextRevealProvider);
    if (crState.isActive) {
      // v4 — sentence mode: navigate to previous sentence
      if (_fullDoc == null) return;
      final currentStart = _sentenceStartAt(crState.resumeWordIndex);
      if (currentStart > 0) {
        _sentenceGapTimer?.cancel();
        final prevStart = _sentenceStartAt(currentStart - 1);
        ref.read(contextRevealProvider.notifier).enterSentence(prevStart);
        _sweepEngine.reset();
        _sweepEngine.start();
        appLog(
          'gestures',
          'action: swipeRight → previous sentence at word $prevStart',
        );
      } else {
        appLog('gestures', 'action: swipeRight → already at first sentence');
      }
    } else {
      // v4 — RSVP mode: navigate to previous sentence
      _seekToPreviousSentence();
      // P27 — show double-tap hint after first sentence navigation
      if (!_hasNavigatedSentence) {
        _hasNavigatedSentence = true;
        _tryShowHint(HintId.doubleTap);
      }
    }
  }

  /// Navigate to the first word of the next sentence (RSVP mode).
  void _seekToNextSentence() {
    if (_fullDoc == null) return;
    final globalIdx = _currentGlobalIndex;
    var cumulative = 0;
    for (final sentence in _fullDoc!.sentences) {
      final sentenceEnd = cumulative + sentence.words.length;
      if (globalIdx < sentenceEnd) {
        // Current sentence found — seek to start of next sentence.
        if (sentenceEnd < _allDocWords.length) {
          final localTarget = (sentenceEnd - _sliceOffset).clamp(
            0,
            _words.length - 1,
          );
          ref.read(wordTimerProvider.notifier).seekTo(localTarget);
          appLog(
            'gestures',
            'action: swipeLeft → next sentence at word $sentenceEnd',
          );
        } else {
          appLog('gestures', 'action: swipeLeft → already at last sentence');
        }
        return;
      }
      cumulative = sentenceEnd;
    }
  }

  /// Navigate to the first word of the previous sentence (RSVP mode).
  void _seekToPreviousSentence() {
    if (_fullDoc == null) return;
    final globalIdx = _currentGlobalIndex;
    var cumulative = 0;
    int previousSentenceStart = 0;
    for (final sentence in _fullDoc!.sentences) {
      final sentenceEnd = cumulative + sentence.words.length;
      if (globalIdx < sentenceEnd) {
        // If already at sentence start, go to previous sentence.
        final target = globalIdx == cumulative
            ? previousSentenceStart
            : cumulative;
        final localTarget = (target - _sliceOffset).clamp(0, _words.length - 1);
        ref.read(wordTimerProvider.notifier).seekTo(localTarget);
        appLog(
          'gestures',
          'action: swipeRight → previous sentence at word $target',
        );
        return;
      }
      previousSentenceStart = cumulative;
      cumulative = sentenceEnd;
    }
  }

  Timer? _sentenceGapTimer;

  void _onSweepAdvance() {
    if (!mounted) return;
    final crState = ref.read(contextRevealProvider);
    if (!crState.isActive) return;
    final words = _contextRevealWords();
    final atEnd = ref
        .read(contextRevealProvider.notifier)
        .advanceSweep(words.length);
    if (atEnd) {
      _autoAdvanceToNextSentence(crState);
    }
  }

  /// Auto-advance to next sentence after the inter-sentence gap delay.
  // Grade D — tunable via SpeedyBoyTiming.sentenceGapMs
  void _autoAdvanceToNextSentence(ContextRevealState crState) {
    _sentenceGapTimer?.cancel();
    _sweepEngine.pause();
    _sentenceGapTimer = Timer(
      const Duration(milliseconds: SpeedyBoyTiming.sentenceGapMs),
      () {
        if (!mounted) return;
        final current = ref.read(contextRevealProvider);
        if (!current.isActive || current.isSweepPaused) return;
        if (_fullDoc == null) return;

        final currentStart = _sentenceStartAt(current.resumeWordIndex);
        final sentenceWords = _sentenceWordsAt(currentStart);
        final nextStart = currentStart + sentenceWords.length;

        if (nextStart < _allDocWords.length) {
          ref.read(contextRevealProvider.notifier).enterSentence(nextStart);
          _sweepEngine.reset();
          _sweepEngine.start();
          appLog('sweep', 'auto-advance to sentence at word $nextStart');
        } else {
          // Last sentence — hold on final word, no further advance
          _sweepEngine.stop();
          appLog('sweep', 'reached last sentence, holding');
        }
      },
    );
  }

  // P3 Grade C — swipe detection via Listener pointer events.
  // Uses classifySwipe() from gesture_classifier.dart for dual-gate
  // threshold validation (distance ratio + velocity).
  // RULE 24 COMPLIANCE: Listener is used instead of onVerticalDragEnd /
  // onHorizontalDragEnd to avoid gesture arena conflicts with the WpmDial3D
  // GestureDetector (which owns drag input while visible). Raw pointer events
  // bypass the arena and are consistent with Rule 24's intent.
  void _handlePointerUp(PointerUpEvent event) {
    if (_showReadingGoalOnboarding) return;
    // Suppress swipe classification while the WPM dial is visible —
    // the dial's own GestureDetector handles drag input, but the raw
    // Listener pointer events still fire and would be misclassified
    // as directional swipes.
    if (ref.read(wpmDialProvider).isVisible) {
      _panStart = null;
      _panLast = null;
      _panStartTime = null;
      return;
    }
    final start = _panStart;
    final last = _panLast;
    final startTime = _panStartTime;
    _panStart = null;
    _panLast = null;
    _panStartTime = null;

    if (start == null || last == null || startTime == null) return;

    final dx = last.dx - start.dx;
    final dy = last.dy - start.dy;
    final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
    final screenSize = MediaQuery.sizeOf(context);

    final direction = classifySwipe(
      dx: dx,
      dy: dy,
      elapsedMs: elapsedMs,
      screenWidth: screenSize.width,
      screenHeight: screenSize.height,
    );

    if (direction == null) {
      // Only log if there was meaningful drag (avoids noise from taps).
      if (dx.abs() > 5 || dy.abs() > 5) {
        final vel = elapsedMs > 0
            ? (dx.abs() / (elapsedMs / 1000)).toStringAsFixed(0)
            : '0';
        appLog(
          'gestures',
          'rejected: dx=${dx.toStringAsFixed(0)} dy=${dy.toStringAsFixed(0)} '
              'velocity=$vel elapsed=${elapsedMs}ms',
        );
      }
      return;
    }

    final vel = elapsedMs > 0
        ? (direction == SwipeDirection.up || direction == SwipeDirection.down
              ? dy.abs() / (elapsedMs / 1000)
              : dx.abs() / (elapsedMs / 1000))
        : 0.0;
    final dist =
        direction == SwipeDirection.up || direction == SwipeDirection.down
        ? dy.abs()
        : dx.abs();

    appLog(
      'gestures',
      'detected: ${direction.name} velocity=${vel.toStringAsFixed(0)} '
          'distance=${dist.toStringAsFixed(0)}',
    );

    switch (direction) {
      case SwipeDirection.up:
        _onSwipeUp();
      case SwipeDirection.down:
        _onSwipeDown();
      case SwipeDirection.left:
        _onSwipeLeft();
      case SwipeDirection.right:
        _onSwipeRight();
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.escape) {
      _goBack();
    } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _toggleFullScreen();
      // TASK-044 — ContextReveal keyboard shortcuts
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _onSwipeUp();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _onSwipeDown();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _onSwipeLeft();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _onSwipeRight();
    } else if (event.logicalKey == LogicalKeyboardKey.space) {
      _togglePause();
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final timer = ref.read(wordTimerProvider.notifier);
      final currentWpm = ref.read(wordTimerProvider).wpm;
      // Scroll up = increase WPM, scroll down = decrease
      if (event.scrollDelta.dy < 0) {
        timer.setWpm((currentWpm + 10).clamp(30, 1000));
      } else if (event.scrollDelta.dy > 0) {
        timer.setWpm((currentWpm - 10).clamp(30, 1000));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = ref.watch(wordTimerProvider.select((s) => s.isPlaying));
    final progress = ref.watch(wordTimerProvider.select((s) => s.progress));
    final wpm = ref.watch(wordTimerProvider.select((s) => s.wpm));
    final dialState = ref.watch(wpmDialProvider);
    // Select only the config fields used in build() to avoid
    // unnecessary rebuilds from bookmark auto-save every 5s.
    final config = ref.watch(
      configProvider.select((c) {
        final v = c.valueOrNull ?? const AppConfig();
        return (
          parallaxIntensity: v.parallaxIntensity,
          anchorColorIndex: v.anchorColorIndex,
          fontFamily: v.fontFamily,
        );
      }),
    );

    // P2 Grade C — pause/resume reading when WPM dial visibility changes
    ref.listen<WpmDialState>(wpmDialProvider, (prev, next) {
      if (next.isVisible && !(prev?.isVisible ?? false)) {
        ref.read(wordTimerProvider.notifier).pause();
      } else if (!next.isVisible && (prev?.isVisible ?? false)) {
        ref.read(wordTimerProvider.notifier).play();
      }
    });

    ref.listen<WordTimerState>(wordTimerProvider, (prev, next) {
      if (prev?.currentIndex != next.currentIndex) {
        final idx = next.currentIndex;

        // Update word display.
        if (_words.isNotEmpty && idx < _words.length) {
          _wordNotifier.value = _words[idx];
          _wordAdvanceCount++;
          _sessionWordCount++;
          if (_wordAdvanceCount <= 5) {
            appLog(
              'ParallaxReadingScreen',
              'word advance #$_wordAdvanceCount idx=$idx "${_words[idx]}"',
            );
          }

          // P27 — trigger onboarding hints at word milestones
          if (_wordAdvanceCount == 1) {
            _tryShowHint(HintId.tap);
            _hintController.startLongPressTimer();
          } else if (_wordAdvanceCount == 10) {
            _tryShowHint(HintId.swipeUp);
          }
        } else {
          appLog(
            'ParallaxReadingScreen',
            'WARN: idx=$idx _words.length=${_words.length}',
          );
        }

        // Save global word index (sliceOffset + slice-local index).
        // Rule 28 — skip bookmark persist for clipboard documents.
        if (!_isClipboard) {
          final globalIndex = _sliceOffset + idx;
          ref
              .read(bookmarkProvider(widget.filePath).notifier)
              .updateIndex(globalIndex);
        }

        // Detect range completion.
        if (_readingRange != null && !_isRangeComplete && next.isFinished) {
          setState(() => _isRangeComplete = true);
        }
      }
    });

    final anchorColor =
        SpeedyBoyTokens.anchorColors[config.anchorColorIndex.clamp(
          0,
          SpeedyBoyTokens.anchorColors.length - 1,
        )];

    // P4 Grade C — flash anchor color on double-tap sentence restart
    final effectiveAnchorColor = _showRestartFlash
        ? SpeedyBoyTokens.stageText
        : anchorColor;

    // P20 — watch ContextReveal state for overlay rendering
    final crState = ref.watch(contextRevealProvider);

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: ColoredBox(
          color: SpeedyBoyTokens.roomBackground,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fontSize = dynamicFontSize(constraints);

              return Listener(
                // Passive pointer tracking — doesn't compete in the
                // gesture arena, so onLongPress can still fire.
                onPointerDown: (e) {
                  _panStart = e.position;
                  _panStartTime = DateTime.now();
                },
                onPointerMove: (e) => _panLast = e.position,
                onPointerUp: _handlePointerUp,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _togglePause,
                        onDoubleTap: _handleDoubleTap,
                        onLongPressStart: (details) {
                          appLog('gestures', 'detected: longPress');
                          // P27 — user discovered long-press; cancel hint timer
                          _hintController.cancelLongPressTimer();
                          _hintController.markShown(HintId.longPress);
                          ref
                              .read(wpmDialProvider.notifier)
                              .show(details.globalPosition, wpm);
                        },
                        child: ValueListenableBuilder<String>(
                          valueListenable: _wordNotifier,
                          builder: (context, currentWord, _) {
                            // P7 Grade C — shared overlay stack for all intensity modes
                            final overlayStack = Stack(
                              children: [
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  height: 1,
                                  child: ProgressHairline3D(progress: progress),
                                ),
                                if (config.parallaxIntensity !=
                                        ParallaxIntensity.none &&
                                    !crState.isActive)
                                  Positioned.fill(
                                    child: PauseFog3D(
                                      isPaused: !isPlaying && _words.isNotEmpty,
                                      wpm: wpm,
                                    ),
                                  ),
                                if (_isRangeComplete && _readingRange != null)
                                  Positioned.fill(
                                    child: FinishedRangeOverlay(
                                      visible: _isRangeComplete,
                                      startPage: _readingRange!.startPage,
                                      endPage: _readingRange!.endPage,
                                      wordCount: _words.length,
                                      averageWpm: wpm,
                                      onContinueReading:
                                          _continueReadingPastRange,
                                      onSetNewRange: () {
                                        ref
                                            .read(
                                              bookmarkProvider(
                                                widget.filePath,
                                              ).notifier,
                                            )
                                            .save();
                                        context.push(
                                          Uri(
                                            path: '/range-picker',
                                            queryParameters: {
                                              'path': widget.filePath,
                                            },
                                          ).toString(),
                                        );
                                      },
                                      onGoToLibrary: () {
                                        ref
                                            .read(
                                              bookmarkProvider(
                                                widget.filePath,
                                              ).notifier,
                                            )
                                            .save();
                                        ref
                                            .read(wordTimerProvider.notifier)
                                            .pause();
                                        context.go('/');
                                      },
                                    ),
                                  ),
                                // ── ContextReveal Overlay ──
                                // IgnorePointer so back button and long-press
                                // (WPM dial) pass through — all gestures are
                                // handled by the parent Listener/GestureDetector.
                                if (crState.isActive)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Semantics(
                                        liveRegion: true,
                                        label:
                                            'Context reveal: ${crState.tier.name} view. '
                                            '${_contextRevealWords().join(' ')}. '
                                            'Swipe down to resume reading.',
                                        child: ContextRevealOverlay(
                                          tier: crState.tier,
                                          words: _contextRevealWords(),
                                          sweepPosition: crState.sweepPosition,
                                          fontSize: fontSize,
                                          fontFamily: config.fontFamily,
                                          isJiggling: crState.isJiggling,
                                          isSweepPaused: crState.isSweepPaused,
                                          backgroundColor:
                                              config.parallaxIntensity ==
                                                  ParallaxIntensity.none
                                              ? SpeedyBoyTokens.stageBase
                                              : SpeedyBoyTokens.cubeBackWall,
                                          backgroundOpacity:
                                              config.parallaxIntensity ==
                                                  ParallaxIntensity.none
                                              ? 1.0
                                              : 0.88,
                                          onJiggleComplete: () => ref
                                              .read(
                                                contextRevealProvider.notifier,
                                              )
                                              .clearJiggle(),
                                        ),
                                      ),
                                    ),
                                  ),
                                // PauseFog3D in sentence mode — rendered after CR
                                // overlay so it's visible on top when sweep is paused.
                                if (crState.isActive &&
                                    crState.isSweepPaused &&
                                    config.parallaxIntensity !=
                                        ParallaxIntensity.none)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: PauseFog3D(
                                        isPaused: crState.isSweepPaused,
                                        wpm: wpm,
                                      ),
                                    ),
                                  ),
                                // Simple dimming for 2D sentence-mode pause
                                if (crState.isActive &&
                                    crState.isSweepPaused &&
                                    config.parallaxIntensity ==
                                        ParallaxIntensity.none)
                                  const Positioned.fill(
                                    child: IgnorePointer(
                                      child: ColoredBox(
                                        color:
                                            SpeedyBoyTokens.stagePauseOverlay,
                                      ),
                                    ),
                                  ),
                                // WPM dial — rendered above ContextReveal so it
                                // remains visible and interactive during sentence view.
                                // Key preserves State across conditional sibling changes.
                                Positioned.fill(
                                  key: const ValueKey('wpm-dial'),
                                  child: WpmDial3D(
                                    wpm: dialState.currentWpm,
                                    visible: dialState.isVisible,
                                    onWpmChanged: (w) {
                                      ref
                                          .read(wpmDialProvider.notifier)
                                          .updateWpm(w);
                                      final newWpm = ref
                                          .read(wpmDialProvider)
                                          .currentWpm;
                                      ref
                                          .read(wordTimerProvider.notifier)
                                          .setWpm(newWpm);
                                      _sweepEngine.updateWpm(newWpm);
                                    },
                                    onDismissed: () => ref
                                        .read(wpmDialProvider.notifier)
                                        .dismiss(),
                                  ),
                                ),

                                // ── ContextReveal Onboarding (shown once) ──
                                if (_showCROnboarding)
                                  Positioned.fill(
                                    child: GestureDetector(
                                      onTap: _dismissCROnboarding,
                                      child: ColoredBox(
                                        color: SpeedyBoyTokens.stagePauseOverlay
                                            .withAlpha(230),
                                        child: Center(
                                          child: Semantics(
                                            liveRegion: true,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 32,
                                                  ),
                                              child: Text(
                                                'Swipe up to see surrounding words.\n'
                                                'Swipe again for more context.\n'
                                                'Swipe down to resume.',
                                                textAlign: TextAlign.center,
                                                style: SpeedyBoyTypography.body
                                                    .copyWith(
                                                      color: SpeedyBoyTokens
                                                          .stageText,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                // ── Onboarding Hint Overlay (Rule 27) ──
                                if (_activeHint != null)
                                  HintOverlay(
                                    text: _activeHint!.message,
                                    position: _activeHint!.position,
                                    slideFrom: _activeHint!.slideFrom,
                                    onDismiss: _dismissActiveHint,
                                  ),
                                // ── Reading Goal Onboarding (shown once) ──
                                if (_showReadingGoalOnboarding)
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: SpeedyBoyTokens.shellBase
                                          .withAlpha(230),
                                      child: Center(
                                        child: SingleChildScrollView(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 40,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Choose Your Reading Pace',
                                                style: SpeedyBoyTypography.title
                                                    .copyWith(
                                                      color: SpeedyBoyTokens
                                                          .shellTextPrimary,
                                                    ),
                                              ),
                                              const SizedBox(height: 16),
                                              ReadingGoalPresets(
                                                onSelected: (goal) {
                                                  ref
                                                      .read(
                                                        configProvider.notifier,
                                                      )
                                                      .applyReadingGoalPreset(
                                                        goal,
                                                      );
                                                  ref
                                                      .read(
                                                        configProvider.notifier,
                                                      )
                                                      .setHasSeenReadingGoalOnboarding(
                                                        true,
                                                      );
                                                  setState(() {
                                                    _showReadingGoalOnboarding =
                                                        false;
                                                  });
                                                  // Begin reading
                                                  ref
                                                      .read(
                                                        wordTimerProvider
                                                            .notifier,
                                                      )
                                                      .play();
                                                },
                                              ),
                                              const SizedBox(height: 12),
                                              GestureDetector(
                                                onTap: () {
                                                  // Skip → default to Comfortable
                                                  final comfortable =
                                                      readingGoalConfigs
                                                          .firstWhere(
                                                            (c) =>
                                                                c.preset ==
                                                                ReadingGoalPreset
                                                                    .comfortable,
                                                          );
                                                  ref
                                                      .read(
                                                        configProvider.notifier,
                                                      )
                                                      .applyReadingGoalPreset(
                                                        comfortable,
                                                      );
                                                  ref
                                                      .read(
                                                        configProvider.notifier,
                                                      )
                                                      .setHasSeenReadingGoalOnboarding(
                                                        true,
                                                      );
                                                  setState(() {
                                                    _showReadingGoalOnboarding =
                                                        false;
                                                  });
                                                  ref
                                                      .read(
                                                        wordTimerProvider
                                                            .notifier,
                                                      )
                                                      .play();
                                                },
                                                child: Text(
                                                  'Customize later in Settings',
                                                  style: SpeedyBoyTypography
                                                      .caption
                                                      .copyWith(
                                                        color: SpeedyBoyTokens
                                                            .shellAccent,
                                                        decoration:
                                                            TextDecoration
                                                                .underline,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );

                            // P7 Grade C — "None" renders flat 2D, no 3D room geometry
                            if (config.parallaxIntensity ==
                                ParallaxIntensity.none) {
                              return Stack(
                                children: [
                                  // Flat stage background
                                  Positioned.fill(
                                    child: Container(
                                      decoration:
                                          SpeedyBoyDecorations.insetDecoration(
                                            SpeedyBoySurface.stage,
                                            borderRadius: 0,
                                          ),
                                    ),
                                  ),
                                  // 2D word painter (hidden during ContextReveal)
                                  if (currentWord.isNotEmpty &&
                                      !crState.isActive)
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: WordPainter(
                                          word: currentWord,
                                          fontSize: fontSize,
                                          animationValue: 1.0,
                                          painterPool: _flatPainterPool,
                                          anchorColor: effectiveAnchorColor,
                                          fontFamily: config.fontFamily,
                                        ),
                                      ),
                                    ),
                                  // Simple dimming on pause (no fog) — suppress
                                  // during CR since CR has its own background.
                                  if (!isPlaying &&
                                      _words.isNotEmpty &&
                                      !crState.isActive)
                                    const Positioned.fill(
                                      child: ColoredBox(
                                        color:
                                            SpeedyBoyTokens.stagePauseOverlay,
                                      ),
                                    ),
                                  // Shared overlays
                                  Positioned.fill(child: overlayStack),
                                ],
                              );
                            }

                            return ParallaxRoom(
                              headX: 0,
                              headY: 0,
                              // Hide RSVP word during ContextReveal
                              currentWord: crState.isActive ? '' : currentWord,
                              fontSize: fontSize,
                              anchorColor: effectiveAnchorColor,
                              isPlaying: isPlaying,
                              fontFamily: config.fontFamily,
                              wpm: wpm,
                              intervalMs: (60000 / wpm).round(),
                              parallaxIntensity: config.parallaxIntensity,
                              child: overlayStack,
                            );
                          },
                        ),
                      ),
                    ),
                    // Back button — opaque GestureDetector absorbs
                    // the hit so the translucent GestureDetector behind
                    // cannot claim the tap for _togglePause.
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 8,
                      left: 8,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _goBack,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.arrow_back,
                            color: SpeedyBoyTokens.stageText,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    if (_isDesktop)
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 8,
                        right: 8,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _toggleFullScreen,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              _isFullScreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                              color: SpeedyBoyTokens.stageText,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
