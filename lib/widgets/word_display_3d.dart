import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';
import 'package:speedy_boy/three_d/glyph_measurer.dart';
import 'package:speedy_boy/three_d/word_painter.dart';

/// 3D extruded word display widget with A-001 breathe animation.
class WordDisplay3D extends StatefulWidget {
  const WordDisplay3D({
    super.key,
    required this.word,
    required this.fontSize,
    this.anchorColor,
  });

  final String word;
  final double fontSize;
  final Color? anchorColor;

  @override
  State<WordDisplay3D> createState() => _WordDisplay3DState();
}

class _WordDisplay3DState extends State<WordDisplay3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    GlyphMeasurer.instance.initialize();
    _controller = AnimationController(
      vsync: this,
      duration: SpeedyBoyAnimations.wordAdvanceDuration,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: SpeedyBoyAnimations.wordAdvanceCurve,
    );
  }

  @override
  void didUpdateWidget(WordDisplay3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.word != oldWidget.word) {
      final reducedMotion = isReducedMotion(context);
      if (!reducedMotion) {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          return CustomPaint(
            painter: WordPainter(
              word: widget.word,
              fontSize: widget.fontSize,
              animationValue: _animation.value,
              anchorColor: widget.anchorColor,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}
