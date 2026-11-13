import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:runthru/core/book_structure.dart';
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
    this.headingStarts,
    this.structure,
    this.onEnd,
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

  /// Document-wide word indices where a heading line starts, when the
  /// document records its headings. Null for documents that do not: short
  /// unpunctuated paragraphs are then taken for headings.
  final Set<int>? headingStarts;

  /// The book's sections. Each chapter then opens on a fresh page under a
  /// designed heading (label, rule, title) instead of a bold line.
  final BookStructure? structure;

  /// Called when the reader turns past the last page.
  final VoidCallback? onEnd;

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
    if (page == null) return;
    if (page.end >= widget.words.length - 1) {
      widget.onEnd?.call();
      return;
    }
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

  /// The chapter whose heading covers local word [i], if any: the page
  /// then opens with that chapter's designed heading.
  BookSection? _openerAt(int i) {
    final structure = widget.structure;
    if (structure == null) return null;
    final global = i + widget.wordOffset;
    final section = structure.sectionAt(global);
    if (section.kind != SectionKind.body || !section.isTitled) return null;
    if (global < section.start || global > section.textStart) return null;
    if (global == section.textStart && section.headingWords > 0) return null;
    return section;
  }

  /// Whether local word [i] starts a section (any kind): a fresh page.
  bool _isSectionStart(int i) {
    final structure = widget.structure;
    if (structure == null) return false;
    final global = i + widget.wordOffset;
    final section = structure.sectionAt(global);
    return section.start == global && section.isTitled;
  }

  bool? _isFlaggedHeading(int i) {
    final starts = widget.headingStarts;
    if (starts == null) return null;
    return starts.contains(i + widget.wordOffset);
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to lay out while a document is still loading or being swapped.
    if (widget.words.isEmpty) {
      _page = null;
      return const SizedBox.shrink();
    }
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
          isSectionStart: _isSectionStart,
          isFlaggedHeading: _isFlaggedHeading,
          openerAt: _openerAt,
          wordOffset: widget.wordOffset,
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
                            animateOpener: !reduced,
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
                  canFinish: widget.onEnd != null,
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
  const _PageSpec(this.start, this.end, {this.opener, this.textStart});

  final int start;
  final int end;

  /// The chapter this page opens, when it starts at a chapter's heading.
  final BookSection? opener;

  /// First word of running text on the page (after the opener's heading
  /// words). Equals [start] on ordinary pages.
  final int? textStart;
}

/// Measures pages. Paragraph painters use the same style, width and text
/// scaler as [_PageText], so what fits here is exactly what renders.
class _BookLayout {
  _BookLayout({
    required this.words,
    required this.isParagraphStart,
    required this.isChapterStart,
    required this.isSectionStart,
    required this.isFlaggedHeading,
    required this.openerAt,
    required this.wordOffset,
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

  /// Whether a local word starts a titled section (a fresh page).
  final bool Function(int) isSectionStart;

  /// Whether a local word starts a heading line; null when the document
  /// does not record headings.
  final bool? Function(int) isFlaggedHeading;

  /// The chapter whose heading covers a local word, if any.
  final BookSection? Function(int) openerAt;

  /// Document index of `words[0]`.
  final int wordOffset;
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
    // Documents that record their headings are taken at their word: a
    // short line such as "Author: Lewis Carroll" is not one.
    final flagged = isFlaggedHeading(first);
    if (flagged != null) return flagged;
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
    BookSection? opener;
    int? textStart;

    // A page that starts on a chapter's heading opens with the designed
    // heading; the heading's own words are not laid out as text.
    final section = openerAt(start);
    if (section != null) {
      opener = section;
      used = openerHeight(section);
      i = (section.textStart - wordOffset).clamp(start, words.length);
      textStart = i;
      first = false;
      if (i >= words.length) {
        return _PageSpec(start, words.length - 1, opener: opener, textStart: i);
      }
    }

    while (i < words.length) {
      // Paragraph (or the rest of one, if the page starts mid-paragraph).
      final end = paragraphEnd(i);
      // A new chapter starts a fresh page. Without section data, spine
      // files are only chapters when they open with a heading:
      // scanned-book EPUBs split files by print page, mid-sentence.
      final startsFresh =
          isSectionStart(i) || (isChapterStart(i) && isHeading(i, end));
      if (i > start && startsFresh) break;
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
        if (lastWord >= i) {
          return _PageSpec(
            start,
            lastWord,
            opener: opener,
            textStart: textStart,
          );
        }
      }
      break;
    }
    // Always show at least one word so a giant word cannot stall paging.
    return _PageSpec(
      start,
      (i - 1).clamp(start, words.length - 1),
      opener: opener,
      textStart: textStart,
    );
  }

