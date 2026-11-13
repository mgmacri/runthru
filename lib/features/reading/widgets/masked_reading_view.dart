import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/widgets/reading_focus_chrome.dart';

/// Per-mode masking geometry for the continuous-text reading modes.
///
/// Mirrors the design spec's MaskedScroller params (modes-views.jsx):
/// Paragraph uses a tri-zone line ruler (active line lit, neighbours
/// masked); Full Page uses a stepless moving spotlight band.
class MaskedReadingParams {
  const MaskedReadingParams({
    required this.fontScale,
    required this.minFontSize,
    required this.maxFontSize,
    required this.lineHeight,
    required this.bandLines,
    required this.dim,
    required this.feather,
    required this.showRuler,
    required this.anchorPct,
    required this.pad,
  });

  /// Multiplier applied to the dynamic stage font size.
  final double fontScale;

  /// Clamp bounds for the derived font size.
  final double minFontSize;
  final double maxFontSize;

  /// Text line height multiplier.
  final double lineHeight;

  /// Clear reading-band height in line heights.
  final double bandLines;

  /// Mask opacity over the non-active zones (0..1).
  final double dim;

  /// Soft gradient falloff above/below the band, in logical pixels.
  final double feather;

  /// Tri-zone ruler accents (Paragraph) vs spotlight glow (Full Page).
  final bool showRuler;

  /// Vertical anchor of the reading band as a fraction of stage height.
  final double anchorPct;

  /// Horizontal text padding.
  final double pad;

  /// Paragraph mode — tri-zone line ruler (design: fontSize 23 @ 360w,
  /// lineHeight 1.62, band 1.2 lines, dim 0.8, feather 20, anchor 42%).
  static const MaskedReadingParams paragraph = MaskedReadingParams(
    fontScale: 1.17,
    minFontSize: 20,
    maxFontSize: 30,
    lineHeight: 1.62,
    bandLines: 1.2,
    dim: 0.8,
    feather: 20,
    showRuler: true,
    anchorPct: 0.42,
    pad: 30,
  );

  /// Full Page mode — moving spotlight (design: fontSize 15.5 @ 360w,
  /// lineHeight 1.74, band 3 lines, dim 0.92, feather 30, anchor 46%).
  static const MaskedReadingParams fullPage = MaskedReadingParams(
    fontScale: 0.79,
    minFontSize: 14,
    maxFontSize: 19,
    lineHeight: 1.74,
    bandLines: 3,
    dim: 0.92,
    feather: 30,
    showRuler: false,
    anchorPct: 0.46,
    pad: 26,
  );
}

/// Continuous text that glides bottom-to-top under a fixed reading band.
///
/// The active line's vertical midpoint is pinned to the band anchor; as the
/// reading head advances to the next line the whole passage translates up,
/// so the eyes never move. Words use karaoke color-sync: read words are
/// inked (with the ORP letter accented), the active word fills left→right
/// in step with its dwell time, upcoming words stay faint.
class MaskedReadingView extends StatelessWidget {
  const MaskedReadingView({
    super.key,
    required this.words,
    required this.currentIndex,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.fontFamily,
    required this.fontSize,
    required this.wpm,
    required this.params,
    required this.semanticModeLabel,
    this.rulerKey,
    this.anchorColor = RunThruTokens.stageFocalRed,
    this.paragraphStarts = const {},
    this.wordOffset = 0,
  });

  /// Colour of the ORP letter on inked words (the reader's anchor setting).
  final Color anchorColor;

  /// Document-wide word indices that start a paragraph. Empty for documents
  /// extracted before paragraph data existed (falls back to heuristics).
  final Set<int> paragraphStarts;

  /// Document index of `words[0]` (non-zero when reading a page range).
  final int wordOffset;

  /// Tri-zone mask overlay key (for tests).
  static const Key maskKey = ValueKey('masked-reading-tri-zone-mask');

  /// Spotlight band key (for tests).
  static const Key spotlightKey = ValueKey('masked-reading-spotlight');

  /// Left band accent bar key (for tests).
  static const Key bandBarKey = ValueKey('masked-reading-band-bar');

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

  /// Dynamic stage font size (already system-text-scale adjusted).
  final double fontSize;

  /// Current reading speed — times the active-word karaoke fill.
  final int wpm;

  /// Masking geometry for this mode.
  final MaskedReadingParams params;

  /// Spoken mode name, e.g. 'Paragraph mode'.
  final String semanticModeLabel;

