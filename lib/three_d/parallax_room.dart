import 'package:flutter/material.dart';
import 'package:speedy_boy/core/word_transition.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/store/models.dart';
import 'package:speedy_boy/three_d/glyph_measurer.dart';
import 'package:speedy_boy/three_d/off_axis_projection.dart';
import 'package:speedy_boy/three_d/parallax_room_painter.dart';
import 'package:speedy_boy/three_d/parallax_word_painter.dart';
import 'package:speedy_boy/three_d/text_painter_pool.dart';

/// The full 3D room widget — composites the room painter,
/// word painter, and any overlay children (fog, dial, progress).
///
/// Static 3D marble box with word entrance animation.
class ParallaxRoom extends StatefulWidget {
  const ParallaxRoom({
    super.key,
    required this.headX,
    required this.headY,
    required this.currentWord,
    this.fontSize = 48,
    this.anchorColor,
    this.config,
    this.isPlaying = false,
    this.fontFamily = 'BricolageGrotesque',
    this.wpm = 300,
    this.intervalMs = 200,
    this.parallaxIntensity = ParallaxIntensity.subtle,
    this.child,
  });

  /// Head position in abstract room units (from HeadPositionNotifier).
  final double headX;
  final double headY;

  /// Current word to display.
  final String currentWord;

  /// Font size for word display.
  final double fontSize;

  /// ORP anchor color.
  final Color? anchorColor;

  /// Room geometry config (null = auto-detect from screen).
  final RoomConfig? config;

  /// Whether reading is currently playing (for focus mode).
  final bool isPlaying;

  /// Reading font family.
  final String fontFamily;

  /// Current reading speed in words per minute.
  final int wpm;

  /// Current word display interval in milliseconds.
  final int intervalMs;

  /// Controls the parallax rendering mode.
  // P7 Grade C — 4 rendering branches for room intensity
  final ParallaxIntensity parallaxIntensity;

  /// Overlay child (fog, dial, progress bar, etc.).
  final Widget? child;

  @override
  State<ParallaxRoom> createState() => _ParallaxRoomState();
}

class _ParallaxRoomState extends State<ParallaxRoom>
    with TickerProviderStateMixin {
  late final AnimationController _buildController;
  late final AnimationController _wordController;
  late final AnimationController _depthBounceController;
  late final Animation<double> _buildAnimation;
  late final Animation<double> _wordAnimation;
  late final Animation<double> _depthBounceAnimation;
  final TextPainterPool _painterPool = TextPainterPool();

  @override
  void initState() {
    super.initState();
    GlyphMeasurer.instance.setFontFamily(widget.fontFamily);
    GlyphMeasurer.instance.initialize();

    // Build-in animation: room constructs itself over ~1s
    _buildController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _buildAnimation = CurvedAnimation(
      parent: _buildController,
      curve: Curves.easeOutCubic,
    );

    // Word entrance animation (A-001: scale breathe)
    _wordController = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.wordAdvanceDuration,
    );
    _wordAnimation = CurvedAnimation(
      parent: _wordController,
      curve: SpeedyBoyAnimations.wordAdvanceCurve,
    );

    // Depth bounce animation (A-013: subtle forward Z motion)
    _depthBounceController = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.wordDepthBounceDuration,
    );
    _depthBounceAnimation = CurvedAnimation(
      parent: _depthBounceController,
      curve: SpeedyBoyAnimations.wordDepthBounceCurve,
    );

    // Start build animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reducedMotion = isReducedMotion(context);
      if (reducedMotion) {
        _buildController.value = 1.0;
      } else {
        _buildController.forward();
      }
    });
  }

  @override
  void didUpdateWidget(ParallaxRoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fontFamily != oldWidget.fontFamily) {
      GlyphMeasurer.instance.setFontFamily(widget.fontFamily);
    }
    if (widget.currentWord != oldWidget.currentWord) {
      if (mounted) {
        final reducedMotion = isReducedMotion(context);
        // P7 Grade C — off mode: snap animations, no motion
        final skipAnimations =
            widget.parallaxIntensity == ParallaxIntensity.off;
        if (!reducedMotion && !skipAnimations) {
          // P6 Grade A — select animation based on WPM and word length
          final result = selectWordTransition(
            wpm: widget.wpm,
            charCount: widget.currentWord.length,
            displayMs: widget.intervalMs,
          );

          _wordController.forward(from: 0);

          switch (result.transition) {
            case WordTransition.a001Breathe:
              // P6 Grade A — above threshold, skip depth bounce entirely
              break;
            case WordTransition.a013BounceIn:
              // P6 Grade A — at/below threshold, use capped depth bounce
              final staggerTotal =
                  SpeedyBoyAnimations.glyphStaggerMs *
                  (widget.currentWord.length - 1).clamp(0, 999);
              _depthBounceController.duration = Duration(
                milliseconds: result.baseDurationMs + staggerTotal,
              );
              _depthBounceController.forward(from: 0);
          }
        } else {
          _wordController.value = 1.0;
          _depthBounceController.value = 1.0;
        }
      }
    }
  }

  @override
  void dispose() {
    _buildController.dispose();
    _wordController.dispose();
    _depthBounceController.dispose();
    _painterPool.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final config = widget.config ?? RoomConfig.fromScreen(size);

          return ListenableBuilder(
            listenable: Listenable.merge([
              _buildAnimation,
              _wordAnimation,
              _depthBounceAnimation,
            ]),
            builder: (context, child) {
              // Focus dimming when playing
              final focusDim = widget.isPlaying ? 0.3 : 0.0;

              // P7 Grade C — compute effective head position per intensity
              final double effectiveHeadX;
              final double effectiveHeadY;
              switch (widget.parallaxIntensity) {
                case ParallaxIntensity.none:
                case ParallaxIntensity.off:
                  // Static room — no parallax motion
                  effectiveHeadX = 0;
                  effectiveHeadY = 0;
                case ParallaxIntensity.subtle:
                  // P7 Grade C — clamp to ≤2.5% displacement
                  effectiveHeadX = widget.headX.clamp(-0.025, 0.025);
                  effectiveHeadY = widget.headY.clamp(-0.025, 0.025);
                case ParallaxIntensity.full:
                  // P7 Grade C — clamp to ≤5% displacement
                  effectiveHeadX = widget.headX.clamp(-0.05, 0.05);
                  effectiveHeadY = widget.headY.clamp(-0.05, 0.05);
              }

              return Stack(
                children: [
                  // ── Room background + walls + grid ──
                  Positioned.fill(
                    child: CustomPaint(
                      painter: ParallaxRoomPainter(
                        headX: effectiveHeadX,
                        headY: effectiveHeadY,
                        config: config,
                        buildProgress: _buildAnimation.value,
                        focusDim: focusDim,
                      ),
                    ),
                  ),

                  // ── Word at depth ──
                  if (widget.currentWord.isNotEmpty)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: ParallaxWordPainter(
                          word: widget.currentWord,
                          fontSize: widget.fontSize,
                          headX: effectiveHeadX,
                          headY: effectiveHeadY,
                          config: config,
                          painterPool: _painterPool,
                          animationValue: _wordAnimation.value,
                          depthBounceValue: _depthBounceAnimation.value,
                          reducedMotion: isReducedMotion(context),
                          anchorColor: widget.anchorColor,
                          fontFamily: widget.fontFamily,
                        ),
                      ),
                    ),

                  // ── Overlay children (progress, fog, dial) ──
                  if (widget.child != null)
                    Positioned.fill(child: widget.child!),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
