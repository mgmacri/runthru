import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:speedy_boy/core/context_reveal_state.dart';
import 'package:speedy_boy/design/design.dart';

/// Full-screen overlay for ContextReveal comprehension recovery.
///
/// Displays the full current sentence in a wrapped text block, centered
/// vertically. v4 simplified to sentence-only (no micro/clause tiers).
///
/// Animated transitions:
/// - Enter (RSVP → Sentence): 200ms easeOut
/// - Exit: 150ms easeOut
/// - Jiggle (ceiling feedback): scale 1.0 → 1.2 → spring back ~300ms
/// - Reduced motion: all transitions instant / opacity flash for jiggle.
// P17 Grade C — ContextReveal overlay (sentence only)
class ContextRevealOverlay extends StatefulWidget {
  const ContextRevealOverlay({
    required this.tier,
    required this.words,
    required this.sweepPosition,
    required this.fontSize,
    this.fontFamily = 'BricolageGrotesque',
    this.isJiggling = false,
    this.isSweepPaused = false,
    this.backgroundColor = SpeedyBoyTokens.roomBackground,
    this.backgroundOpacity = 1.0,
    this.onExitComplete,
    this.onJiggleComplete,
    super.key,
  });

  /// Current ContextReveal tier (determines word count).
  final ContextRevealTier tier;

  /// The words to display in the overlay.
  final List<String> words;

  /// Current sweep highlight position (0-indexed within [words]).
  final int sweepPosition;

  /// Font size for the displayed words.
  final double fontSize;

  /// Font family for the displayed words.
  final String fontFamily;

  /// Whether the elastic jiggle animation should play (ceiling feedback).
  // P1 Grade C — elastic jiggle when swiping up in sentence view
  final bool isJiggling;

  /// Whether the sweep is currently paused (shows pause indicator).
  final bool isSweepPaused;

  /// Called when exit animation completes.
  final VoidCallback? onExitComplete;

  /// Background color for the overlay — should match the reading screen's
  /// current background (roomBackground for 3D, stageBase for flat 2D).
  final Color backgroundColor;

  /// Opacity of the background fill (0.0–1.0). Set < 1.0 to let the
  /// parallax room show through in 3D modes.
  final double backgroundOpacity;

  /// Called when the jiggle animation completes.
  final VoidCallback? onJiggleComplete;

  @override
  State<ContextRevealOverlay> createState() => _ContextRevealOverlayState();
}

