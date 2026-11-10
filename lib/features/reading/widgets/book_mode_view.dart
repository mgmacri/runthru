import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:runthru/core/time_left.dart';
import 'package:runthru/design/design.dart';

/// Book mode: a calm, paged view the reader turns themselves, like an
/// e-reader. No timer runs.
///
/// The page always begins at [startIndex] (the shared reading position), so
/// switching to Word mode resumes at the top of the page being read. Turning
/// a page reports the new first word through [onTurn]; the owner moves the
/// reading position there and rebuilds this view.
///
/// Pagination measures with the exact painter settings used to render, and
/// breaks only between lines, so a line is never cut in half.
class BookModeView extends StatefulWidget {
  /// Creates a [BookModeView].
  const BookModeView({
    super.key,
    required this.words,
    required this.startIndex,
    required this.onTurn,
    required this.fontFamily,
    required this.fontSize,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.wpm,
    required this.onFontSizeChanged,
    this.paragraphStarts = const {},
    this.chapterStarts = const {},
    this.wordOffset = 0,
    this.totalWords,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  /// Words of the current document or slice.
  final List<String> words;

  /// Index into [words] of the first word on the page.
  final int startIndex;

  /// Called with the first word index of the page turned to.
  final ValueChanged<int> onTurn;

  /// Reading font family.
  final String fontFamily;

  /// Text size before system text scale.
  final double fontSize;

  /// Extra letter spacing from Settings.
  final double letterSpacing;

  /// Extra word spacing from Settings.
  final double wordSpacing;

  /// Reading speed, used only to estimate time left.
  final int wpm;

  /// Called with the requested Book text size (A− / A+).
  final ValueChanged<double> onFontSizeChanged;

  /// Document-wide word indices that start a paragraph.
  final Set<int> paragraphStarts;

  /// Document-wide word indices where a spine file (EPUB) begins. One that
  /// opens with a heading starts a fresh page, as in an e-reader.
  final Set<int> chapterStarts;

  /// Document index of `words[0]`.
  final int wordOffset;

  /// Words in the whole document, for the percentage (defaults to
  /// [words] length).
  final int? totalWords;

  /// Space taken by the reader header above the page.
  final double topInset;

  /// Space reserved below the page (safe area).
  final double bottomInset;

  /// Next-page button key (for tests).
  static const Key nextKey = ValueKey('book-next-page');

  /// Previous-page button key (for tests).
  static const Key previousKey = ValueKey('book-previous-page');

  /// Page text key (for tests).
  static const Key pageKey = ValueKey('book-page-text');

  @override
  State<BookModeView> createState() => BookModeViewState();
}

/// State for [BookModeView]; exposes page turning for swipes and keys.
class BookModeViewState extends State<BookModeView> {
  _BookLayout? _layout;
  _PageSpec? _page;
  int _direction = 1;

  /// Moves to the next page, if any.
  void nextPage() {
    final page = _page;
    if (page == null || page.end >= widget.words.length - 1) return;
    _direction = 1;
    HapticFeedback.selectionClick();
    widget.onTurn(page.end + 1);
  }

  /// Moves to the previous page, if any.
  void previousPage() {
    final layout = _layout;
    if (layout == null || widget.startIndex <= 0) return;
    _direction = -1;
    HapticFeedback.selectionClick();
    widget.onTurn(layout.previousPageStart(widget.startIndex));
  }

  bool _isParagraphStart(int i) =>
      i == 0 || widget.paragraphStarts.contains(i + widget.wordOffset);

  bool _isChapterStart(int i) =>
      widget.chapterStarts.contains(i + widget.wordOffset);

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1.0).clamp(1.0, 2.0).toDouble();
    final style = TextStyle(
      fontFamily: widget.fontFamily,
      fontSize: widget.fontSize * textScale,
      height: 1.6,
      letterSpacing: widget.letterSpacing,
      wordSpacing: widget.wordSpacing,
      color: RunThruTokens.stageText,
      fontWeight: FontWeight.w400,
    );
    final headingStyle = style.copyWith(
      fontSize: style.fontSize! * 1.18,
      fontWeight: FontWeight.w700,
      height: 1.3,
    );
    final reduced = isReducedMotion(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPad = (constraints.maxWidth * 0.08).clamp(20.0, 48.0);
        final pageWidth = (constraints.maxWidth - horizontalPad * 2).clamp(
          120.0,
          680.0,
        );
        const footerHeight = 64.0;
        final pageHeight =
            constraints.maxHeight -
            widget.topInset -
            widget.bottomInset -
            footerHeight -
            24;

        final layout = _layout = _BookLayout(
          words: widget.words,
          isParagraphStart: _isParagraphStart,
          style: style,
          headingStyle: headingStyle,
          isChapterStart: _isChapterStart,
          width: pageWidth,
          height: pageHeight.clamp(style.fontSize! * 3, double.infinity),
          paragraphGap: style.fontSize! * 0.75,
          direction: Directionality.of(context),
        );
        final start = widget.startIndex.clamp(0, widget.words.length - 1);
        final page = _page = layout.pageFrom(start);

        final total = widget.totalWords ?? widget.words.length;
        final globalEnd = page.end + widget.wordOffset;
        final percent = total <= 0
            ? 0
            : ((globalEnd + 1) / total * 100).clamp(0, 100).round();
        final wordsLeft = (total - globalEnd - 1).clamp(0, total);
        final minutesLeft = (wordsLeft / widget.wpm.clamp(60, 1500)).ceil();

        return Padding(
          padding: EdgeInsets.only(
            top: widget.topInset,
            bottom: widget.bottomInset,
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Expanded(
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: pageWidth,
                        child: AnimatedSwitcher(
                          duration: reduced
                              ? Duration.zero
                              : const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final incoming =
                                child.key == ValueKey('page-${page.start}');
                            final dx = (incoming ? 0.12 : -0.12) * _direction;
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: Offset(dx, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _PageText(
                            key: ValueKey('page-${page.start}'),
                            page: page,
                            layout: layout,
                          ),
                        ),
                      ),
                    ),
                    // Kindle-style tap zones: left third goes back, the rest
                    // goes forward. Invisible to assistive technology, which
                    // uses the labelled footer buttons instead.
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: previousPage,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: nextPage,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: footerHeight,
                child: _BookFooter(
                  percent: percent,
                  minutesLeft: minutesLeft,
                  canGoBack: start > 0,
                  canGoForward: page.end < widget.words.length - 1,
                  onPrevious: previousPage,
                  onNext: nextPage,
                  fontSize: widget.fontSize,
                  onFontSizeChanged: widget.onFontSizeChanged,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One laid-out page: words [start]..[end] inclusive.
class _PageSpec {
  const _PageSpec(this.start, this.end);

  final int start;
  final int end;
}

/// Measures pages. Paragraph painters use the same style, width and text
/// scaler as [_PageText], so what fits here is exactly what renders.
class _BookLayout {
  _BookLayout({
    required this.words,
    required this.isParagraphStart,
    required this.isChapterStart,
    required this.style,
    required this.headingStyle,
    required this.width,
    required this.height,
    required this.paragraphGap,
    required this.direction,
  });

  final List<String> words;
  final bool Function(int) isParagraphStart;
  final bool Function(int) isChapterStart;
  final TextStyle style;
  final TextStyle headingStyle;
  final double width;
  final double height;
  final double paragraphGap;
  final TextDirection direction;

  /// More words than any page can hold. A block is never measured past
  /// this, so a document without paragraph data (one giant "paragraph")
  /// cannot stall layout; the remainder continues on the next line.
  static const int maxBlockWords = 1200;

  /// End (inclusive) of the paragraph that starts at [i], capped at
  /// [maxBlockWords].
  int paragraphEnd(int i) {
    var end = i;
    final limit = (i + maxBlockWords - 1).clamp(i, words.length - 1);
    while (end < limit && !isParagraphStart(end + 1)) {
      end++;
    }
    return end;
  }

  /// A short paragraph with no closing punctuation reads as a heading
  /// ("Chapter Two: The Ledger"). Only whole paragraphs qualify.
  bool isHeading(int first, int last) {
    if (!isParagraphStart(first)) return false;
    final count = last - first + 1;
    if (count > 10) return false;
    return !_closingPunctuation.hasMatch(words[last]);
  }

  /// Space above a paragraph that is not first on its page. A block that
  /// continues a capped paragraph gets none.
  double gapBefore(int first, int last) {
    if (!isParagraphStart(first)) return 0;
    return isHeading(first, last) ? paragraphGap * 2 : paragraphGap;
  }

  TextStyle styleFor(int first, int last) =>
      isHeading(first, last) ? headingStyle : style;

  /// Lays out the page that starts at [start].
  _PageSpec pageFrom(int start) {
    var used = 0.0;
    var i = start;
    var first = true;
    while (i < words.length) {
      // Paragraph (or the rest of one, if the page starts mid-paragraph).
      final end = paragraphEnd(i);
      // A new chapter starts a fresh page. Spine files are only chapters
      // when they open with a heading: scanned-book EPUBs split files by
      // print page, mid-sentence.
      if (!first && isChapterStart(i) && isHeading(i, end)) break;
      final gap = first ? 0.0 : gapBefore(i, end);
      final remaining = height - used - gap;
      if (remaining < _lineHeight) break;

      final para = _ParagraphText(words, i, end);
      final painter = _painter(para.text, styleFor(i, end));
      if (painter.height <= remaining) {
        used += gap + painter.height;
        painter.dispose();
        i = end + 1;
        first = false;
        continue;
      }
      // Split the paragraph after the last line that fits fully.
      final lines = painter.computeLineMetrics();
      var fitEndChar = -1;
      var bottom = 0.0;
      for (final line in lines) {
        bottom += line.height;
        if (bottom > remaining + 0.5) break;
        final pos = painter.getPositionForOffset(
          Offset(width, bottom - line.height / 2),
        );
        fitEndChar = painter.getLineBoundary(pos).end;
      }
      painter.dispose();
      if (fitEndChar > 0) {
        final lastWord = para.lastWordEndingBy(fitEndChar);
        if (lastWord >= i) return _PageSpec(start, lastWord);
      }
      break;
    }
    // Always show at least one word so a giant word cannot stall paging.
    return _PageSpec(start, (i - 1).clamp(start, words.length - 1));
  }

  /// First word of the page that ends just before [currentStart].
  ///
  /// Finds the earliest start whose page reaches `currentStart - 1`, so the
  /// previous page is as full as possible and no word is skipped.
  int previousPageStart(int currentStart) {
    if (currentStart <= 0) return 0;
    final target = currentStart - 1;
    var lo = (currentStart - 2000).clamp(0, target);
    var hi = target;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (pageFrom(mid).end >= target) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    // Prefer starting on a paragraph if one begins on that page.
    for (var j = lo; j <= target; j++) {
      if (isParagraphStart(j)) {
        final page = pageFrom(j);
        if (page.end >= target && j - lo < 12) return j;
        break;
      }
    }
    return lo;
  }

  double get _lineHeight => style.fontSize! * (style.height ?? 1.2);

  TextPainter _painter(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: TextScaler.noScaling,
  )..layout(maxWidth: width);
}

final RegExp _closingPunctuation = RegExp(r'[.!?\u2026,;:"\u201D\u2019)\]]$');

/// A paragraph's text with each word's end offset, for line splitting.
class _ParagraphText {
  _ParagraphText(List<String> words, this.first, int last) {
    final buffer = StringBuffer();
    for (var i = first; i <= last; i++) {
      if (i > first) buffer.write(' ');
      buffer.write(words[i]);
      wordEnds.add(buffer.length);
    }
    text = buffer.toString();
  }

  final int first;
  late final String text;
  final List<int> wordEnds = [];

  /// Index of the last word whose text ends at or before [charEnd].
  int lastWordEndingBy(int charEnd) {
    var result = first - 1;
    for (var k = 0; k < wordEnds.length; k++) {
      if (wordEnds[k] <= charEnd) result = first + k;
    }
    return result;
  }
}

class _PageText extends StatelessWidget {
  const _PageText({super.key, required this.page, required this.layout});

  final _PageSpec page;
  final _BookLayout layout;

  @override
  Widget build(BuildContext context) {
    final paragraphs = <Widget>[];
    var i = page.start;
    while (i <= page.end) {
      // Classify by the whole paragraph (as pagination did), render only
      // the part that is on this page.
      final fullEnd = layout.paragraphEnd(i);
      final end = fullEnd.clamp(i, page.end);
      if (paragraphs.isNotEmpty) {
        paragraphs.add(SizedBox(height: layout.gapBefore(i, fullEnd)));
      }
      final heading = layout.isHeading(i, fullEnd);
      final text = Text(
        _ParagraphText(layout.words, i, end).text,
        style: layout.styleFor(i, fullEnd),
        textScaler: TextScaler.noScaling,
        textAlign: TextAlign.start,
      );
      paragraphs.add(heading ? Semantics(header: true, child: text) : text);
      i = end + 1;
    }
    return Semantics(
      key: BookModeView.pageKey,
      liveRegion: true,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: paragraphs,
      ),
    );
  }
}

class _BookFooter extends StatelessWidget {
  const _BookFooter({
    required this.percent,
    required this.minutesLeft,
    required this.canGoBack,
    required this.canGoForward,
    required this.onPrevious,
    required this.onNext,
    required this.fontSize,
    required this.onFontSizeChanged,
  });

  final int percent;
  final int minutesLeft;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final double fontSize;
  final ValueChanged<double> onFontSizeChanged;

  String get _timeLeft {
    if (!canGoForward) return 'Last page';
    return formatTimeLeft(minutesLeft);
  }

  @override
  Widget build(BuildContext context) {
    final muted = RunThruTypography.caption.copyWith(
      color: RunThruTokens.stageText.withValues(alpha: 0.62),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _FooterButton(
            key: BookModeView.previousKey,
            icon: Icons.chevron_left_rounded,
            label: 'Previous page',
            onTap: canGoBack ? onPrevious : null,
          ),
          _FooterButton(
            icon: Icons.text_decrease_rounded,
            label: 'Smaller text',
            onTap: () => onFontSizeChanged(fontSize - 2),
          ),
          Expanded(
            child: Semantics(
              label: '$percent percent read. $_timeLeft',
              excludeSemantics: true,
              child: Text(
                '$percent% · $_timeLeft',
                textAlign: TextAlign.center,
                style: muted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          _FooterButton(
            icon: Icons.text_increase_rounded,
            label: 'Larger text',
            onTap: () => onFontSizeChanged(fontSize + 2),
          ),
          _FooterButton(
            key: BookModeView.nextKey,
            icon: Icons.chevron_right_rounded,
            label: 'Next page',
            onTap: canGoForward ? onNext : null,
          ),
        ],
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: SizedBox(
          width: RunThruA11y.minTapTarget,
          height: RunThruA11y.minTapTarget,
          child: Icon(
            icon,
            size: 24,
            color: RunThruTokens.stageText.withValues(
              alpha: enabled ? 0.72 : 0.22,
            ),
          ),
        ),
      ),
    );
  }
}
