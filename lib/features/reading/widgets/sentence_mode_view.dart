import 'package:flutter/material.dart';
import 'package:runthru/design/typography.dart';

/// Displays the current sentence in full, centered in the viewport.
///
/// The current word is highlighted with bold + underline (not color-only).
/// The WordTimerNotifier continues advancing word-by-word; this view just
/// shows the full sentence for context.
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

  @override
  Widget build(BuildContext context) {
    if (currentIndex >= words.length || words.isEmpty) {
      return const Center(child: Text(''));
    }
    final (start, end) = _findSentenceBounds(words, currentIndex);
    final sentence = words.sublist(start, end + 1);
    final baseStyle = RunThruTypography.body.copyWith(
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      fontFamily: fontFamily,
      fontSize: fontSize,
    );
    final List<InlineSpan> spans = [];
    for (int i = 0; i < sentence.length; i++) {
      final wordIdx = start + i;
      final isCurrent = wordIdx == currentIndex;
      spans.add(
        TextSpan(
          text: sentence[i] + (i < sentence.length - 1 ? ' ' : ''),
          style: isCurrent
              ? baseStyle.copyWith(
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                )
              : baseStyle,
        ),
      );
    }
    return Semantics(
      label: 'Sentence mode. Current word: ${words[currentIndex]}',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text.rich(
            TextSpan(children: spans),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Find the start and end indices (inclusive) of the sentence containing [wordIndex].
(int, int) _findSentenceBounds(List<String> words, int wordIndex) {
  int start = wordIndex;
  while (start > 0 && !_isSentenceEnd(words[start - 1])) {
    start--;
  }
  int end = wordIndex;
  while (end < words.length - 1 && !_isSentenceEnd(words[end])) {
    end++;
  }
  return (start, end);
}

bool _isSentenceEnd(String word) {
  return word.endsWith('.') || word.endsWith('!') || word.endsWith('?');
}