  /// Optional key for the ruler underline accent.
  final Key? rulerKey;

  /// Whether a line centred at [lineMid] (stage coordinates) sits in the
  /// clear reading band, with a quarter-line tolerance for rounding.
  static bool _inBand(
    double lineMid,
    double bandTop,
    double bandBottom,
    double lineHeight,
  ) =>
      lineMid >= bandTop - lineHeight * 0.25 &&
      lineMid <= bandBottom + lineHeight * 0.25;

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
    final reduced = isReducedMotion(context);
    final direction = Directionality.of(context);

    final fs = (fontSize * params.fontScale).clamp(
      params.minFontSize,
      params.maxFontSize,
    );
    final lh = fs * params.lineHeight;
    final faintStyle = RunThruTypography.body.copyWith(
      color: RunThruTokens.stageText.withValues(alpha: 0.25),
      letterSpacing: letterSpacing,
      fontFamily: fontFamily,
      fontSize: fs,
      fontWeight: FontWeight.w600,
      height: params.lineHeight,
    );
    final inkedStyle = faintStyle.copyWith(color: RunThruTokens.stageText);

    return Semantics(
      label: '$semanticModeLabel. Current word: ${words[safeIndex]}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stageH = constraints.maxHeight;
          final maxLineWidth = (constraints.maxWidth - params.pad * 2).clamp(
            120.0,
            double.infinity,
          );

          final paragraphs = paragraphStarts.isEmpty
              ? _windowParagraphs(words, safeIndex)
              : _windowParagraphsFromStarts(
                  words,
                  safeIndex,
                  (i) => i == 0 || paragraphStarts.contains(i + wordOffset),
                );
          final lines = _measureLines(
            paragraphs: paragraphs,
            maxWidth: maxLineWidth,
            style: faintStyle,
            lineHeight: lh,
            textDirection: direction,
          );
          if (lines.isEmpty) return const Center(child: Text(''));

          final activeLine = _activeLine(lines, safeIndex);
          final anchorY = stageH * params.anchorPct;
          final translateY = anchorY - activeLine.mid;

          final band = params.bandLines * lh;
          final bandTop = anchorY - band / 2;
          final bandBottom = anchorY + band / 2;
          final maskColor = RunThruTokens.stageBase.withValues(
            alpha: params.dim,
          );
          final clearColor = RunThruTokens.stageBase.withValues(alpha: 0);
          final featherTop = ((bandTop - params.feather) / stageH).clamp(
            0.0,
            1.0,
          );
          final clearTop = (bandTop / stageH).clamp(featherTop, 1.0);
          final clearBottom = (bandBottom / stageH).clamp(clearTop, 1.0);
          final featherBottom = ((bandBottom + params.feather) / stageH).clamp(
            clearBottom,
            1.0,
          );

          return ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: params.pad,
                  right: params.pad,
                  top: 0,
                  child: AnimatedContainer(
                    duration: reduced
                        ? Duration.zero
                        : const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.translationValues(0, translateY, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in lines) ...[
                          if (line.gapBefore > 0)
                            SizedBox(height: line.gapBefore),
                          // Accent ORP letters only on lines inside the clear
                          // band. Under the dim mask they turn into pink
                          // speckles that pull the eye away from the band.
                          // A single token wider than the column (a URL, a
                          // long compound) cannot wrap: shrink that line to
                          // fit instead of running off the edge.
                          SizedBox(
                            height: lh,
                            width: maxLineWidth,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final word in line.words) ...[
                                    if (word.spaceBefore > 0)
                                      SizedBox(width: word.spaceBefore),
                                    KaraokeWord(
                                      word: word.word,
                                      globalIndex: word.globalIndex,
                                      state: word.globalIndex == safeIndex
                                          ? KaraokeWordState.active
                                          : word.globalIndex < safeIndex
                                          ? KaraokeWordState.done
                                          : KaraokeWordState.next,
                                      faintStyle: faintStyle,
                                      inkedStyle: inkedStyle,
                                      sweepDuration: _sweepDuration,
                                      reduced: reduced,
                                      anchorColor:
                                          _inBand(
                                            line.mid + translateY,
                                            bandTop,
                                            bandBottom,
                                            lh,
                                          )
                                          ? anchorColor
                                          : inkedStyle.color!,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Tri-zone mask: opaque top & bottom zones, clear reading band.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: DecoratedBox(
                        key: maskKey,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              maskColor,
                              maskColor,
                              clearColor,
                              clearColor,
                              maskColor,
                              maskColor,
                            ],
                            stops: [
                              0,
                              featherTop,
                              clearTop,
                              clearBottom,
                              featherBottom,
                              1,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (params.showRuler) ...[
                  // Reading-band underline directly beneath the active line.
                  Positioned(
                    left: 16,
                    right: 16,
                    top: bandBottom - 1,
                    height: 2.5,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: DecoratedBox(
                          key: rulerKey,
                          decoration: BoxDecoration(
                            color: RunThruTokens.shellAccent.withValues(
                              alpha: 0.9,
                            ),
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: RunThruTokens.shellAccent.withValues(
                                  alpha: 0.5,
                                ),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Left edge band marker.
                  Positioned(
                    left: 0,
                    top: bandTop,
                    width: 4,
                    height: band,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: DecoratedBox(
                          key: bandBarKey,
                          decoration: BoxDecoration(
                            color: RunThruTokens.shellAccent.withValues(
                              alpha: 0.55,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else
                  // Soft illuminated spotlight following the reading band.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: bandTop,
                    height: band,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: DecoratedBox(
                          key: spotlightKey,
                          // A full-width band, brightest on the reading line.
                          // (A RadialGradient here is sized by the band's
                          // short side, so it drew a small grey blot at the
                          // centre of the screen instead of a band.)
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                RunThruTokens.shellAccent.withValues(alpha: 0),
                                RunThruTokens.shellAccent.withValues(
                                  alpha: 0.07,
                                ),
                                RunThruTokens.shellAccent.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The line containing [index], falling back to the nearest earlier line.
  _LineData _activeLine(List<_LineData> lines, int index) {
    _LineData best = lines.first;
    for (final line in lines) {
      if (line.contains(index)) return line;
      if (line.words.first.globalIndex <= index) best = line;
    }
    return best;
  }

  /// Greedy line layout over the window paragraphs, accumulating each
  /// line's vertical midpoint (paragraphs separated by a 0.55-line gap).
  List<_LineData> _measureLines({
    required List<List<_WindowWord>> paragraphs,
    required double maxWidth,
    required TextStyle style,
    required double lineHeight,
    required TextDirection textDirection,
  }) {
    final lines = <_LineData>[];
    final spaceWidth =
        _measureText(' ', style, textDirection) + wordSpacing.clamp(0.0, 80.0);
    var y = 0.0;

    for (var p = 0; p < paragraphs.length; p++) {
      final gapBefore = p == 0 ? 0.0 : lineHeight * 0.55;
      var isFirstLineOfParagraph = true;
      final current = <_LineWord>[];
      var currentWidth = 0.0;

      void flush() {
        if (current.isEmpty) return;
        final gap = isFirstLineOfParagraph ? gapBefore : 0.0;
        y += gap;
        lines.add(
          _LineData(
            words: List<_LineWord>.unmodifiable(current),
            gapBefore: gap,
            mid: y + lineHeight / 2,
          ),
        );
        y += lineHeight;
        isFirstLineOfParagraph = false;
        current.clear();
        currentWidth = 0;
      }

      for (final word in paragraphs[p]) {
        final width = _measureText(word.word, style, textDirection);
        final nextWidth = current.isEmpty
            ? width
            : currentWidth + spaceWidth + width;
        if (current.isNotEmpty && nextWidth > maxWidth) flush();
        current.add(
          _LineWord(
            word: word.word,
            globalIndex: word.globalIndex,
            spaceBefore: current.isEmpty ? 0 : spaceWidth,
          ),
        );
        currentWidth = current.length == 1 ? width : nextWidth;
      }
      flush();
    }
    return lines;
  }

  double _measureText(String text, TextStyle style, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}

/// Paragraphs surrounding [wordIndex]: previous, current, and next, so
/// upcoming lines are visible below the band and read lines fade above it.
List<List<_WindowWord>> _windowParagraphs(List<String> words, int wordIndex) {
  final (start, end) = _paragraphBounds(words, wordIndex);

  var windowStart = start;
  var i = start - 1;
  while (i >= 0 && _isParagraphBoundary(words[i])) {
    i--;
  }
  if (i >= 0) windowStart = _paragraphBounds(words, i).$1;

  var windowEnd = end;
  i = end + 1;
  while (i < words.length && _isParagraphBoundary(words[i])) {
    i++;
  }
  if (i < words.length) windowEnd = _paragraphBounds(words, i).$2;

  final paragraphs = <List<_WindowWord>>[];
  var current = <_WindowWord>[];
  for (var j = windowStart; j <= windowEnd; j++) {
    if (_isParagraphBoundary(words[j])) {
      if (current.isNotEmpty) {
        paragraphs.add(current);
        current = <_WindowWord>[];
      }
      continue;
    }
    current.add(_WindowWord(words[j].trim(), j));
  }
  if (current.isNotEmpty) paragraphs.add(current);
  return paragraphs;
}

/// The longest run of words laid out as one paragraph. Text with no
/// paragraph breaks at all (pasted or shared text whose paragraphs are
/// separated by single line breaks) is otherwise one paragraph as long as
/// the document, and the window, which is measured again on every word,
/// would be the whole document.
const int _maxParagraphWords = 200;

/// Whether a paragraph, or a piece of an overlong one, starts at [index].
///
/// A paragraph that has run for [_maxParagraphWords] words without a break
/// is cut at each multiple of that many words. The cuts depend only on the
/// document, never on where the reader is, so the lines stay where they
/// are as the reader advances.
bool _startsPiece(int index, bool Function(int index) isStart) {
  if (isStart(index)) return true;
  if (index % _maxParagraphWords != 0) return false;
  for (var i = index - 1; i > index - _maxParagraphWords && i > 0; i--) {
    if (isStart(i)) return false;
  }
  return true;
}

/// Real paragraphs around [wordIndex]: whole paragraphs (pieces of them
/// where one is overlong, see [_startsPiece]) until there are at least
/// [before] words above and [after] words below the current word, so a
/// short heading never leaves the page nearly empty.
List<List<_WindowWord>> _windowParagraphsFromStarts(
  List<String> words,
  int wordIndex,
  bool Function(int index) isParagraphStart, {
  int before = 120,
  int after = 220,
}) {
  bool isStart(int index) => _startsPiece(index, isParagraphStart);

  var start = wordIndex;
  while (start > 0 && !isStart(start)) {
    start--;
  }
  // Extend back by whole paragraphs.
  while (start > 0 && wordIndex - start < before) {
    start--;
    while (start > 0 && !isStart(start)) {
      start--;
    }
  }
  var end = wordIndex;
  // Extend forward to the end of a paragraph past the target.
  while (end < words.length - 1 &&
      (end - wordIndex < after || !isStart(end + 1))) {
    end++;
  }

  final paragraphs = <List<_WindowWord>>[];
  var current = <_WindowWord>[];
  for (var j = start; j <= end; j++) {
    if (j != start && isStart(j) && current.isNotEmpty) {
      paragraphs.add(current);
      current = <_WindowWord>[];
    }
    final word = words[j].trim();
    if (word.isNotEmpty) current.add(_WindowWord(word, j));
  }
  if (current.isNotEmpty) paragraphs.add(current);
  return paragraphs;
}

/// Find start and end of the paragraph containing [wordIndex].
///
/// Paragraphs are separated by empty-string entries or words that start
/// with '\n'. Falls back to 50-word chunks if no boundaries exist.
(int, int) _paragraphBounds(List<String> words, int wordIndex) {
  final hasBoundaries = words.any(_isParagraphBoundary);
  if (!hasBoundaries) {
    final chunkStart = (wordIndex ~/ 50) * 50;
    final chunkEnd = (chunkStart + 49).clamp(0, words.length - 1);
    return (chunkStart, chunkEnd);
  }
  var start = wordIndex;
  while (start > 0 && !_isParagraphBoundary(words[start - 1])) {
    start--;
  }
  var end = wordIndex;
  while (end < words.length - 1 && !_isParagraphBoundary(words[end + 1])) {
    end++;
  }
  return (start, end);
}

bool _isParagraphBoundary(String word) {
  return word.trim().isEmpty || word.startsWith('\n');
}

class _WindowWord {
  const _WindowWord(this.word, this.globalIndex);

  final String word;
  final int globalIndex;
}

class _LineWord {
  const _LineWord({
    required this.word,
    required this.globalIndex,
    required this.spaceBefore,
  });

  final String word;
  final int globalIndex;
  final double spaceBefore;
}

class _LineData {
  const _LineData({
    required this.words,
    required this.gapBefore,
    required this.mid,
  });

  final List<_LineWord> words;

  /// Paragraph gap rendered above this line (0 within a paragraph).
  final double gapBefore;

  /// Vertical midpoint of this line within the content column.
  final double mid;

  bool contains(int index) => words.any((w) => w.globalIndex == index);
}
