import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/widgets/masked_reading_view.dart';

/// Paragraph mode — tri-zone line ruler.
///
/// Text glides bottom-to-top under a fixed reading band: the active line is
/// pinned at the band anchor with an accent ruler directly beneath it, and
/// neighbouring lines are masked so the eye never skips a line.
class ParagraphModeView extends StatelessWidget {
  /// Creates a [ParagraphModeView].
  const ParagraphModeView({
    super.key,
    required this.words,
    required this.currentIndex,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.fontFamily,
    required this.fontSize,
    required this.wpm,
    this.anchorColor = RunThruTokens.stageFocalRed,
    this.paragraphStarts = const {},
    this.wordOffset = 0,
  });

  /// Document-wide paragraph start indices (see [MaskedReadingView]).
  final Set<int> paragraphStarts;

  /// Document index of `words[0]`.
  final int wordOffset;

  /// Colour of the ORP letter on inked words (the reader's anchor setting).
  final Color anchorColor;

  static const Key readingLineKey = ValueKey('paragraph-mode-reading-line');

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

  /// Current reading speed. Used to time the active-word highlight sweep.
  final int wpm;

  @override
  Widget build(BuildContext context) {
    return MaskedReadingView(
      words: words,
      currentIndex: currentIndex,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      fontFamily: fontFamily,
      fontSize: fontSize,
      wpm: wpm,
      params: MaskedReadingParams.paragraph,
      semanticModeLabel: 'Paragraph mode',
      rulerKey: readingLineKey,
      anchorColor: anchorColor,
      paragraphStarts: paragraphStarts,
      wordOffset: wordOffset,
    );
  }
}
