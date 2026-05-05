import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/core/dynamic_font_size.dart';
import 'package:runthru/core/reading_range_resolver.dart';
import 'package:runthru/core/sentence_resolver.dart';
import 'package:runthru/core/word_timer.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/hooks/bookmark_notifier.dart';
import 'package:runthru/services/analytics_service.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/preprocessing_queue.dart';
import 'package:runthru/store/analytics_models.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/three_d/cube_viewport.dart';
import 'package:runthru/widgets/finished_range_overlay.dart';
import 'package:runthru/widgets/pause_fog_3d.dart';
import 'package:runthru/widgets/progress_hairline_3d.dart';
import 'package:runthru/widgets/word_display_3d.dart';
import 'package:runthru/widgets/wpm_dial_3d.dart';

/// Full-screen 3D reading experience with static marble cube viewport.
class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({super.key, required this.filePath});

  final String filePath;

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _breatheController;
  bool _dialVisible = false;
  bool _isFullScreen = false;
  List<String> _words = [];
  List<String> _allDocWords = [];
  int _sliceOffset = 0;
  ReadingRange? _readingRange;
  bool _isRangeComplete = false;
  ExtractedDocument? _fullDoc;

  // ── Analytics session tracking ──
  DateTime? _sessionStart;
  int _sessionWordCount = 0;

  /// Cached reference for safe use in dispose().
  late final PreprocessingQueue _queue;

  static bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  @override
  void initState() {
    super.initState();
    _queue = ref.read(preprocessingQueueProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _breatheController = AnimationController(
      vsync: this,
      duration: RunThruAnimations.cubeBreatheDuration,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initReading();
    });
  }

  Future<void> _initReading() async {
    final queue = ref.read(preprocessingQueueProvider.notifier);
    await queue.prioritize(widget.filePath);

    final processed = ref.read(preprocessingQueueProvider);
    final entry = processed[widget.filePath];

    if (entry?.document != null) {
      _loadDocument(entry!.document!);
    }
  }

  void _loadDocument(ExtractedDocument doc) {
    _fullDoc = doc;
    _allDocWords = doc.allWords;
    if (_allDocWords.isEmpty) return;

    final config = ref.read(configProvider).valueOrNull ?? const AppConfig();
    final bookmark = config.bookmarks[widget.filePath];
    final range = bookmark?.readingRange;

    if (range != null && doc.hasPageBoundaries) {
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

        final lastPosition = bookmark?.wordIndex ?? 0;
        int startIndex;
        if (lastPosition <= rangeStart) {
          startIndex = 0;
        } else if (lastPosition >= rangeEnd) {
          startIndex = _words.length - 1;
          _isRangeComplete = true;
        } else {
          final globalResume = resumeIndex(bookmark!, doc);
          startIndex = (globalResume - rangeStart).clamp(0, _words.length - 1);
        }

        final timer = ref.read(wordTimerProvider.notifier);
        timer.loadDocument(_words.length, startIndex: startIndex);
        timer.attachWordSource((i) => i < _words.length ? _words[i] : null);
        timer.setWpm(config.defaultWpm);
        if (_isRangeComplete) {
          timer.pause();
        } else {
          _sessionStart = DateTime.now();
          _sessionWordCount = 0;
          timer.play();
        }
        _breatheController.stop();
        return;
      }
    }

    // No range — full document.
    _words = _allDocWords;
    _sliceOffset = 0;
    _readingRange = null;

    final startIndex = bookmark != null ? resumeIndex(bookmark, doc) : 0;
    final timer = ref.read(wordTimerProvider.notifier);
    timer.loadDocument(_words.length, startIndex: startIndex);
    timer.attachWordSource((i) => i < _words.length ? _words[i] : null);
    timer.setWpm(config.defaultWpm);
    _sessionStart = DateTime.now();
    _sessionWordCount = 0;
    timer.play();
    _breatheController.stop();
  }

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

    final timer = ref.read(wordTimerProvider.notifier);
    timer.loadDocument(_words.length, startIndex: 0);
    timer.attachWordSource((i) => i < _words.length ? _words[i] : null);
    _sessionStart = DateTime.now();
    _sessionWordCount = 0;
    timer.play();
    _breatheController.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(bookmarkProvider(widget.filePath).notifier).save();
    }
  }

  @override
  void dispose() {
    _endAnalyticsSession();
    _queue.resumeBackground();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    _breatheController.dispose();
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
    ref.read(analyticsServiceProvider).saveSession(session);
  }

  void _togglePause() {
    final timer = ref.read(wordTimerProvider.notifier);
    final timerState = ref.read(wordTimerProvider);

    if (timerState.isPlaying) {
      timer.pause();
      ref.read(bookmarkProvider(widget.filePath).notifier).save();
      _endAnalyticsSession();
      final reducedMotion = isReducedMotion(context);
      if (!reducedMotion) {
        _breatheController.repeat();
      }
    } else {
      _sessionStart = DateTime.now();
      _sessionWordCount = 0;
      timer.play();
      _breatheController.stop();
      _breatheController.value = 0;
    }
  }

  void _showDial() {
    setState(() => _dialVisible = true);
  }

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
    SystemChrome.setEnabledSystemUIMode(
      _isFullScreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  Widget build(BuildContext context) {
    final timerState = ref.watch(wordTimerProvider);
    final config = ref.watch(configProvider).valueOrNull ?? const AppConfig();

    final anchorColor =
        RunThruTokens.anchorColors[config.anchorColorIndex.clamp(
          0,
          RunThruTokens.anchorColors.length - 1,
        )];

    ref.listen<WordTimerState>(wordTimerProvider, (prev, next) {
      if (prev?.currentIndex != next.currentIndex) {
        final globalIndex = _sliceOffset + next.currentIndex;
        ref
            .read(bookmarkProvider(widget.filePath).notifier)
            .updateIndex(globalIndex);
        _sessionWordCount++;

        if (_readingRange != null && !_isRangeComplete && next.isFinished) {
          setState(() => _isRangeComplete = true);
        }
      }
    });

    final currentWord =
        _words.isNotEmpty && timerState.currentIndex < _words.length
        ? _words[timerState.currentIndex]
        : '';

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fontSize = dynamicFontSize(constraints);

            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _togglePause,
                    onLongPress: _showDial,
                    child: _buildViewport(
                      config,
                      child: _buildContent(
                        currentWord: currentWord,
                        timerState: timerState,
                        anchorColor: anchorColor,
                        fontSize: fontSize,
                        config: config,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: RunThruTokens.stageText,
                      size: 20,
                    ),
                    onPressed: () {
                      _endAnalyticsSession();
                      ref
                          .read(bookmarkProvider(widget.filePath).notifier)
                          .save();
                      ref.read(wordTimerProvider.notifier).pause();
                      context.pop();
                    },
                  ),
                ),
                if (_isDesktop)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: Icon(
                        _isFullScreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        color: RunThruTokens.stageText,
                        size: 20,
                      ),
                      onPressed: _toggleFullScreen,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Wraps content in the 3D cube or a flat background depending on
  /// [ParallaxIntensity]. "None" and "Off" get a flat stageBase fill.
  Widget _buildViewport(AppConfig config, {required Widget child}) {
    final flat =
        config.parallaxIntensity == ParallaxIntensity.none ||
        config.parallaxIntensity == ParallaxIntensity.off;

    if (flat) {
      return ColoredBox(color: RunThruTokens.stageBase, child: child);
    }

    return ListenableBuilder(
      listenable: _breatheController,
      builder: (context, inner) {
        return CubeViewport(
          parallaxOffset: Offset.zero,
          breatheAngle: RunThruAnimations.cubeBreatheAngle(
            _breatheController.value,
          ),
          child: inner,
        );
      },
      child: child,
    );
  }

  /// Builds the stacked content layer (word, progress, pause fog, dial, etc.).
  Widget _buildContent({
    required String currentWord,
    required WordTimerState timerState,
    required Color anchorColor,
    required double fontSize,
    required AppConfig config,
  }) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 1,
          child: ProgressHairline3D(progress: timerState.progress),
        ),
        Positioned.fill(
          child: WordDisplay3D(
            word: currentWord,
            fontSize: fontSize,
            anchorColor: anchorColor,
            fontFamily: config.fontFamily,
          ),
        ),
        Positioned.fill(
          child: PauseFog3D(
            isPaused: !timerState.isPlaying && _words.isNotEmpty,
            wpm: timerState.wpm,
          ),
        ),
        if (_isRangeComplete && _readingRange != null)
          Positioned.fill(
            child: FinishedRangeOverlay(
              visible: _isRangeComplete,
              startPage: _readingRange!.startPage,
              endPage: _readingRange!.endPage,
              wordCount: _words.length,
              averageWpm: timerState.wpm,
              onContinueReading: _continueReadingPastRange,
              onSetNewRange: () {
                ref.read(bookmarkProvider(widget.filePath).notifier).save();
                context.push(
                  Uri(
                    path: '/range-picker',
                    queryParameters: {'path': widget.filePath},
                  ).toString(),
                );
              },
              onGoToLibrary: () {
                ref.read(bookmarkProvider(widget.filePath).notifier).save();
                ref.read(wordTimerProvider.notifier).pause();
                context.go('/');
              },
            ),
          ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: WpmDial3D(
              wpm: timerState.wpm,
              visible: _dialVisible,
              onWpmChanged: (wpm) {
                ref.read(wordTimerProvider.notifier).setWpm(wpm);
              },
              onDismissed: () {
                setState(() => _dialVisible = false);
              },
            ),
          ),
        ),
      ],
    );
  }
}
