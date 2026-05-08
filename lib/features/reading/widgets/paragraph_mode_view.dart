import 'package:flutter/material.dart';
import 'package:runthru/design/typography.dart';

/// Displays the current paragraph in full with current word highlighted.
///
/// Paragraphs are identified by scanning for empty-string entries or
/// words starting with newline characters. Falls back to ~50-word chunks
/// if no paragraph boundaries exist.
class ParagraphModeView extends StatefulWidget {
  /// Creates a [ParagraphModeView].
  const ParagraphModeView({
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
  State<ParagraphModeView> createState() => _ParagraphModeViewState();
}

class _ParagraphModeViewState extends State<ParagraphModeView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _wordKeys = {};

  @override
  void didUpdateWidget(covariant ParagraphModeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentWord());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentWord());
  }

  void _scrollToCurrentWord() {
    final key = _wordKeys[widget.currentIndex];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 200),
        alignment: 0.5,
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentIndex >= widget.words.length || widget.words.isEmpty) {
      return const Center(child: Text(''));
    }
    final (start, end) = _findParagraphBounds(
      widget.words,
      widget.currentIndex,
    );
    final paragraph = widget.words.sublist(start, end + 1);
    final baseStyle = RunThruTypography.body.copyWith(
      letterSpacing: widget.letterSpacing,
      wordSpacing: widget.wordSpacing,
      fontFamily: widget.fontFamily,
      fontSize: widget.fontSize,
      height: 1.6,
    );
    final List<InlineSpan> spans = [];
    for (int i = 0; i < paragraph.length; i++) {
      final wordIdx = start + i;
      final isCurrent = wordIdx == widget.currentIndex;
      final key = isCurrent ? (_wordKeys[wordIdx] ??= GlobalKey()) : null;
      spans.add(
        WidgetSpan(
          child: key != null
              ? Container(
                  key: key,
                  child: Text(
                    paragraph[i] + (i < paragraph.length - 1 ? ' ' : ''),
                    style: isCurrent
                        ? baseStyle.copyWith(
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          )
                        : baseStyle,
                  ),
                )
              : Text(
                  paragraph[i] + (i < paragraph.length - 1 ? ' ' : ''),
                  style: isCurrent
                      ? baseStyle.copyWith(
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        )
                      : baseStyle,
                ),
        ),
      );
    }
    return Semantics(
      label:
          'Paragraph mode. Current word: ${widget.words[widget.currentIndex]}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Text.rich(
            TextSpan(children: spans),
            textAlign: TextAlign.left,
          ),
        ),
      ),
    );
  }
}

/// Find start and end of the paragraph containing [wordIndex].
///
/// Paragraphs are separated by empty-string entries or words that
/// start with '\n'. Falls back to 50-word chunks if no boundaries found.
(int, int) _findParagraphBounds(List<String> words, int wordIndex) {
  final bool hasBoundaries = words.any((w) => w.isEmpty || w.startsWith('\n'));
  if (!hasBoundaries) {
    final int chunkStart = (wordIndex ~/ 50) * 50;
    final int chunkEnd = (chunkStart + 49).clamp(0, words.length - 1);
    return (chunkStart, chunkEnd);
  }
  int start = wordIndex;
  while (start > 0 && !_isParagraphBoundary(words[start - 1])) {
    start--;
  }
  int end = wordIndex;
  while (end < words.length - 1 && !_isParagraphBoundary(words[end + 1])) {
    end++;
  }
  return (start, end);
}

bool _isParagraphBoundary(String word) {
  return word.isEmpty || word == '\n' || word.startsWith('\n\n');
}