  // ── Chapter opener metrics (shared by pagination and rendering) ──

  /// Space above the opener, as a fraction of the page: a chapter opens
  /// lower down the page, as in print.
  static const double openerDrop = 0.1;

  TextStyle get openerOverlineStyle => RunThruTypography.chapterOverline;

  TextStyle get openerTitleStyle => RunThruTypography.chapterTitle.copyWith(
    fontSize: (style.fontSize! * 1.55).clamp(24.0, 44.0),
  );

  TextStyle get openerSubtitleStyle => RunThruTypography.chapterSubtitle
      .copyWith(fontSize: (style.fontSize! * 0.82).clamp(13.0, 22.0));

  static const double openerRuleHeight = 12;
  static const double openerGap = 14;

  /// Height of the block below the opener before the text begins.
  double get openerTail => style.fontSize! * 1.6;

  double _lineBlock(String text, TextStyle textStyle, int maxLines) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: direction,
      textAlign: TextAlign.center,
      textScaler: TextScaler.noScaling,
      maxLines: maxLines,
      ellipsis: '\u2026',
    )..layout(maxWidth: width);
    final h = painter.height;
    painter.dispose();
    return h;
  }

  /// Total height the opener of [section] takes at the top of its page.
  /// Never more than 70% of the page, so text always follows it.
  double openerHeight(BookSection section) {
    var h = height * openerDrop;
    final group = section.groupTitle ?? '';
    if (group.isNotEmpty) {
      h += _lineBlock(group.toUpperCase(), openerOverlineStyle, 1) + 8;
    }
    if (section.overline.isNotEmpty) {
      h +=
          _lineBlock(section.overline.toUpperCase(), openerOverlineStyle, 2) +
          openerGap;
    }
    h += openerRuleHeight + openerGap;
    h += _lineBlock(section.headline, openerTitleStyle, 4);
    final subtitle = section.subtitle ?? '';
    if (subtitle.isNotEmpty) {
      h += 10 + _lineBlock(subtitle, openerSubtitleStyle, 3);
    }
    h += openerTail;
    return h.clamp(0.0, height * 0.7);
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
  const _PageText({
    super.key,
    required this.page,
    required this.layout,
    this.animateOpener = false,
  });

  final _PageSpec page;
  final _BookLayout layout;

  /// Whether a chapter opener on this page plays its entrance.
  final bool animateOpener;

  @override
  Widget build(BuildContext context) {
    final paragraphs = <Widget>[];
    final opener = page.opener;
    if (opener != null) {
      paragraphs.add(
        _ChapterOpener(
          key: ValueKey('opener-${opener.start}'),
          section: opener,
          layout: layout,
          animate: animateOpener,
        ),
      );
    }
    var i = page.textStart ?? page.start;
    var firstBlock = opener == null;
    while (i <= page.end) {
      // Classify by the whole paragraph (as pagination did), render only
      // the part that is on this page.
      final fullEnd = layout.paragraphEnd(i);
      final end = fullEnd.clamp(i, page.end);
      if (!firstBlock) {
        final gap = opener != null && i == page.textStart
            ? 0.0
            : layout.gapBefore(i, fullEnd);
        if (gap > 0) paragraphs.add(SizedBox(height: gap));
      }
      firstBlock = false;
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

/// A chapter's heading at the top of its first page: the label spaced out
/// above a short rule, then the title, as a printed chapter opening.
///
/// Its height is [_BookLayout.openerHeight], the same figure pagination
/// reserved, so the text below starts exactly where the page was measured
/// to. The entrance is a single fade and rise; none with reduced motion.
class _ChapterOpener extends StatelessWidget {
  const _ChapterOpener({
    super.key,
    required this.section,
    required this.layout,
    required this.animate,
  });

  final BookSection section;
  final _BookLayout layout;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final group = section.groupTitle ?? '';
    final subtitle = section.subtitle ?? '';
    final spoken = [
      if (group.isNotEmpty) group,
      if (section.overline.isNotEmpty) section.overline,
      section.headline,
      if (subtitle.isNotEmpty) subtitle,
    ].join('. ');

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: layout.height * _BookLayout.openerDrop),
        if (group.isNotEmpty) ...[
          Text(
            group.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: layout.openerOverlineStyle.copyWith(
              color: RunThruTokens.shellInkSoft,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (section.overline.isNotEmpty) ...[
          Text(
            section.overline.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: layout.openerOverlineStyle,
          ),
          const SizedBox(height: _BookLayout.openerGap),
        ],
        const SizedBox(
          height: _BookLayout.openerRuleHeight,
          child: Center(child: _OpenerRule()),
        ),
        const SizedBox(height: _BookLayout.openerGap),
        Text(
          section.headline,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textScaler: TextScaler.noScaling,
          style: layout.openerTitleStyle,
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: layout.openerSubtitleStyle,
          ),
        ],
      ],
    );

    final block = Semantics(
      header: true,
      label: spoken,
      child: ExcludeSemantics(
        // The reserved height, whatever the fonts measure to: text below
        // must start where pagination expects.
        child: SizedBox(
          height: layout.openerHeight(section),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: content,
            ),
          ),
        ),
      ),
    );
    if (!animate) return block;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: RunThruTiming.titleCardEnter,
      curve: Curves.easeOutCubic,
      child: block,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: child,
        ),
      ),
    );
  }
}

