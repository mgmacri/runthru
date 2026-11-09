import 'package:flutter/material.dart';
import 'package:runthru/features/reading/widgets/masked_reading_view.dart';

/// Full Page mode — stepless moving spotlight.
///
/// The page dims and a soft illuminated band follows the reading line,
/// keeping peripheral context in view while the text glides bottom-to-top
/// under the fixed band.
class FullPageModeView extends StatelessWidget {
  /// Creates a [FullPageModeView].
  const FullPageModeView({
    super.key,
    required this.words,
    required this.currentIndex,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.fontFamily,
    required this.fontSize,
    required this.wpm,
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
      params: MaskedReadingParams.fullPage,
      semanticModeLabel: 'Full page mode',
    );
  }
}
