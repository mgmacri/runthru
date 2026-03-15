import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speedy_boy/core/dynamic_font_size.dart';
import 'package:speedy_boy/core/sentence_resolver.dart';
import 'package:speedy_boy/core/word_timer.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/hooks/bookmark_notifier.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/services/preprocessing_queue.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';
import 'package:speedy_boy/three_d/cube_viewport.dart';
import 'package:speedy_boy/widgets/pause_fog_3d.dart';
import 'package:speedy_boy/widgets/progress_hairline_3d.dart';
import 'package:speedy_boy/widgets/word_display_3d.dart';
import 'package:speedy_boy/widgets/wpm_dial_3d.dart';

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

  static bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _breatheController = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.cubeBreatheDuration,
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
    _words = doc.allWords;
    if (_words.isEmpty) return;

    final config = ref.read(configProvider).valueOrNull ?? const AppConfig();
    final bookmark = config.bookmarks[widget.filePath];
    final startIndex = bookmark != null ? resumeIndex(bookmark, doc) : 0;

    final timer = ref.read(wordTimerProvider.notifier);
    timer.loadDocument(_words.length, startIndex: startIndex);
    timer.setWpm(config.defaultWpm);
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
    ref.read(preprocessingQueueProvider.notifier).resumeBackground();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    _breatheController.dispose();
    super.dispose();
  }

  void _togglePause() {
    final timer = ref.read(wordTimerProvider.notifier);
    final timerState = ref.read(wordTimerProvider);

    if (timerState.isPlaying) {
      timer.pause();
      ref.read(bookmarkProvider(widget.filePath).notifier).save();
      final reducedMotion = isReducedMotion(context);
      if (!reducedMotion) {
        _breatheController.repeat();
      }
    } else {
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
        SpeedyBoyTokens.anchorColors[config.anchorColorIndex.clamp(
      0,
      SpeedyBoyTokens.anchorColors.length - 1,
    )];

    ref.listen<WordTimerState>(wordTimerProvider, (prev, next) {
      if (prev?.currentIndex != next.currentIndex) {
        ref
            .read(bookmarkProvider(widget.filePath).notifier)
            .updateIndex(next.currentIndex);
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
                    child: AnimatedBuilder(
                      animation: _breatheController,
                      builder: (context, child) {
                        return CubeViewport(
                          parallaxOffset: Offset.zero,
                          breatheAngle: SpeedyBoyAnimations.cubeBreatheAngle(
                            _breatheController.value,
                          ),
                          child: child,
                        );
                      },
                      child: Stack(
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 1,
                            child: ProgressHairline3D(
                              progress: timerState.progress,
                            ),
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
                              isPaused:
                                  !timerState.isPlaying && _words.isNotEmpty,
                              wpm: timerState.wpm,
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
                                  ref
                                      .read(wordTimerProvider.notifier)
                                      .setWpm(wpm);
                                },
                                onDismissed: () {
                                  setState(() => _dialVisible = false);
                                },
                              ),
                            ),
                          ),
                        ],
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
                      color: SpeedyBoyTokens.stageText,
                      size: 20,
                    ),
                    onPressed: () {
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
                        color: SpeedyBoyTokens.stageText,
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
}
