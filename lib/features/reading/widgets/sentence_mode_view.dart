import 'package:flutter/material.dart';
import 'package:runthru/core/orp.dart';
import 'package:runthru/core/sentence_resolver.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/widgets/reading_focus_chrome.dart';

/// Sentence mode: karaoke colour-sync on one re-centering line.
///
/// Matches the design reference (`modes-views.jsx` SentenceView): the active
/// sentence sits on a single line that slides under fixed fixation ticks so
/// the eyes stay put. Read words are inked with the ORP letter accented, the
/// active word fills left to right over its dwell time, upcoming words are
/// faint, and both edges fade out. The line centres on the active word's ORP
/// letter so it lines up with the single-word RSVP focal point.
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
    this.wpm = 300,
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

  /// Current reading speed; times the active word's karaoke fill.
  final int wpm;

  /// Fraction of the width faded at each edge (design: 16%).
  static const double edgeFade = 0.16;

  static const Key stripKey = ValueKey('sentence-mode-strip');
  static const Key currentWordKey = ValueKey('sentence-mode-current-word');
  static const Key slideBuilderKey = ValueKey('sentence-mode-slide-builder');
  static const Key transformKey = ValueKey('sentence-mode-transform');
  static const Key fixedGuideKey = ValueKey('sentence-mode-fixed-guide');
  static const Key edgeFadeKey = ValueKey('sentence-mode-edge-fade');

  Duration get _sweepDuration {
    final safeWpm = wpm.clamp(30, 1000);
    return Duration(milliseconds: (60000 / safeWpm).round());
  }

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
    // One weight for every state so measurement and render agree and the
    // line never shifts when a word changes state.
    final faintStyle = RunThruTypography.body.copyWith(
      color: RunThruTokens.stageText.withValues(alpha: 0.25),
      letterSpacing: letterSpacing,
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: 1.15,
    );
    final inkedStyle = faintStyle.copyWith(color: RunThruTokens.stageText);

    return Semantics(
      label: 'Flowing sentence mode. Current word: ${words[safeIndex]}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = _measureSentence(
            sentence,
            currentIndex: sentenceCurrentIndex,
            style: faintStyle,
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
                            sentenceStart: bounds.start,
                            currentIndex: sentenceCurrentIndex,
                            faintStyle: faintStyle,
                            inkedStyle: inkedStyle,
                            spaceWidth: metrics.spaceWidth,
                            reduced: reducedMotion,
                          ),
                        ),
                      ),
                    ),
                    const IgnorePointer(child: _EdgeFade(key: edgeFadeKey)),
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
    required int sentenceStart,
    required int currentIndex,
    required TextStyle faintStyle,
    required TextStyle inkedStyle,
    required double spaceWidth,
    required bool reduced,
  }) {
    final children = <Widget>[];
    for (var i = 0; i < sentence.length; i++) {
      final state = i == currentIndex
          ? KaraokeWordState.active
          : i < currentIndex
          ? KaraokeWordState.done
          : KaraokeWordState.next;
      children.add(
        KaraokeWord(
          key: i == currentIndex
              ? currentWordKey
              : ValueKey('sentence-mode-word-$i'),
          word: sentence[i],
          globalIndex: sentenceStart + i,
          state: state,
          faintStyle: faintStyle,
          inkedStyle: inkedStyle,
          sweepDuration: _sweepDuration,
          reduced: reduced,
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
    required TextStyle style,
    required TextDirection textDirection,
  }) {
    final spaceWidth = _measureText(' ', style, textDirection) + wordSpacing;
    var cursorX = 0.0;
    var currentAnchorX = 0.0;

    for (var i = 0; i < sentence.length; i++) {
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

/// Fades both ends of the line into the stage, as in the design's
/// 16%/84% horizontal mask, so the sentence reads as one centred line.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({super.key});

  @override
  Widget build(BuildContext context) {
    final clear = RunThruTokens.stageBase.withValues(alpha: 0);
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              RunThruTokens.stageBase,
              clear,
              clear,
              RunThruTokens.stageBase,
            ],
            stops: const [
              0,
              SentenceModeView.edgeFade,
              1 - SentenceModeView.edgeFade,
              1,
            ],
          ),
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