class _ContextRevealOverlayState extends State<ContextRevealOverlay>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  // ── Jiggle animation (P1 Grade C) ──
  late AnimationController _jiggleController;
  double _jiggleScale = 1.0;
  double _jiggleOpacity = 1.0; // for reduced-motion fallback

  bool _hasAnimatedInitialEntry = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _opacity = const AlwaysStoppedAnimation(0.0);
    _jiggleController = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Defer initial animation to didChangeDependencies where MediaQuery
    // (needed by isReducedMotion) is available.
    if (!_hasAnimatedInitialEntry && widget.tier != ContextRevealTier.none) {
      _hasAnimatedInitialEntry = true;
      _animateEnter();
    }
  }

  @override
  void didUpdateWidget(ContextRevealOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.tier != widget.tier) {
      if (widget.tier == ContextRevealTier.none &&
          oldWidget.tier != ContextRevealTier.none) {
        _animateExit();
      } else if (oldWidget.tier == ContextRevealTier.none &&
          widget.tier != ContextRevealTier.none) {
        _animateEnter();
      }
    }

    // P1 Grade C — trigger jiggle when isJiggling transitions to true
    if (widget.isJiggling && !oldWidget.isJiggling) {
      _animateJiggle();
    }
  }

  void _animateEnter() {
    final reduced = isReducedMotion(context);
    if (reduced) {
      _opacity = const AlwaysStoppedAnimation(1.0);
      _controller.value = 1.0;
      setState(() {});
      return;
    }
    // P17 Grade C — enter: 200ms easeOut
    _controller.duration = SpeedyBoyTiming.contextRevealEnter;
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward(from: 0.0);
  }

  void _animateExit() {
    final reduced = isReducedMotion(context);
    if (reduced) {
      _opacity = const AlwaysStoppedAnimation(0.0);
      _controller.value = 0.0;
      setState(() {});
      widget.onExitComplete?.call();
      return;
    }
    // P17 Grade C — exit: 150ms easeOut
    _controller.duration = SpeedyBoyTiming.contextRevealExit;
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.reverse(from: 1.0).then((_) {
      widget.onExitComplete?.call();
    });
  }

  /// Elastic jiggle — ceiling feedback when swiping up in sentence view.
  ///
  /// Full motion: scale 1.0 → 1.2 (100ms ease-out), then spring back to 1.0
  /// (~200ms damped spring). Total ~300ms.
  /// Reduced motion (Rule 5): opacity flash 1.0 → 0.7 → 1.0 over 150ms.
  // P1 Grade C — elastic jiggle uses SpeedyBoyTiming tokens
  void _animateJiggle() {
    final reduced = isReducedMotion(context);
    if (reduced) {
      _animateJiggleReducedMotion();
      return;
    }

    // Phase 1: Scale up to max
    _jiggleController.duration = const Duration(
      milliseconds: SpeedyBoyTiming.jiggleScaleUpMs,
    );
    _jiggleController.addListener(_onJiggleUpdate);

    _jiggleController.forward(from: 0.0).then((_) {
      if (!mounted) return;
      // Phase 2: Spring back
      final simulation = SpeedyBoyAnimations.jiggleSimulation(
        from: 1.0,
        to: 0.0,
      );
      _jiggleController.animateWith(simulation).then((_) {
        if (!mounted) return;
        _jiggleController.removeListener(_onJiggleUpdate);
        setState(() => _jiggleScale = 1.0);
        widget.onJiggleComplete?.call();
      });
    });
  }

  void _onJiggleUpdate() {
    const maxScale = SpeedyBoyTiming.jiggleMaxScale;
    // Map controller value (0→1→0) to scale (1.0→maxScale→1.0)
    final t = _jiggleController.value;
    setState(() => _jiggleScale = 1.0 + (maxScale - 1.0) * t);
  }

  /// Reduced-motion fallback: opacity flash instead of scale.
  void _animateJiggleReducedMotion() {
    _jiggleController.duration = const Duration(milliseconds: 150);
    _jiggleController.addListener(_onJiggleReducedUpdate);
    _jiggleController.forward(from: 0.0).then((_) {
      if (!mounted) return;
      _jiggleController.reverse().then((_) {
        if (!mounted) return;
        _jiggleController.removeListener(_onJiggleReducedUpdate);
        setState(() => _jiggleOpacity = 1.0);
        widget.onJiggleComplete?.call();
      });
    });
  }

  void _onJiggleReducedUpdate() {
    // Flash: 1.0 → 0.7 → 1.0
    final t = _jiggleController.value;
    setState(() => _jiggleOpacity = 1.0 - 0.3 * t);
  }

  @override
  void dispose() {
    _controller.dispose();
    _jiggleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tier == ContextRevealTier.none && _controller.value == 0.0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final adaptedSize = _adaptiveFontSize(
          widget.words,
          constraints.biggest,
          context,
        );

        return ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final opacityValue = _opacity.value;
            return Stack(
              children: [
                // ── Background — hides RSVP word. Opacity controlled
                // by backgroundOpacity to let parallax room persist.
                Positioned.fill(
                  child: ColoredBox(
                    color: widget.backgroundColor.withAlpha(
                      (255 * widget.backgroundOpacity * opacityValue).round(),
                    ),
                  ),
                ),

                // ── Word display ──
                Positioned.fill(
                  child: Opacity(
                    opacity: opacityValue * _jiggleOpacity,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Transform.scale(
                          scale: _jiggleScale,
                          child: _buildSentenceLayout(
                            adaptedSize,
                            constraints.biggest,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Pause indicator — only shown when sweep is paused ──
                if (widget.isSweepPaused)
                  Positioned(
                    bottom: 32,
                    left: 0,
                    right: 0,
                    child: Opacity(
                      opacity: opacityValue * 0.45,
                      child: _buildPauseIndicator(),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// Compute the readability floor based on device class.
  // P5 Grade C — readability floor varies by device class
  static double _readabilityFloor(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    if (shortestSide >= 600) return 18.0; // tablet
    if (shortestSide >= 400) return 16.0; // large phone
    return 14.0; // small phone
  }

  /// Compute adaptive font size for the sentence overlay.
  ///
  /// Starts at [widget.fontSize], reduces by 2pt steps until the wrapped text
  /// fits within 80% of [viewportSize] height, or hits the readability floor.
  double _adaptiveFontSize(
    List<String> words,
    Size viewportSize,
    BuildContext context,
  ) {
    if (words.isEmpty) return widget.fontSize;

    final floor = _readabilityFloor(context);
    final maxHeight = viewportSize.height * 0.8;
    // Available width after horizontal padding (24px each side)
    final availableWidth = viewportSize.width - 48;
    var fontSize = widget.fontSize;

    while (fontSize > floor) {
      final height = _estimateWrappedHeight(words, fontSize, availableWidth);
      if (height <= maxHeight) return fontSize;
      fontSize -= 2;
    }

    return fontSize.clamp(floor, widget.fontSize);
  }

  /// Estimate the total height of wrapped text at a given font size.
  double _estimateWrappedHeight(
    List<String> words,
    double fontSize,
    double availableWidth,
  ) {
    final style = SpeedyBoyTypography.readingAnchor(
      fontSize,
      fontFamily: widget.fontFamily,
    );

    final spacing = fontSize * 0.25;
    final runSpacing = fontSize * 0.3;

    var currentLineWidth = 0.0;
    var lineCount = 1;

    for (var i = 0; i < words.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: words[i], style: style),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final wordWidth = tp.width;
      tp.dispose();

      final neededWidth = currentLineWidth == 0
          ? wordWidth
          : currentLineWidth + spacing + wordWidth;

      if (neededWidth > availableWidth && currentLineWidth > 0) {
        lineCount++;
        currentLineWidth = wordWidth;
      } else {
        currentLineWidth = neededWidth;
      }
    }

    return lineCount * fontSize + (lineCount - 1) * runSpacing;
  }

  /// Sentence: wrapped text block, centered vertically.
  /// Uses [adaptedSize] computed by [_adaptiveFontSize].
  /// When text still overflows at floor, wraps in a scrollable as last resort.
  Widget _buildSentenceLayout(double adaptedSize, Size viewportSize) {
    // Pre-measure every word at bold weight so each child has a fixed
    // intrinsic width. This prevents line-break jitter when the sweep
    // highlight toggles a boundary word between normal and bold.
    final boldStyle = SpeedyBoyTypography.readingAnchor(
      adaptedSize,
      fontFamily: widget.fontFamily,
    );
    final wordWidths = <double>[];
    for (final word in widget.words) {
      final tp = TextPainter(
        text: TextSpan(text: word, style: boldStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      wordWidths.add(tp.width);
      tp.dispose();
    }

    final content = _wrapInTextDefaults(
      adaptedSize,
      Wrap(
        alignment: WrapAlignment.center,
        spacing: adaptedSize * 0.25,
        runSpacing: adaptedSize * 0.3,
        children: List.generate(
          widget.words.length,
          (i) => _buildWord(i, adaptedSize, wordWidths[i]),
        ),
      ),
    );

    // Check if still overflows at floor — use scroll as last resort
    final availableWidth = viewportSize.width - 48;
    final estimatedHeight = _estimateWrappedHeight(
      widget.words,
      adaptedSize,
      availableWidth,
    );
    final maxHeight = viewportSize.height * 0.8;

    if (estimatedHeight > maxHeight) {
      return SizedBox(
        height: maxHeight,
        child: SingleChildScrollView(child: content),
      );
    }

    return content;
  }

  /// Wrap content in DefaultTextStyle to prevent yellow double-underline
  /// on Android when there's no Material ancestor.
  Widget _wrapInTextDefaults(double fontSize, Widget child) {
    return DefaultTextStyle(
      style: SpeedyBoyTypography.readingWord(
        fontSize,
        fontFamily: widget.fontFamily,
      ),
      child: child,
    );
  }

  Widget _buildWord(int index, double fontSize, double fixedWidth) {
    final word = widget.words[index];
    final isFocus = index == widget.sweepPosition;
    final isNearFocus = (index - widget.sweepPosition).abs() == 1;

    // P17 Grade C — sweep styling: focus, ±1, others
    final double opacity;
    if (isFocus) {
      opacity = 1.0;
    } else if (isNearFocus) {
      opacity = 0.7;
    } else {
      opacity = 0.5;
    }

    final style = isFocus
        ? SpeedyBoyTypography.readingAnchor(
            fontSize,
            color: SpeedyBoyTokens.stageAnchor.withAlpha(
              (opacity * 255).round(),
            ),
            fontFamily: widget.fontFamily,
          )
        : SpeedyBoyTypography.readingWord(
            fontSize,
            color: SpeedyBoyTokens.stageText.withAlpha((opacity * 255).round()),
            fontFamily: widget.fontFamily,
          );

    // Use fixed width measured at bold to prevent line-break jitter.
    return SizedBox(
      width: fixedWidth,
      child: Text(word, style: style),
    );
  }

  /// Minimal pause indicator — two small bars at the bottom center.
  // P17 Grade C — visual pause feedback during ContextReveal
  Widget _buildPauseIndicator() {
    const barWidth = 4.0;
    const barHeight = 18.0;
    const barGap = 5.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: barWidth,
          height: barHeight,
          decoration: BoxDecoration(
            color: SpeedyBoyTokens.stageText,
            borderRadius: BorderRadius.circular(barWidth * 0.4),
          ),
        ),
        const SizedBox(width: barGap),
        Container(
          width: barWidth,
          height: barHeight,
          decoration: BoxDecoration(
            color: SpeedyBoyTokens.stageText,
            borderRadius: BorderRadius.circular(barWidth * 0.4),
          ),
        ),
      ],
    );
  }
}