/// The short rule with a centre diamond under a chapter label.
class _OpenerRule extends StatelessWidget {
  const _OpenerRule();

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: SizedBox(
        height: 1.4,
        child: ColoredBox(
          color: RunThruTokens.shellTeal.withValues(alpha: 0.55),
        ),
      ),
    );
    return SizedBox(
      width: 120,
      child: Row(
        children: [
          line,
          const SizedBox(width: 7),
          Transform.rotate(
            angle: 0.785398, // 45°
            child: const SizedBox(
              width: 6,
              height: 6,
              child: ColoredBox(color: RunThruTokens.shellTeal),
            ),
          ),
          const SizedBox(width: 7),
          line,
        ],
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
    required this.canFinish,
    required this.onPrevious,
    required this.onNext,
    required this.fontSize,
    required this.onFontSizeChanged,
  });

  final int percent;
  final int minutesLeft;
  final bool canGoBack;
  final bool canGoForward;

  /// On the last page: whether going on from it does anything (it tells the
  /// host that the text has been read to the end).
  final bool canFinish;
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
          // On the last page this button finishes the text. The page's tap
          // zones do too, but they are hidden from assistive technology, so
          // this is the only way to the end for a screen-reader user.
          _FooterButton(
            key: BookModeView.nextKey,
            icon: Icons.chevron_right_rounded,
            label: canGoForward ? 'Next page' : 'Finish',
            onTap: canGoForward || canFinish ? onNext : null,
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
      // The ink response's own tap action is excluded with its semantics,
      // so the action is named here for assistive technology.
      onTap: onTap,
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
