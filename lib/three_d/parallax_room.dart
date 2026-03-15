import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';
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

  /// Overlay child (fog, dial, progress bar, etc.).
  final Widget? child;

  @override
  State<ParallaxRoom> createState() => _ParallaxRoomState();
}

class _ParallaxRoomState extends State<ParallaxRoom>
    with TickerProviderStateMixin {
  late final AnimationController _buildController;
  late final AnimationController _wordController;
  late final Animation<double> _buildAnimation;
  late final Animation<double> _wordAnimation;
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

    // Word entrance animation
    _wordController = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.wordAdvanceDuration,
    );
    _wordAnimation = CurvedAnimation(
      parent: _wordController,
      curve: SpeedyBoyAnimations.wordAdvanceCurve,
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
        if (!reducedMotion) {
          _wordController.forward(from: 0);
        } else {
          _wordController.value = 1.0;
        }
      }
    }
  }

  @override
  void dispose() {
    _buildController.dispose();
    _wordController.dispose();
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

          return AnimatedBuilder(
            animation: Listenable.merge([
              _buildAnimation,
              _wordAnimation,
            ]),
            builder: (context, child) {
              // Focus dimming when playing
              final focusDim = widget.isPlaying ? 0.3 : 0.0;

              return Stack(
                children: [
                  // ── Room background + walls + grid ──
                  Positioned.fill(
                    child: CustomPaint(
                      painter: ParallaxRoomPainter(
                        headX: 0,
                        headY: 0,
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
                          headX: 0,
                          headY: 0,
                          config: config,
                          painterPool: _painterPool,
                          animationValue: _wordAnimation.value,
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
