import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speedy_boy/core/logger.dart';
import 'package:speedy_boy/core/reading_range_resolver.dart';
import 'package:speedy_boy/core/sentence_resolver.dart';
import 'package:speedy_boy/core/word_timer.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/hooks/bookmark_notifier.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/services/preprocessing_queue.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';
import 'package:speedy_boy/three_d/back_wall_font_sizer.dart';
import 'package:speedy_boy/three_d/off_axis_projection.dart';
import 'package:speedy_boy/three_d/parallax_room.dart';
import 'package:speedy_boy/widgets/finished_range_overlay.dart';
import 'package:speedy_boy/widgets/pause_fog_3d.dart';
import 'package:speedy_boy/widgets/progress_hairline_3d.dart';
import 'package:speedy_boy/widgets/wpm_dial_3d.dart';
import 'package:window_manager/window_manager.dart';

class ParallaxReadingScreen extends ConsumerStatefulWidget {
  const ParallaxReadingScreen({super.key, required this.filePath});

  final String filePath;

  @override
  ConsumerState<ParallaxReadingScreen> createState() =>
      _ParallaxReadingScreenState();
}

class _ParallaxReadingScreenState extends ConsumerState<ParallaxReadingScreen>
    with WidgetsBindingObserver {
  final ValueNotifier<String> _wordNotifier = ValueNotifier('');
  final FocusNode _focusNode = FocusNode();
  final BackWallFontSizer _fontSizer = BackWallFontSizer();
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

  bool _dialVisible = false;
  bool _isFullScreen = false;

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
    appLog('ParallaxReadingScreen', 'initState filePath=${widget.filePath}');
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (_isDesktop) _enterDesktopFullScreen();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      appLog('ParallaxReadingScreen', 'post-frame: loading document');
      _initReading();
    });
  }

  @override
  void dispose() {
    _wordNotifier.dispose();
    _focusNode.dispose();
    _queue.resumeBackground();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_isDesktop && _isFullScreen) windowManager.setFullScreen(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(bookmarkProvider(widget.filePath).notifier).save();
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
    appLog('ParallaxReadingScreen',
        'after prioritize: status=${entry?.status} hasDoc=${entry?.document != null}');

    if (entry?.document != null) {
      _loadDocument(entry!.document!);
    } else {
      appLog('ParallaxReadingScreen',
          'WARN: document null — words never load. entry=$entry');
    }
  }

  void _loadDocument(ExtractedDocument doc) {
    _fullDoc = doc;
    _allDocWords = doc.allWords;
    appLog('ParallaxReadingScreen',
        '_loadDocument: totalWords=${_allDocWords.length}');

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
        final rangeEnd =
            resolved.resolvedEndWordIndex.clamp(0, _allDocWords.length - 1);
        _sliceOffset = rangeStart;
        _words = _allDocWords.sublist(
          rangeStart,
          rangeEnd + 1,
        );

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

        appLog('ParallaxReadingScreen',
            'range: $rangeStart-$rangeEnd, sliceLen=${_words.length}, startIdx=$startIndex');

        _wordNotifier.value = _words[startIndex.clamp(0, _words.length - 1)];
        final timer = ref.read(wordTimerProvider.notifier);
        timer.loadDocument(_words.length, startIndex: startIndex);
        timer.setWpm(config.defaultWpm);

        if (_isRangeComplete) {
          timer.pause();
        } else {
          timer.play();
        }
        appLog('ParallaxReadingScreen',
            'timer loaded with range slice, wpm=${config.defaultWpm}');
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
    appLog('ParallaxReadingScreen',
        'wordNotifier seeded: "${_wordNotifier.value}"');

    final timer = ref.read(wordTimerProvider.notifier);
    timer.loadDocument(_words.length, startIndex: startIndex);
    timer.setWpm(config.defaultWpm);
    timer.play();
    appLog('ParallaxReadingScreen', 'timer.play() wpm=${config.defaultWpm}');
  }

  void _togglePause() {
    final timer = ref.read(wordTimerProvider.notifier);
    if (ref.read(wordTimerProvider).isPlaying) {
      timer.pause();
      ref.read(bookmarkProvider(widget.filePath).notifier).save();
    } else {
      timer.play();
    }
  }

  /// Extends reading past the original range end to the end of the document.
  void _continueReadingPastRange() {
    if (_fullDoc == null || _readingRange == null) return;

    final rangeEnd = _readingRange!.resolvedEndWordIndex;
    final remaining = _allDocWords.sublist(rangeEnd + 1);
    if (remaining.isEmpty) return;

    setState(() {
      _isRangeComplete = false;
      _words = remaining;
      _sliceOffset = rangeEnd + 1;
    });

    _wordNotifier.value = _words.first;
    final timer = ref.read(wordTimerProvider.notifier);
    timer.loadDocument(_words.length, startIndex: 0);
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
    ref.read(bookmarkProvider(widget.filePath).notifier).save();
    ref.read(wordTimerProvider.notifier).pause();
    if (mounted) context.pop();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.escape) {
      _goBack();
    } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _toggleFullScreen();
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
    final config = ref.watch(configProvider).valueOrNull ?? const AppConfig();

    ref.listen(
      wordTimerProvider.select((s) => s.currentIndex),
      (_, idx) {
        if (_words.isNotEmpty && idx < _words.length) {
          _wordNotifier.value = _words[idx];
          _wordAdvanceCount++;
          if (_wordAdvanceCount <= 5) {
            appLog('ParallaxReadingScreen',
                'word advance #$_wordAdvanceCount idx=$idx "${_words[idx]}"');
          }
        } else {
          appLog('ParallaxReadingScreen',
              'WARN: idx=$idx _words.length=${_words.length}');
        }
      },
    );

    ref.listen<WordTimerState>(wordTimerProvider, (prev, next) {
      if (prev?.currentIndex != next.currentIndex) {
        // Save global word index (sliceOffset + slice-local index).
        final globalIndex = _sliceOffset + next.currentIndex;
        ref
            .read(bookmarkProvider(widget.filePath).notifier)
            .updateIndex(globalIndex);

        // Detect range completion.
        if (_readingRange != null && !_isRangeComplete && next.isFinished) {
          setState(() => _isRangeComplete = true);
        }
      }
    });

    final anchorColor = SpeedyBoyTokens.anchorColors[config.anchorColorIndex
        .clamp(0, SpeedyBoyTokens.anchorColors.length - 1)];

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
              // Use BackWallFontSizer for parallax screen
              // (dynamicFontSize is only for the non-parallax fallback)
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final roomConfig = RoomConfig.fromScreen(size);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePause,
                onLongPress: () => setState(() => _dialVisible = true),
                child: ValueListenableBuilder<String>(
                  valueListenable: _wordNotifier,
                  builder: (context, currentWord, _) {
                    final baseFontSize = _fontSizer.computeFontSize(
                      roomConfig,
                      0, // headX
                      0, // headY
                      constraints.maxWidth,
                      constraints.maxHeight,
                      currentWord,
                    );
                    final fontSize = baseFontSize * config.fontScale;

                    return ParallaxRoom(
                      headX: 0,
                      headY: 0,
                      currentWord: currentWord,
                      fontSize: fontSize,
                      anchorColor: anchorColor,
                      isPlaying: isPlaying,
                      fontFamily: config.fontFamily,
                      child: Stack(
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 1,
                            child: ProgressHairline3D(progress: progress),
                          ),
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
                                onContinueReading: _continueReadingPastRange,
                                onSetNewRange: () {
                                  ref
                                      .read(bookmarkProvider(widget.filePath)
                                          .notifier)
                                      .save();
                                  context.push(Uri(
                                    path: '/range-picker',
                                    queryParameters: {'path': widget.filePath},
                                  ).toString());
                                },
                                onGoToLibrary: () {
                                  ref
                                      .read(bookmarkProvider(widget.filePath)
                                          .notifier)
                                      .save();
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
                                wpm: wpm,
                                visible: _dialVisible,
                                onWpmChanged: (w) => ref
                                    .read(wordTimerProvider.notifier)
                                    .setWpm(w),
                                onDismissed: () =>
                                    setState(() => _dialVisible = false),
                              ),
                            ),
                          ),
                          Positioned(
                            top: MediaQuery.paddingOf(context).top + 8,
                            left: 8,
                            child: IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: SpeedyBoyTokens.stageText,
                                size: 20,
                              ),
                              onPressed: _goBack,
                            ),
                          ),
                          if (_isDesktop)
                            Positioned(
                              top: MediaQuery.paddingOf(context).top + 8,
                              right: 8,
                              child: IconButton(
                                icon: Icon(
                                  _isFullScreen
                                      ? Icons.fullscreen_exit
                                      : Icons.fullscreen,
                                  color: SpeedyBoyTokens.stageText,
                                  size: 20,
                                ),
                                onPressed: _toggleFullScreen,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
