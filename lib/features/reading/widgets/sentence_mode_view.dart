import 'package:flutter/material.dart';
import 'package:runthru/core/orp.dart';
import 'package:runthru/core/sentence_resolver.dart';
import 'package:runthru/design/design.dart';

/// Displays the active sentence as a right-to-left flowing horizontal strip.
///
/// This is still left-to-right text. The strip translates under a fixed center
/// anchor so the current word stays near the reader's focal point.
class SentenceModeView extends StatelessWidget {
  /// Creates a [SentenceModeView].
  const SentenceModeView({
    super.key,
    required this.words,
    required this.currentIndex,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.fontFamily,
    required this.fontSize,
  });

  /// All words in the current document/slice.
  final List<String> words;

  /// The current word index (from WordTimerState.currentIndex).
  final int currentIndex;

  /// Extra letter spacing from accessibility settings.
  final double letterSpacing;

  /// Extra word spacing from accessibility settings.
  final double wordSpacing;

  /// Font family from config (e.g., 'BricolageGrotesque').
  final String fontFamily;

  /// Dynamic font size.
  final double fontSize;

  static const Key stripKey = ValueKey('sentence-mode-strip');
  static const Key currentWordKey = ValueKey('sentence-mode-current-word');
  static const Key slideBuilderKey = ValueKey('sentence-mode-slide-builder');
  static const Key transformKey = ValueKey('sentence-mode-transform');
  static const Key fixedGuideKey = ValueKey('sentence-mode-fixed-guide');

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) {
      return const Center(child: Text(''));
    }

    final safeIndex = currentIndex.clamp(0, words.length - 1);
    final bounds = sentenceBoundsForWord(words, safeIndex);
    if (bounds.end < bounds.start) {
      return const Center(child: Text(''));
    }

    final sentence = words.sublist(bounds.start, bounds.end + 1);
    final sentenceCurrentIndex = safeIndex - bounds.start;
    final baseStyle = RunThruTypography.body.copyWith(
      color: RunThruTokens.stageText,
      letterSpacing: letterSpacing,
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: 1.15,
    );
    final currentStyle = baseStyle.copyWith(
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.underline,
      decorationColor: RunThruTokens.shellAccent,
      decorationThickness: 1.5,
    );

    return Semantics(
      label: 'Flowing sentence mode. Current word: ${words[safeIndex]}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = _measureSentence(
            sentence,
            currentIndex: sentenceCurrentIndex,
            baseStyle: baseStyle,
            currentStyle: currentStyle,
            textDirection: Directionality.of(context),
          );
          final anchorX = constraints.maxWidth / 2;
          final translationX = anchorX - metrics.currentAnchorX;
          final reducedMotion = isReducedMotion(context);

          final stageHeight = (fontSize * 1.6).clamp(64.0, 180.0);

          return ClipRect(
            child: Center(
              child: SizedBox(
                width: constraints.maxWidth,
                height: stageHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      key: slideBuilderKey,
                      tween: Tween<double>(
                        begin: translationX,
                        end: translationX,
                      ),
                      duration: reducedMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      builder: (context, animatedX, child) {
                        return Transform.translate(
                          key: transformKey,
                          offset: Offset(animatedX, 0),
                          child: child,
                        );
                      },
                      // OverflowBox lets the strip be wider than the viewport
                      // without triggering a RenderFlex overflow exception.
                      // ClipRect above handles the visual clipping.
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: 0,
                        maxWidth: double.infinity,
                        child: Row(
                          key: stripKey,
                          mainAxisSize: MainAxisSize.min,
                          textDirection: TextDirection.ltr,
                          children: _buildWordStrip(
                            sentence,
                            currentIndex: sentenceCurrentIndex,
                            baseStyle: baseStyle,
                            currentStyle: currentStyle,
                            spaceWidth: metrics.spaceWidth,
                          ),
                        ),
                      ),
                    ),
                    const IgnorePointer(
                      child: _FixedGuideLines(key: fixedGuideKey),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildWordStrip(
    List<String> sentence, {
    required int currentIndex,
    required TextStyle baseStyle,
    required TextStyle currentStyle,
    required double spaceWidth,
  }) {
    final children = <Widget>[];
    for (var i = 0; i < sentence.length; i++) {
      final isCurrent = i == currentIndex;
      children.add(
        isCurrent
            ? _AnchoredWord(
                key: currentWordKey,
                word: sentence[i],
                baseStyle: currentStyle,
              )
            : Text(
                sentence[i],
                key: ValueKey('sentence-mode-word-$i'),
                style: baseStyle.copyWith(
                  color: RunThruTokens.stageText.withValues(alpha: 0.28),
                ),
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
      );
      if (i < sentence.length - 1) {
        children.add(SizedBox(width: spaceWidth));
      }
    }
    return children;
  }

  _SentenceMetrics _measureSentence(
    List<String> sentence, {
    required int currentIndex,
    required TextStyle baseStyle,
    required TextStyle currentStyle,
    required TextDirection textDirection,
  }) {
    final spaceWidth =
        _measureText(' ', baseStyle, textDirection) + wordSpacing;
    var cursorX = 0.0;
    var currentAnchorX = 0.0;

    for (var i = 0; i < sentence.length; i++) {
      final style = i == currentIndex ? currentStyle : baseStyle;
      final word = sentence[i];
      final width = _measureText(word, style, textDirection);
      if (i == currentIndex) {
        currentAnchorX =
            cursorX + _measureAnchorOffset(word, style, textDirection);
      }
      cursorX += width;
      if (i < sentence.length - 1) {
        cursorX += spaceWidth;
      }
    }

    return _SentenceMetrics(
      currentAnchorX: currentAnchorX,
      spaceWidth: spaceWidth,
    );
  }

  double _measureAnchorOffset(
    String word,
    TextStyle style,
    TextDirection textDirection,
  ) {
    if (word.isEmpty) return 0;
    final anchorIndex = _anchorIndexForWord(word);
    final prefix = word.substring(0, anchorIndex);
    final anchor = word.substring(anchorIndex, anchorIndex + 1);
    return _measureText(prefix, style, textDirection) +
        _measureText(anchor, style, textDirection) / 2;
  }

  double _measureText(
    String text,
    TextStyle style,
    TextDirection textDirection,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}

class _AnchoredWord extends StatelessWidget {
  const _AnchoredWord({super.key, required this.word, required this.baseStyle});

  final String word;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final anchorIndex = _anchorIndexForWord(word);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: RunThruTokens.shellAccent.withValues(alpha: 0.84),
            width: 2.4,
          ),
        ),
      ),
      child: RichText(
        textScaler: TextScaler.noScaling,
        text: TextSpan(
          style: baseStyle.copyWith(decoration: TextDecoration.none),
          children: [
            TextSpan(text: word.substring(0, anchorIndex)),
            TextSpan(
              text: word.substring(anchorIndex, anchorIndex + 1),
              style: baseStyle.copyWith(
                color: RunThruTokens.stageFocalRed,
                decoration: TextDecoration.none,
              ),
            ),
            TextSpan(text: word.substring(anchorIndex + 1)),
          ],
        ),
      ),
    );
  }
}

class _FixedGuideLines extends StatelessWidget {
  const _FixedGuideLines({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = (constraints.maxHeight - 36).clamp(18.0, 52.0);
        return SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _GuideLine(color: RunThruTokens.shellAccent),
              SizedBox(height: gap),
              const _GuideLine(color: RunThruTokens.shellAccent),
            ],
          ),
        );
      },
    );
  }
}

class _GuideLine extends StatelessWidget {
  const _GuideLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const SizedBox(width: 2, height: 18),
    );
  }
}

class _SentenceMetrics {
  const _SentenceMetrics({
    required this.currentAnchorX,
    required this.spaceWidth,
  });

  final double currentAnchorX;
  final double spaceWidth;
}

int _anchorIndexForWord(String word) {
  if (word.isEmpty) return 0;
  final stripped = word.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (stripped.isEmpty) return 0;
  final leadingPunctuation = word.indexOf(stripped);
  final orpIndex = bucketedOrpIndex(stripped);
  return (leadingPunctuation < 0 ? orpIndex : leadingPunctuation + orpIndex)
      .clamp(0, word.length - 1);
}
