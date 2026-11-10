import 'package:flutter/material.dart';
import 'package:runthru/core/orp.dart';
import 'package:runthru/design/design.dart';

/// Splits [word] into spans with the ORP (optimal recognition point)
/// letter tinted in [anchorColor]. Shared by the continuous-text reading
/// modes for inked (read/active) words. Words without letters (a lone dash)
/// get no tint.
List<InlineSpan> anchoredWordSpans(
  String word,
  TextStyle style, {
  Color anchorColor = RunThruTokens.stageFocalRed,
}) {
  final anchorIndex = anchorIndexInWord(word);
  if (anchorIndex < 0) return [TextSpan(text: word, style: style)];
  return [
    TextSpan(text: word.substring(0, anchorIndex), style: style),
    TextSpan(
      text: word.substring(anchorIndex, anchorIndex + 1),
      style: style.copyWith(color: anchorColor),
    ),
    TextSpan(text: word.substring(anchorIndex + 1), style: style),
  ];
}

/// Reading state of one word in the continuous-text modes.
enum KaraokeWordState {
  /// Already read: inked, ORP letter accented.
  done,

  /// Being read: fills left to right over its dwell time.
  active,

  /// Not yet read: faint.
  next,
}

/// Karaoke color-sync word: read words are inked with the ORP letter
/// accented; the active word fills left→right over its dwell time with an
/// accent underline; upcoming words stay faint.
class KaraokeWord extends StatelessWidget {
  /// Creates a karaoke word.
  const KaraokeWord({
    super.key,
    required this.word,
    required this.globalIndex,
    required this.state,
    required this.faintStyle,
    required this.inkedStyle,
    required this.sweepDuration,
    required this.reduced,
    this.anchorColor = RunThruTokens.stageFocalRed,
  });

  /// Colour of the ORP letter on inked words (the reader's anchor setting).
  final Color anchorColor;

  /// The word text.
  final String word;

  /// Index of the word in the document (keys the fill animation).
  final int globalIndex;

  /// Reading state.
  final KaraokeWordState state;

  /// Style for unread text.
  final TextStyle faintStyle;

  /// Style for read text; must share metrics with [faintStyle].
  final TextStyle inkedStyle;

  /// Dwell time for the active word's fill.
  final Duration sweepDuration;

  /// Reduced motion: the active word is shown fully inked at once.
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case KaraokeWordState.next:
        return Text(
          word,
          style: faintStyle,
          softWrap: false,
          textScaler: TextScaler.noScaling,
        );
      case KaraokeWordState.done:
        return RichText(
          textScaler: TextScaler.noScaling,
          softWrap: false,
          text: TextSpan(
            children: anchoredWordSpans(
              word,
              inkedStyle,
              anchorColor: anchorColor,
            ),
          ),
        );
      case KaraokeWordState.active:
        final inked = RichText(
          textScaler: TextScaler.noScaling,
          softWrap: false,
          text: TextSpan(
            children: anchoredWordSpans(
              word,
              inkedStyle,
              anchorColor: anchorColor,
            ),
          ),
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Text(
              word,
              style: faintStyle,
              softWrap: false,
              textScaler: TextScaler.noScaling,
            ),
            // Inked overlay wipes in left→right over the word's dwell time.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: TweenAnimationBuilder<double>(
                key: ValueKey('karaoke-fill-$globalIndex'),
                tween: Tween(begin: 0, end: 1),
                duration: reduced ? Duration.zero : sweepDuration,
                curve: Curves.linear,
                child: inked,
                builder: (context, value, child) {
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: value,
                      child: child,
                    ),
                  );
                },
              ),
            ),
            Positioned(
              key: ValueKey('paragraph-word-highlight-$globalIndex'),
              left: 0,
              right: 0,
              bottom: -3,
              height: 2.5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: RunThruTokens.shellAccent.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        );
    }
  }
}
