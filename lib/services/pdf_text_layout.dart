/// Layout-aware reconstruction of reading text from raw PDF pages.
///
/// pdfium reports a page as one string plus a box per character. Read as a
/// plain string that text is the *page*, not the book: running headers and
/// page numbers sit between the halves of a sentence, words hyphenated at a
/// line end carry a control character, drop caps are separate from their
/// word and there are no paragraphs or headings.
///
/// [analyzePdfLayout] rebuilds the reading text from the character boxes:
///
/// 1. **Lines.** Raw lines are split into physical lines, measured (edges,
///    baseline, cap height) and cleaned. A watermark set up the margin is
///    dropped.
/// 2. **Page furniture.** Short lines at the very top or bottom of a page
///    that stand clear of the text and are a page number, or repeat on
///    other pages of the window, are removed.
/// 3. **Structure.** Drop caps rejoin their word; contents rows, headings
///    and paragraph starts are recovered from size, spacing and indentation.
/// 4. **Text repair.** Words hyphenated across lines and pages are rejoined
///    against the document's own vocabulary.
///
/// Where the evidence is thin the text is left as pdfium gave it: a running
/// head that survives is a nuisance, a line of the book removed is a loss.
///
/// The analyzer is pure Dart (no Flutter, no pdfium) so it can be unit
/// tested with synthetic pages. It makes one pass over the characters and
/// then works line by line; nothing in it grows faster than the page count
/// of the window.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:runthru/core/text_segmentation.dart';
import 'package:runthru/services/models.dart';

// ── Input ─────────────────────────────────────────────────────────────

/// Number of doubles stored per character in [PdfRawPage.charBoxes].
const int kPdfCharBoxStride = 4;

/// One page exactly as pdfium reports it.
class PdfRawPage {
  const PdfRawPage({
    required this.pageIndex,
    required this.width,
    required this.height,
    required this.text,
    required this.charBoxes,
  });

  /// A page with no text layer.
  PdfRawPage.empty({required this.pageIndex, this.width = 0, this.height = 0})
    : text = '',
      charBoxes = Float64List(0);

  /// 0-based page index in the document.
  final int pageIndex;

  /// Page size in points, as displayed (after page rotation).
  final double width;
  final double height;

  /// The page's raw text. Lines end in `\n` (optionally `\r\n`); pdfium
  /// marks a word hyphenated at a line end with U+0002 in place of the
  /// hyphen and no line break.
  final String text;

  /// [kPdfCharBoxStride] doubles per UTF-16 code unit of [text]:
  /// left, top, right, bottom, in PDF coordinates (origin bottom-left, so
  /// top > bottom). A page whose list is shorter than the text is treated
  /// as having no geometry.
  final Float64List charBoxes;
}

/// A bookmark destination to locate in the analysed text.
class PdfOutlineTarget {
  const PdfOutlineTarget({
    required this.title,
    required this.pageIndex,
    this.depth = 0,
    this.top,
    this.left,
  });

  final String title;

  /// 0-based index of the page the bookmark points at.
  final int pageIndex;

  /// Nesting level in the outline tree (0 = top level).
  final int depth;

  /// Vertical position of the destination on the page, when the bookmark
  /// carries one.
  final double? top;

  /// Horizontal position of the destination, when the bookmark carries one.
  final double? left;
}

// ── Output ────────────────────────────────────────────────────────────

/// Where an emitted page begins in the result's word and sentence streams.
class PdfPageStart {
  const PdfPageStart({
    required this.pageIndex,
    required this.startWordIndex,
    required this.startSentenceIndex,
    required this.firstWords,
  });

  final int pageIndex;

  /// Index of the first word on the page. When a word is hyphenated across
  /// the page break this is the rejoined word.
  final int startWordIndex;

  /// The sentence containing that word; a page may begin mid-sentence.
  final int startSentenceIndex;

  /// The first few words on the page, as a preview label. Empty for a page
  /// with no text.
  final String firstWords;
}

/// The reading text recovered from a window of pages.
class PdfLayoutResult {
  const PdfLayoutResult({
    required this.sentences,
    required this.pageStarts,
    this.outline = const [],
    this.continuesPrevious = false,
    this.endsWithSplitWord = false,
  });

  final List<Sentence> sentences;

  /// One entry per emitted page, in page order.
  final List<PdfPageStart> pageStarts;

  /// The located bookmarks, in reading order.
  final List<OutlineEntry> outline;

  /// Whether the first sentence continues the sentence the previous page
  /// ended on (see [ExtractedDocument.continuesPrevious]).
  final bool continuesPrevious;

  /// Whether the last word is the left half of a word hyphenated across the
  /// end of the window and ends in [kSplitWordMarker].
  final bool endsWithSplitWord;
}

// ── Tuning ────────────────────────────────────────────────────────────

/// Share of the page height, at the top and at the bottom, in which a line
/// can be page furniture. Wide enough for small-format books whose footer
/// sits well clear of the paper edge.
const double _zoneFraction = 0.15;

/// Furniture is short: a running head, a page number, a site name.
const int _maxFurnitureWords = 16;
const int _maxFurnitureChars = 130;

/// A furniture line is "detached" when it stands this many line pitches
/// clear of the text block.
const double _detachedPitches = 1.5;

/// Cap-height ratios (line / body) for headings and their levels.
const double _headingRatio = 1.15;
const double _headingLevel2Ratio = 1.3;
const double _headingLevel1Ratio = 1.6;
const int _maxHeadingWords = 14;

/// A run of large lines longer than this is large body text, not a title.
const int _maxHeadingLines = 4;
const int _maxHeadingRunWords = 40;

/// Heading lines closer than this many cap heights are one wrapped heading.
const double _headingStackPitch = 3.5;

/// A line this many pitches below its predecessor opens a paragraph.
const double _paragraphGapPitches = 1.35;

/// Spacing that sets a heading-like line apart from the text around it.
const double _isolatedPitches = 1.25;

/// A 1–2 letter line this many body cap heights tall is a drop cap.
const double _dropCapRatio = 1.8;

/// Text that does not run horizontally is dropped only while it is at most
/// this share of the page's characters.
const double _maxTurnedShare = 0.3;

/// Share of the column a line must fall short by to count as "clearly
/// short" without any punctuation to confirm it.
const double _clearShortfall = 0.2;

/// How many neighbouring lines describe a line's local column.
const int _neighbourLines = 4;

// ── Entry point ───────────────────────────────────────────────────────

/// Rebuilds reading text from [pages].
///
/// [pages] is a window in page order. Pages from [firstPage] to [lastPage]
/// (0-based page indices, inclusive; default: the whole window) are emitted;
/// pages outside that range are evidence only: they make repeated headers
/// detectable in short ranges and tell the analyzer what the text on either
/// side of the range looks like.
///
/// [outline] bookmarks that point into the emitted pages are located and
/// returned as [OutlineEntry]s.
PdfLayoutResult analyzePdfLayout(
  List<PdfRawPage> pages, {
  int? firstPage,
  int? lastPage,
  List<PdfOutlineTarget> outline = const [],
}) {
  return _LayoutAnalysis(pages, firstPage, lastPage, outline).run();
}

// ── Lines ─────────────────────────────────────────────────────────────

class _Line {
  _Line({
    required this.page,
    required this.text,
    required this.hasBox,
    required this.softBreak,
  });

  final _Page page;

  /// Cleaned text: single spaces, no control characters.
  String text;

  /// Whether the line has usable geometry.
  bool hasBox;

  /// Whether the line's letters climb the page instead of running along a
  /// baseline: text set vertically or on a slant.
  bool turned = false;

  /// Whether the line ended at a hyphenation mark (pdfium's U+0002 or a
  /// soft hyphen): the word continues on the next line.
  bool softBreak;

  double left = 0;
  double right = 0;
  double top = 0;
  double bottom = 0;

  /// The y the letters sit on (median glyph bottom).
  double baseline = 0;

  /// Height of capitals and ascenders: the line's type size.
  double capHeight = 0;

  /// Width of the first word, for the "would it have fitted on the previous
  /// line" test.
  double firstWordWidth = 0;

  int visibleChars = 0;

  /// Box of the first glyph (left, top, right, bottom).
  double firstLeft = 0;
  double firstTop = 0;
  double firstRight = 0;
  double firstBottom = 0;

  /// Box of a drop cap that opens this line, if any.
  bool hasDropCap = false;
  double dropLeft = 0;
  double dropRight = 0;
  double dropBottom = 0;

  /// Left edge for indentation tests. Lines set beside a drop cap count
  /// from the drop cap's edge, not their own.
  double flowLeft = 0;

  /// Position in [_Page.lines] once the page's lines are final.
  int index = 0;

  int words = 0;
  bool startsLower = false;
  bool endsSentence = false;
  bool endsClause = false;
  bool endsHyphen = false;
  bool isOrnament = false;
  bool listMarker = false;

  bool isTocRow = false;
  bool isTocLabel = false;
  int heading = 0;

  /// Set when a bookmark names this line: it opens a unit of text.
  bool forceStart = false;

  /// Index of the line's first word in the paragraph being built, then in
  /// the result once the paragraph is emitted.
  int firstToken = 0;
  int wordIndex = -1;

  double get centerY => (top + bottom) / 2;
  double get height => top - bottom;
  bool get isBody => heading == 0 && !isTocRow && !isTocLabel && !isOrnament;
}

class _Page {
  _Page(this.raw, this.slot);

  final PdfRawPage raw;

  /// Position in the analysed window.
  final int slot;

  List<_Line> lines = <_Line>[];
  bool emitted = false;

  /// Blocks of lines that end at a common right edge.
  List<_Column> columns = const <_Column>[];

  int get pageIndex => raw.pageIndex;
}

/// Lines on a page that share a right edge: a column of text, a block
/// quote, a passage set around a picture.
class _Column {
  const _Column(this.left, this.right);

  final double left;
  final double right;
}

/// A line in the top or bottom zone that may be page furniture.
class _Candidate {
  _Candidate(this.line, {required this.top, required this.rank});

  final _Line line;

  /// Top zone (true) or bottom zone (false).
  final bool top;

  /// 0 for the outermost line of the zone, 1 for the next one in.
  final int rank;

  /// Vertical distance to the nearest line that is not a candidate.
  double gapToText = double.infinity;

  /// The other candidate in this zone on this page, if there are two.
  _Candidate? partner;

  bool pureNumber = false;
  bool roman = false;
  int value = 0;

  /// Text with numbers replaced by `#`, punctuation dropped.
  String key = '';
  List<int> numbers = const <int>[];

  bool removed = false;
  bool detached = false;
}

/// A body paragraph being assembled from lines.
class _Paragraph {
  _Paragraph({required this.startsParagraph});

  final bool startsParagraph;
  final List<String> tokens = <String>[];
  final List<_Line> lines = <_Line>[];
}

class _LayoutAnalysis {
  _LayoutAnalysis(
    List<PdfRawPage> rawPages,
    int? firstPage,
    int? lastPage,
    this._outline,
  ) {
    for (var i = 0; i < rawPages.length; i++) {
      final page = _Page(rawPages[i], i);
      final index = page.pageIndex;
      page.emitted =
          (firstPage == null || index >= firstPage) &&
          (lastPage == null || index <= lastPage);
      _pages.add(page);
    }
  }

  final List<PdfOutlineTarget> _outline;
  final List<_Page> _pages = <_Page>[];

  /// Lower-cased words of the window and how often each occurs.
  final Map<String, int> _vocabulary = <String, int>{};

  /// Dominant cap height: the size of running text.
  double _bodyCap = 0;

  /// Typical baseline-to-baseline distance by type size, and overall.
  final Map<int, double> _pitchBySize = <int, double>{};
  double _pitch = 0;

  // Scratch buffers reused for every line.
  final List<double> _heights = <double>[];
  final List<double> _bottoms = <double>[];
  final List<double> _capHeights = <double>[];
  final List<double> _capBottoms = <double>[];
  final List<double> _xHeights = <double>[];

  // Emission state.
  final List<Sentence> _sentences = <Sentence>[];
  final List<int> _sentenceStarts = <int>[];
  int _wordCount = 0;

  PdfLayoutResult run() {
    for (final page in _pages) {
      _scanPage(page);
    }
    _measureBody();
    _buildVocabulary();
    for (final page in _pages) {
      _mergeRows(page);
      _markDropCapWraps(page);
      for (final line in page.lines) {
        _finishText(line);
      }
      page.lines.removeWhere((l) => l.text.isEmpty);
    }
    _measurePitch();
    _removeFurniture();
    for (final page in _pages) {
      _restoreReadingOrder(page);
      _indexLines(page);
      _findColumns(page);
      _markContents(page);
      _markHeadings(page);
    }
    final located = _locateOutline();
    return _emit(located);
  }

  // ── 1. Lines ────────────────────────────────────────────────────────

  /// Splits the page text into physical lines: at every line break, at
  /// every hyphenation mark, and wherever the glyphs themselves return to
  /// the left a row lower although pdfium marked nothing (it does not
  /// always break the lines of content stored sideways).
  void _scanPage(_Page page) {
    final text = page.raw.text;
    final boxes = page.raw.charBoxes;
    final n = text.length;
    final boxed = boxes.length >= n * kPdfCharBoxStride;
    var start = 0;
    var rowLeft = double.infinity;
    var rowRight = double.negativeInfinity;
    var lastCy = 0.0;
    var lastHeight = 0.0;

    void close(int end, {required bool softBreak}) {
      if (end > start) {
        final line = _scanLine(
          page,
          start,
          end,
          softBreak: softBreak,
          boxed: boxed,
        );
        if (line != null) page.lines.add(line);
      }
      rowLeft = double.infinity;
      rowRight = double.negativeInfinity;
    }

    for (var i = 0; i <= n; i++) {
      final c = i < n ? text.codeUnitAt(i) : 0x0A;
      if (c == 0x0A || c == 0x02) {
        close(i, softBreak: c == 0x02 && i < n);
        start = i + 1;
        continue;
      }
      if (!boxed) continue;
      // Printable ASCII is never a space or a mark to skip.
      if ((c <= 0x20 || c >= 0x7F) &&
          (_isSpace(c) || _isIgnorable(c) || c == 0xAD)) {
        continue;
      }
      final o = i * kPdfCharBoxStride;
      final l = boxes[o];
      final r = boxes[o + 2];
      final h = boxes[o + 1] - boxes[o + 3];
      if (!(r - l > 0 || h > 0)) continue;
      final cy = (boxes[o + 1] + boxes[o + 3]) / 2;
      if (rowRight > rowLeft) {
        final size = math.max(h, lastHeight);
        final back = math.max(0.3 * (rowRight - rowLeft), 3 * size);
        if (l < rowRight - back && cy < lastCy - 0.9 * size) {
          close(i, softBreak: false);
          start = i;
        }
      }
      if (l < rowLeft) rowLeft = l;
      if (r > rowRight) rowRight = r;
      lastCy = cy;
      lastHeight = h;
    }
    _settleTurnedText(page);
  }

  /// Drops text that does not run horizontally when it is a small part of
  /// the page: a watermark up the margin, the labels of a chart. When most
  /// of the page is set that way it is the page's text (a vertical script,
  /// a table printed sideways): it is kept, in the order the file gives
  /// it, with no layout read into it.
  void _settleTurnedText(_Page page) {
    var all = 0;
    var turned = 0;
    for (final line in page.lines) {
      all += line.visibleChars;
      if (line.turned) turned += line.visibleChars;
    }
    if (turned == 0) return;
    if (turned <= _maxTurnedShare * all) {
      page.lines.removeWhere((line) => line.turned);
    } else {
      for (final line in page.lines) {
        if (line.turned) line.hasBox = false;
      }
    }
  }

  /// Measures and cleans the characters in `[start, end)`. Returns null for
  /// a line with no text.
  _Line? _scanLine(
    _Page page,
    int start,
    int end, {
    required bool softBreak,
    required bool boxed,
  }) {
    final text = page.raw.text;
    final boxes = page.raw.charBoxes;
    final out = StringBuffer();
    var wrote = false;
    var pendingSpace = false;
    var lastUnit = 0;
    var softHyphenLast = false;

    var left = double.infinity;
    var right = double.negativeInfinity;
    var top = double.negativeInfinity;
    var bottom = double.infinity;
    var minCy = double.infinity;
    var maxCy = double.negativeInfinity;
    var visible = 0;
    var firstLeft = 0.0;
    var firstTop = 0.0;
    var firstRight = 0.0;
    var firstBottom = 0.0;
    var firstWordRight = 0.0;
    var firstWordOpen = true;
    var firstIsCap = false;
    var tallest = 0.0;
    var foreign = false;
    var letters = 0;
    var lastCx = 0.0;
    var lastCy = 0.0;
    var acrossRun = 0.0;
    var upRun = 0.0;
    _heights.clear();
    _bottoms.clear();
    _capHeights.clear();
    _capBottoms.clear();
    _xHeights.clear();

    for (var i = start; i < end; i++) {
      final c = text.codeUnitAt(i);
      // Printable ASCII, which is nearly everything, skips these checks.
      if (c <= 0x20 || c >= 0x7F) {
        if (_isSpace(c)) {
          pendingSpace = wrote;
          if (visible > 0) firstWordOpen = false;
          continue;
        }
        if (c == 0xAD) {
          softHyphenLast = true;
          continue;
        }
        if (_isIgnorable(c)) continue;
        // Joiners matter in scripts that shape their letters; after a
        // Latin letter they are stray marks.
        if ((c == 0x200C || c == 0x200D) && lastUnit < 0x0590) continue;
      }
      softHyphenLast = false;
      if (pendingSpace) {
        out.writeCharCode(0x20);
        pendingSpace = false;
      }
      final ligature = c >= 0xFB00 && c <= 0xFB06 ? _ligatures[c] : null;
      if (ligature != null) {
        out.write(ligature);
      } else {
        out.writeCharCode(c);
      }
      wrote = true;
      lastUnit = c;
      if (!boxed || c == 0x200C || c == 0x200D) continue;

      final o = i * kPdfCharBoxStride;
      final l = boxes[o];
      final t = boxes[o + 1];
      final r = boxes[o + 2];
      final b = boxes[o + 3];
      final w = r - l;
      final h = t - b;
      // Generated characters carry an empty box; NaN fails both tests.
      if (!(w > 0 || h > 0)) continue;
      if (l < left) left = l;
      if (r > right) right = r;
      if (t > top) top = t;
      if (b < bottom) bottom = b;
      final cx = (l + r) / 2;
      final cy = (t + b) / 2;
      if (cy < minCy) minCy = cy;
      if (cy > maxCy) maxCy = cy;
      if (h > tallest) tallest = h;
      // Size is read from letters and digits: a row of leader dots or a
      // run of quotes says nothing about the type.
      if (h > 0 && _isWordChar(c)) {
        if (letters > 0) {
          acrossRun += (cx - lastCx).abs();
          upRun += (cy - lastCy).abs();
        }
        letters++;
        lastCx = cx;
        lastCy = cy;
        _heights.add(h);
        _bottoms.add(b);
        if (_isCapClass(c)) {
          if (visible == 0) firstIsCap = true;
          _capHeights.add(h);
          _capBottoms.add(b);
        } else if (_isXClass(c)) {
          _xHeights.add(h);
        } else if (c >= 0x0370 && _ligatures[c] == null) {
          // A script whose letters these Latin classes do not describe.
          foreign = true;
        }
      }
      if (visible == 0) {
        firstLeft = l;
        firstTop = t;
        firstRight = r;
        firstBottom = b;
      }
      if (firstWordOpen && r > firstWordRight) firstWordRight = r;
      visible++;
    }

    final cleaned = out.toString();
    if (cleaned.isEmpty) return null;
    final line = _Line(
      page: page,
      text: cleaned,
      hasBox: visible > 0,
      softBreak: softBreak || softHyphenLast,
    );
    if (visible == 0) return line;

    // Text set vertically or on a slant (a margin watermark, the labels of
    // a chart): its letters climb the page instead of running along a
    // baseline. [_scanPage] decides what becomes of it.
    if ((letters >= 2 && upRun > 0.5 * tallest && upRun >= 2 * acrossRun) ||
        (visible >= 5 && tallest > 0 && maxCy - minCy > 3 * tallest)) {
      return line
        ..turned = true
        ..visibleChars = visible;
    }
    final baseline = _bottoms.isEmpty ? bottom : _median(_bottoms);
    line
      ..left = left
      ..right = right
      ..top = top
      ..bottom = bottom
      ..flowLeft = left
      ..baseline = baseline
      ..visibleChars = visible
      ..firstLeft = firstLeft
      ..firstTop = firstTop
      ..firstRight = firstRight
      ..firstBottom = firstBottom
      ..firstWordWidth = math.max(0, firstWordRight - left)
      ..capHeight = _capHeight(baseline, firstIsCap, foreign);
    return line;
  }

  /// The tallest capital, digit or ascender standing on the baseline.
  ///
  /// Glyphs off the baseline (a drop cap hanging below the first line, a
  /// superscript) are ignored, and so is a raised initial: a first letter
  /// far taller than everything after it says nothing about the line's size.
  ///
  /// A line with none of those is sized from its x-height letters, and a
  /// line in a script without them from its median glyph. Returns 0 when
  /// the line cannot be sized ("it." has only a dotted and a crossed
  /// letter); such a line is taken to be body text.
  double _capHeight(double baseline, bool firstIsCap, bool foreign) {
    final fallback = _xHeights.isNotEmpty
        ? _median(_xHeights) * 1.45
        : foreign && _heights.length >= 4
        ? _median(_heights) * 1.45
        : 0.0;
    var best = 0.0;
    var second = 0.0;
    var bestIsFirst = false;
    for (var k = 0; k < _capHeights.length; k++) {
      final h = _capHeights[k];
      if ((_capBottoms[k] - baseline).abs() > math.max(0.75, 0.15 * h)) {
        continue;
      }
      if (h > best) {
        second = best;
        best = h;
        bestIsFirst = k == 0 && firstIsCap;
      } else if (h > second) {
        second = h;
      }
    }
    if (best <= 0) return fallback;
    final rest = second > 0 ? second : fallback;
    if (bestIsFirst && rest > 0 && best >= 1.6 * rest) return rest;
    return best;
  }

  /// The dominant cap height, weighted by characters.
  void _measureBody() {
    final sized = <_Line>[
      for (final page in _pages)
        for (final line in page.lines)
          if (line.hasBox && line.capHeight > 0) line,
    ]..sort((a, b) => a.capHeight.compareTo(b.capHeight));
    var total = 0;
    for (final line in sized) {
      total += line.visibleChars;
    }
    var seen = 0;
    for (final line in sized) {
      seen += line.visibleChars;
      if (seen * 2 >= total) {
        _bodyCap = line.capHeight;
        break;
      }
    }
    for (final page in _pages) {
      for (final line in page.lines) {
        if (line.hasBox && line.capHeight <= 0) line.capHeight = _bodyCap;
      }
    }
  }

  /// Counts the whole words of the window. The two halves of a word broken
  /// at a line end are not words, so they are left out: "un" must not
  /// become a word because "un-derstand" was hyphenated somewhere.
  void _buildVocabulary() {
    // Carried from page to page: a word broken at the foot of a page
    // finishes at the head of the next.
    var afterBreak = false;
    for (final page in _pages) {
      for (final line in page.lines) {
        final tokens = line.text.split(' ');
        final broken = line.softBreak || _endsInHyphen(line.text);
        final from = afterBreak ? 1 : 0;
        final to = broken ? tokens.length - 1 : tokens.length;
        for (var i = from; i < to; i++) {
          final word = _core(tokens[i]);
          if (word.isEmpty) continue;
          _vocabulary[word] = (_vocabulary[word] ?? 0) + 1;
        }
        afterBreak = broken;
      }
    }
  }

  bool _known(String word, {int beyond = 0}) =>
      (_vocabulary[word] ?? 0) > beyond;

  // ── Drop caps and split rows ────────────────────────────────────────

  /// Rejoins pieces pdfium reports as separate lines although they sit on
  /// one row: a drop cap and its word, a formula and its subscripts.
  void _mergeRows(_Page page) {
    if (_bodyCap <= 0) return;
    final merged = <_Line>[];
    for (final line in page.lines) {
      final prev = merged.isEmpty ? null : merged.last;
      if (prev != null && prev.hasBox && line.hasBox && !prev.softBreak) {
        if (_isDropCapFor(prev, line)) {
          _attachDropCap(prev, line);
          merged[merged.length - 1] = line;
          continue;
        }
        if (_continuesRow(prev, line)) {
          _appendRow(prev, line);
          continue;
        }
      }
      merged.add(line);
    }
    page.lines = merged;
  }

  bool _isDropCapFor(_Line cap, _Line line) {
    if (cap.capHeight < _dropCapRatio * _bodyCap) return false;
    if (!_dropCapText.hasMatch(cap.text)) return false;
    if (line.capHeight > 0.7 * cap.capHeight) return false;
    if (line.left < cap.right - 0.35 * _bodyCap) return false;
    return line.top > cap.bottom && line.bottom < cap.top;
  }

  /// Prepends the drop cap [cap] to [line]: "I" + "n my younger" → "In my
  /// younger". The letter is its own word only when the document's
  /// vocabulary says so ("I" + "am by birth").
  void _attachDropCap(_Line cap, _Line line) {
    final space = line.text.indexOf(' ');
    final firstWord = space < 0 ? line.text : line.text.substring(0, space);
    final letters = _core(cap.text);
    final next = _core(firstWord);
    var separate = false;
    if (letters.isNotEmpty && next.isNotEmpty) {
      final joinedKnown = _known(letters + next);
      // The drop cap's own line and the word's own line each count once.
      final wordAlone =
          _standaloneCaps.contains(letters) ||
          (letters.length > 1 && _known(letters, beyond: 1));
      final apartKnown = wordAlone && _known(next, beyond: 1);
      if (apartKnown && !joinedKnown) {
        separate = true;
      } else if (apartKnown && joinedKnown) {
        separate = line.left - cap.right >= 0.22 * _bodyCap;
      }
    }
    line
      ..text = separate ? '${cap.text} ${line.text}' : '${cap.text}${line.text}'
      ..firstWordWidth = separate
          ? cap.right - cap.left
          : (line.left - cap.left) + line.firstWordWidth
      ..hasDropCap = true
      ..dropLeft = cap.left
      ..dropRight = cap.right
      ..dropBottom = cap.bottom
      ..left = cap.left
      ..flowLeft = cap.left
      ..visibleChars = line.visibleChars + cap.visibleChars;
  }

  bool _continuesRow(_Line prev, _Line line) {
    final overlap =
        math.min(prev.top, line.top) - math.max(prev.bottom, line.bottom);
    final smaller = math.min(prev.height, line.height);
    if (smaller > 0) {
      if (overlap < 0.5 * smaller) return false;
    } else if (line.centerY > prev.top || line.centerY < prev.bottom) {
      return false;
    }
    return line.left >= prev.right - math.max(1.5, 0.35 * _bodyCap);
  }

  void _appendRow(_Line prev, _Line line) {
    final gap = line.left - prev.right;
    final cap = math.min(prev.capHeight, line.capHeight);
    final spaced = gap > 0.2 * cap && !_startsClosing.hasMatch(line.text);
    // The longer piece says where the row's baseline is and how large its
    // type: the other may be a subscript or a footnote mark.
    if (line.visibleChars > prev.visibleChars) {
      prev
        ..baseline = line.baseline
        ..capHeight = line.capHeight;
    }
    prev
      ..text = spaced ? '${prev.text} ${line.text}' : '${prev.text}${line.text}'
      ..left = math.min(prev.left, line.left)
      ..right = math.max(prev.right, line.right)
      ..top = math.max(prev.top, line.top)
      ..bottom = math.min(prev.bottom, line.bottom)
      ..visibleChars = prev.visibleChars + line.visibleChars
      ..softBreak = line.softBreak;
  }

  /// Finds drop caps set inside their line and, for every drop cap, the
  /// lines set beside it: those are not indented, they make room.
  void _markDropCapWraps(_Page page) {
    if (_bodyCap <= 0) return;
    final lines = page.lines;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.hasBox) continue;
      if (!line.hasDropCap && line.visibleChars > 2) {
        final h = line.firstTop - line.firstBottom;
        if (h >= _dropCapRatio * _bodyCap && h >= 1.6 * line.capHeight) {
          line
            ..hasDropCap = true
            ..dropLeft = line.firstLeft
            ..dropRight = line.firstRight
            ..dropBottom = line.firstBottom;
        }
      }
      if (!line.hasDropCap) continue;
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j];
        if (!next.hasBox ||
            next.baseline >= line.baseline ||
            next.top <= line.dropBottom + 0.25 * _bodyCap ||
            next.left < line.dropRight - 0.35 * _bodyCap ||
            next.left - line.dropRight > 3 * _bodyCap) {
          break;
        }
        next.flowLeft = line.dropLeft;
      }
    }
  }

  // ── Text ────────────────────────────────────────────────────────────

  /// Collapses dot leaders, tidies spacing and records what the line's
  /// first and last characters say about it.
  void _finishText(_Line line) {
    var text = line.text;
    if (_leader.hasMatch(text)) {
      final row = _tocTail.firstMatch(text);
      final number = row?.group(1);
      final head = row == null ? '' : text.substring(0, row.start);
      final isRow =
          row != null &&
          _hasWord(head) &&
          _dotCount(row.group(0)!) >= 4 &&
          (number != null
              ? _isPageNumber(number)
              : _dotCount(row.group(0)!) >= 8);
      if (isRow) {
        line.isTocRow = true;
        text = number == null ? head : '$head $number';
      }
      text = text.replaceAllMapped(_leader, (m) {
        final run = m.group(0)!;
        final dots = _dotCount(run);
        if (dots < 4) return run;
        return line.isTocRow || dots >= 8 ? ' ' : '… ';
      });
      text = text.replaceAll(_spaces, ' ').trim();
    }
    text = tidyInlineSpacing(text);
    line
      ..text = text
      ..words = text.isEmpty ? 0 : ' '.allMatches(text).length + 1
      ..isOrnament = !_hasWord(text) && !_closesPrevious.hasMatch(text)
      ..startsLower = _startsLower.hasMatch(text)
      ..endsSentence = _endsSentence.hasMatch(text)
      ..endsHyphen = _endsInHyphen(text)
      ..listMarker =
          _listMarker.hasMatch(text) || _chapterPrefix.hasMatch(text);
    line.endsClause = line.endsSentence || _endsColon.hasMatch(text);
  }

  // ── Pitch ───────────────────────────────────────────────────────────

  int _sizeBucket(double cap) =>
      _bodyCap <= 0 ? 0 : (8 * cap / _bodyCap).round();

  /// The normal baseline-to-baseline distance for each type size: the lower
  /// quartile, so paragraph gaps do not inflate it.
  void _measurePitch() {
    final all = <double>[];
    final bySize = <int, List<double>>{};
    for (final page in _pages) {
      for (var i = 1; i < page.lines.length; i++) {
        final prev = page.lines[i - 1];
        final line = page.lines[i];
        if (!prev.hasBox || !line.hasBox) continue;
        final cap = math.max(prev.capHeight, line.capHeight);
        if (cap <= 0) continue;
        if (math.min(prev.capHeight, line.capHeight) < cap / 1.12) continue;
        final pitch = prev.baseline - line.baseline;
        if (pitch < 0.8 * cap || pitch > 4 * cap) continue;
        if (line.left > prev.right || line.right < prev.left) continue;
        all.add(pitch);
        (bySize[_sizeBucket(cap)] ??= <double>[]).add(pitch);
      }
    }
    _pitch = _quartile(all);
    bySize.forEach((size, samples) {
      if (samples.length >= 4) _pitchBySize[size] = _quartile(samples);
    });
  }

  double _pitchFor(_Line line) {
    final known = _pitchBySize[_sizeBucket(line.capHeight)];
    if (known != null) return known;
    if (_pitch > 0 && _bodyCap > 0) return _pitch * line.capHeight / _bodyCap;
    return 1.75 * line.capHeight;
  }

  // ── 2. Page furniture ───────────────────────────────────────────────

  /// Removes running heads, footers and page numbers.
  ///
  /// A line is furniture only when all of this holds: it is one of the two
  /// outermost lines in the top or bottom zone of its page, it is short, it
  /// stands clear of the text block, and it is either nothing but a page
  /// number or found again in the same zone of other pages. Anything less
  /// certain stays: a leftover header is a nuisance, a deleted line of the
  /// book is a loss.
  void _removeFurniture() {
    final candidates = <_Candidate>[];
    final byPage = <_Page, List<_Candidate>>{};
    for (final page in _pages) {
      final found = _zoneCandidates(page);
      if (found.isEmpty) continue;
      byPage[page] = found;
      candidates.addAll(found);
    }
    if (candidates.isEmpty) return;

    // Bare page numbers, as "label minus page index". Real page numbers
    // agree on that offset from page to page.
    final numbering = <int, Set<int>>{};
    final groups = <String, List<_Candidate>>{};
    for (final c in candidates) {
      _describe(c);
      final pageIndex = c.line.page.pageIndex;
      if (c.pureNumber) {
        (numbering[_offsetKey(c.value, c.roman, pageIndex)] ??= <int>{}).add(
          pageIndex,
        );
      } else {
        (groups['${c.top ? 't' : 'b'}|${c.key}'] ??= <_Candidate>[]).add(c);
      }
    }
    int agreeing(_Candidate c) =>
        numbering[_offsetKey(c.value, c.roman, c.line.page.pageIndex)]
            ?.length ??
        0;

    // Inner lines first: whether the outer line of a zone stands clear of
    // the text depends on what happened to the line between them.
    for (final rank in const [1, 0]) {
      for (final c in candidates) {
        if (c.rank != rank) continue;
        final line = c.line;
        final pageIndex = line.page.pageIndex;
        final threshold = _detachedPitches * math.max(_pitch, _pitchFor(line));
        final partner = c.partner;
        if (partner == null || rank == 1) {
          c.detached = c.gapToText > threshold;
        } else if ((partner.line.baseline - line.baseline).abs() <
            0.5 * _bodyCap) {
          c.detached = c.gapToText > threshold;
        } else {
          c.detached =
              (partner.removed && c.gapToText > threshold) ||
              (partner.line.baseline - line.baseline).abs() > threshold;
        }
        // Furniture stands clear of the text. A speaker's name that opens
        // three pages of a play repeats too, but the speech follows it.
        if (!c.detached) continue;

        if (c.pureNumber) {
          // A number that fits the numbering of other pages is a page
          // number. One that does not is still taken for one, unless the
          // page shows its number elsewhere (then this is a chapter
          // numeral) or it is set large (then it may be a title).
          var numberedElsewhere = false;
          for (final other in byPage[line.page]!) {
            if (!identical(other, c) &&
                other.pureNumber &&
                agreeing(other) >= 2) {
              numberedElsewhere = true;
            }
          }
          final agree = agreeing(c);
          final veryLarge = _bodyCap > 0 && line.capHeight >= 1.25 * _bodyCap;
          c.removed = veryLarge ? agree >= 3 : agree >= 2 || !numberedElsewhere;
          continue;
        }

        // Type as large as a heading has to match to the letter.
        final large =
            _bodyCap > 0 && line.capHeight >= _headingRatio * _bodyCap;
        final group = groups['${c.top ? 't' : 'b'}|${c.key}']!;
        final pagesSeen = <int>{pageIndex};
        // Pages on which the line has text to stand clear of. On a page
        // where it is all there is, "clear of the text" holds with nothing
        // to be clear of: a title alone on three slides, or a refrain alone
        // at the foot of sparse pages, is the page's text and not its
        // furniture. A running head on a blank page still goes, on the
        // evidence of the pages that do have text.
        var besideText = c.gapToText.isFinite ? 1 : 0;
        // Seen again a leaf or two away, at the same height on the page.
        var nearby = false;
        for (final other in group) {
          final otherPage = other.line.page.pageIndex;
          if (otherPage == pageIndex) continue;
          if (_sameFurniture(c, pageIndex, other, otherPage, exact: large)) {
            if (pagesSeen.add(otherPage) && other.gapToText.isFinite) {
              besideText++;
            }
            nearby |=
                (otherPage - pageIndex).abs() <= 4 &&
                (other.line.baseline - line.baseline).abs() <=
                    math.max(2.0, 0.5 * _bodyCap);
          }
        }
        c.removed =
            besideText * 2 >= pagesSeen.length &&
            besideText > 0 &&
            (pagesSeen.length >= 3 || (nearby && !large));
      }
    }

    for (final entry in byPage.entries) {
      final gone = <_Line>{
        for (final c in entry.value)
          if (c.removed) c.line,
      };
      if (gone.isNotEmpty) entry.key.lines.removeWhere(gone.contains);
    }
  }

  /// The outermost one or two lines in each zone of [page], if short.
  List<_Candidate> _zoneCandidates(_Page page) {
    final height = page.raw.height;
    if (height <= 0) return const <_Candidate>[];
    final boxed = <_Line>[
      for (final line in page.lines)
        if (line.hasBox) line,
    ]..sort((a, b) => b.centerY.compareTo(a.centerY));
    if (boxed.isEmpty) return const <_Candidate>[];

    final found = <_Candidate>[];
    final taken = <_Line>{};
    void collect({required bool top}) {
      final zone = <_Candidate>[];
      for (var k = 0; k < 2 && k < boxed.length; k++) {
        final line = top ? boxed[k] : boxed[boxed.length - 1 - k];
        final inZone = top
            ? line.centerY >= height * (1 - _zoneFraction)
            : line.centerY <= height * _zoneFraction;
        if (!inZone || taken.contains(line)) break;
        taken.add(line);
        if (line.words > _maxFurnitureWords ||
            line.text.length > _maxFurnitureChars) {
          // A long line is text; nothing beyond it is furniture either.
          break;
        }
        zone.add(_Candidate(line, top: top, rank: k));
      }
      if (zone.length == 2) {
        zone[0].partner = zone[1];
        zone[1].partner = zone[0];
      }
      found.addAll(zone);
    }

    collect(top: true);
    collect(top: false);
    if (found.isEmpty) return found;

    final candidateLines = <_Line>{for (final c in found) c.line};
    for (final c in found) {
      var nearest = double.infinity;
      for (final line in boxed) {
        if (candidateLines.contains(line)) continue;
        final gap = (line.baseline - c.line.baseline).abs();
        if (gap < nearest) nearest = gap;
      }
      c.gapToText = nearest;
    }
    return found;
  }

  /// Fills in what [c]'s text looks like with its numbers taken out.
  void _describe(_Candidate c) {
    final text = c.line.text;
    final pure = _pageNumberOnly.firstMatch(text);
    if (pure != null) {
      final token = pure.group(1)!;
      final value = _numberValue(token);
      if (value != null) {
        c
          ..pureNumber = true
          ..roman = !_digits.hasMatch(token)
          ..value = value;
        return;
      }
    }
    final parts = <String>[];
    final numbers = <int>[];
    for (final raw in _wordRuns(text)) {
      // Tested in its own case: "Liv" is a name, "liv" a numeral.
      final value = _numberValue(raw);
      if (value != null) {
        parts.add('#');
        numbers.add(value);
      } else if (_hasDigit.hasMatch(raw)) {
        parts.add(
          raw.toLowerCase().replaceAllMapped(_digitRun, (m) {
            final digits = m.group(0)!;
            numbers.add(digits.length > 9 ? 0 : int.parse(digits));
            return '#';
          }),
        );
      } else {
        parts.add(raw.toLowerCase());
      }
    }
    // The page number may sit on either side of a running head.
    while (parts.isNotEmpty && parts.first == '#') {
      parts.removeAt(0);
    }
    while (parts.isNotEmpty && parts.last == '#') {
      parts.removeLast();
    }
    c
      ..key = parts.join(' ')
      ..numbers = numbers;
  }

  /// Whether two zone lines are the same piece of furniture: the same words
  /// with numbers that stay put or advance with the page. "Chapter 1" on
  /// one page and "Chapter 2" twenty pages on are headings, not a header.
  bool _sameFurniture(
    _Candidate a,
    int pageA,
    _Candidate b,
    int pageB, {
    required bool exact,
  }) {
    if (a.numbers.length != b.numbers.length) return false;
    var equal = true;
    var advances = false;
    for (var i = 0; i < a.numbers.length; i++) {
      final delta = b.numbers[i] - a.numbers[i];
      if (delta != 0) equal = false;
      if (delta != 0 && delta == pageB - pageA) advances = true;
    }
    return equal || (advances && !exact);
  }

  // ── Reading order ───────────────────────────────────────────────────

  /// pdfium lists text in the order the file draws it, and some files draw
  /// what sits at the foot of the page first. Lines at the start of the
  /// page that lie below everything else are moved to the end.
  void _restoreReadingOrder(_Page page) {
    final lines = page.lines;
    final n = lines.length;
    if (n < 2) return;
    for (final line in lines) {
      if (!line.hasBox) return;
    }
    // lowest[i]: the lowest bottom edge among lines i..n-1.
    final lowest = List<double>.filled(n + 1, double.infinity);
    for (var i = n - 1; i >= 0; i--) {
      lowest[i] = math.min(lowest[i + 1], lines[i].bottom);
    }
    var highest = double.negativeInfinity;
    for (var k = 1; k < n; k++) {
      highest = math.max(highest, lines[k - 1].top);
      if (highest <= lowest[k]) {
        page.lines = <_Line>[...lines.sublist(k), ...lines.sublist(0, k)];
        return;
      }
    }
  }

  void _indexLines(_Page page) {
    for (var i = 0; i < page.lines.length; i++) {
      page.lines[i].index = i;
    }
  }

  double get _edgeTolerance => math.max(1.5, 0.3 * _bodyCap);

  /// Groups the page's lines by right edge. Three or more lines ending at
  /// the same place mark where a column ends, which is what a line has to
  /// fall short of to count as short.
  void _findColumns(_Page page) {
    final lines = <_Line>[
      for (final line in page.lines)
        if (line.hasBox && !line.isOrnament) line,
    ]..sort((a, b) => a.right.compareTo(b.right));
    final columns = <_Column>[];
    var i = 0;
    while (i < lines.length) {
      var j = i;
      var left = lines[i].flowLeft;
      while (j + 1 < lines.length &&
          lines[j + 1].right - lines[j].right <= _edgeTolerance) {
        j++;
        left = math.min(left, lines[j].flowLeft);
      }
      if (j - i + 1 >= 3) columns.add(_Column(left, lines[j].right));
      i = j + 1;
    }
    page.columns = columns;
  }

  // ── 3. Contents rows and headings ───────────────────────────────────

  /// Completes contents rows: a row without a leader between leader rows,
  /// and the label line(s) of an entry whose last line carries the leader
  /// ("CHAPTER I." above "Down the Rabbit-Hole . . . . 4").
  void _markContents(_Page page) {
    final lines = page.lines;
    var any = false;
    for (final line in lines) {
      any |= line.isTocRow;
    }
    if (!any) return;

    bool close(_Line upper, _Line lower) {
      if (!upper.hasBox || !lower.hasBox) return true;
      final pitch = upper.baseline - lower.baseline;
      return pitch > 0 && pitch <= 1.6 * _pitchFor(lower);
    }

    bool plain(_Line line) =>
        !line.isTocRow &&
        !line.isOrnament &&
        line.words <= _maxHeadingWords &&
        (_bodyCap <= 0 || line.capHeight < _headingRatio * _bodyCap);

    final leaderRows = <_Line>{
      for (final line in lines)
        if (line.isTocRow) line,
    };
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!plain(line) || !_endsPageNumber(line.text)) continue;
      final before = i > 0 && leaderRows.contains(lines[i - 1]);
      final after = i + 1 < lines.length && leaderRows.contains(lines[i + 1]);
      if ((before && close(lines[i - 1], line)) ||
          (after && close(line, lines[i + 1]))) {
        line.isTocRow = true;
      }
    }
    for (var i = 0; i < lines.length; i++) {
      if (!leaderRows.contains(lines[i])) continue;
      for (var j = i - 1; j >= 0 && j >= i - 2; j--) {
        final label = lines[j];
        if (!plain(label) ||
            label.isTocLabel ||
            _endsPageNumber(label.text) ||
            !close(label, lines[j + 1])) {
          break;
        }
        label.isTocLabel = true;
      }
    }
  }

  void _markHeadings(_Page page) {
    if (_bodyCap <= 0) return;
    final lines = page.lines;

    bool eligible(_Line line) =>
        line.hasBox &&
        line.isBody &&
        line.words <= _maxHeadingWords &&
        !line.hasDropCap;

    // By size.
    for (final line in lines) {
      if (!eligible(line)) continue;
      final ratio = line.capHeight / _bodyCap;
      if (ratio < _headingRatio) continue;
      line.heading = ratio >= _headingLevel1Ratio
          ? 1
          : ratio >= _headingLevel2Ratio
          ? 2
          : 3;
    }
    _demoteLargeText(lines);

    // By wording, for lines that stand apart. Twice, so a label and the
    // title under it each see the other as a heading.
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.heading > 0 || !eligible(line)) continue;
        final level = _headingByWording(line.text);
        if (level > 0 && _standsApart(lines, i)) line.heading = level;
      }
    }
  }

  /// A long run of large lines is a paragraph set in large type, and so is
  /// a shorter one that reads as a sentence: more than a line's worth of
  /// words closed by a full stop.
  void _demoteLargeText(List<_Line> lines) {
    var i = 0;
    while (i < lines.length) {
      if (lines[i].heading == 0) {
        i++;
        continue;
      }
      var j = i;
      var words = lines[i].words;
      while (j + 1 < lines.length && _stacks(lines[j], lines[j + 1])) {
        j++;
        words += lines[j].words;
      }
      final prose = words > _maxHeadingWords && lines[j].text.endsWith('.');
      if (prose ||
          j - i + 1 > _maxHeadingLines ||
          words > _maxHeadingRunWords) {
        for (var k = i; k <= j; k++) {
          lines[k].heading = 0;
        }
      }
      i = j + 1;
    }
  }

  /// Whether heading line [b] continues heading line [a]: the same size,
  /// directly beneath.
  bool _stacks(_Line a, _Line b) {
    if (a.heading == 0 || b.heading == 0) return false;
    if (!a.hasBox || !b.hasBox) return false;
    final big = math.max(a.capHeight, b.capHeight);
    if (math.min(a.capHeight, b.capHeight) < big / 1.1) return false;
    final pitch = a.baseline - b.baseline;
    return pitch > 0 && pitch <= _headingStackPitch * big;
  }

  bool _standsApart(List<_Line> lines, int i) {
    final line = lines[i];
    final clear = _isolatedPitches * _pitchFor(line);
    if (i > 0) {
      final above = lines[i - 1];
      if (above.heading == 0 && above.hasBox) {
        final gap = above.baseline - line.baseline;
        if (gap > 0 && gap <= clear) return false;
        if (gap.abs() < 0.5 * _bodyCap) return false;
      }
    }
    if (i + 1 < lines.length) {
      final below = lines[i + 1];
      if (below.heading == 0 && below.hasBox) {
        final gap = line.baseline - below.baseline;
        if (gap > 0 && gap <= clear) return false;
        if (gap.abs() < 0.5 * _bodyCap) return false;
      }
    }
    return true;
  }

  /// The heading level [text] suggests by its wording alone, or 0.
  int _headingByWording(String text) {
    final numbered = _numberedHeading.firstMatch(text);
    if (numbered != null) {
      final number = numbered.group(1)!;
      final title = numbered.group(2)!;
      // "Chapter Vivid" is not chapter 5-something.
      if (number.length > 1 &&
          !_numberWord.hasMatch(number) &&
          _numberValue(number) == null) {
        return 0;
      }
      if (title.isEmpty) return 3;
      if (_startsUpper.hasMatch(title) && !_endsSoft.hasMatch(title)) return 3;
      return 0;
    }
    if (_namedHeading.hasMatch(text)) return 3;
    final bare = _bareNumeral.firstMatch(text);
    if (bare != null && _numberValue(bare.group(1)!) != null) return 3;
    final section = _sectionHeading.firstMatch(text);
    if (section != null) {
      final depth = '.'.allMatches(section.group(1)!).length;
      return math.min(6, 3 + depth);
    }
    if (_isAllCapsTitle(text)) return 3;
    return 0;
  }

  bool _isAllCapsTitle(String text) {
    if (!_startsWithWord(text) || _endsStop.hasMatch(text)) return false;
    if (_lowerLetter.hasMatch(text)) return false;
    final letters = _upperLetter.allMatches(text).length;
    return letters >= 3 && letters * 2 >= text.replaceAll(' ', '').length;
  }

  // ── Outline ─────────────────────────────────────────────────────────

  /// Finds the line each bookmark points at: the line that carries its
  /// title near the position it names, else the first line below that
  /// position, else (a bookmark without a position) the top of the page.
  ///
  /// A line that *is* the bookmark's title opens a unit of text, and is a
  /// heading if short. A bookmark that merely lands in running text marks
  /// the place and changes nothing.
  List<_Line?> _locateOutline() {
    final byIndex = <int, _Page>{for (final p in _pages) p.pageIndex: p};
    final located = <_Line?>[];
    for (final target in _outline) {
      final page = byIndex[target.pageIndex];
      if (page == null || !page.emitted || page.lines.isEmpty) {
        located.add(null);
        continue;
      }
      final title = _squash(target.title);
      final y = target.top;
      _Line? byPlace;
      _Line? byTitle;
      var placeScore = double.infinity;
      var titleScore = double.infinity;
      var titleMatch = 0;
      for (final line in page.lines) {
        if (line.isOrnament) continue;
        final match = _titleMatch(_squash(line.text), title);
        if (y == null || !line.hasBox) {
          if (match > titleMatch) {
            titleMatch = match;
            byTitle = line;
          }
          continue;
        }
        final x = target.left;
        final aside = x == null ? 0.0 : 0.05 * (line.left - x).abs();
        final drop = y - line.top;
        if (drop >= -math.max(2.0, 0.6 * _bodyCap) &&
            drop + aside < placeScore) {
          placeScore = drop + aside;
          byPlace = line;
        }
        if (match > 0 &&
            drop >= -2.5 * math.max(_bodyCap, line.capHeight) &&
            drop <= 0.25 * page.raw.height &&
            (match > titleMatch ||
                (match == titleMatch && drop.abs() < titleScore))) {
          titleMatch = match;
          titleScore = drop.abs();
          byTitle = line;
        }
      }
      final line = byTitle ?? byPlace ?? (y == null ? page.lines.first : null);
      located.add(line);
      if (line == null || !identical(line, byTitle) || titleMatch < 2) {
        continue;
      }
      line.forceStart = true;
      if (line.isBody && line.words <= _maxHeadingWords && !line.hasDropCap) {
        line.heading = math.min(6, 3 + target.depth);
      }
    }
    return located;
  }

  /// How well [line] matches a bookmark's [title] (both reduced to letters
  /// and digits): 2 when the line is the title, or its first line, or the
  /// title behind a section number; 1 when the line only begins with it;
  /// 0 otherwise.
  int _titleMatch(String line, String title) {
    if (title.isEmpty || line.isEmpty) return 0;
    if (line == title) return 2;
    // "1 Introduction" for the bookmark "Introduction".
    if (line.endsWith(title) && line.length - title.length <= 6) return 2;
    // The first line of a title that wraps.
    if (title.startsWith(line) && line.length >= 4) return 2;
    // A line that goes on after the title: enough to find the place.
    return line.startsWith(title) && title.length >= 6 ? 1 : 0;
  }

  // ── 4. Paragraphs and text ──────────────────────────────────────────

  PdfLayoutResult _emit(List<_Line?> located) {
    _Paragraph? paragraph;
    _Line? prevBody;
    _Line? lastBody;
    var first = true;
    var continuesPrevious = false;
    var lastUnitIsBody = false;

    void flush() {
      final p = paragraph;
      paragraph = null;
      if (p != null) _emitParagraph(p);
    }

    final emitted = <_Page>[
      for (final page in _pages)
        if (page.emitted) page,
    ];
    for (final page in emitted) {
      final lines = page.lines;
      var i = 0;
      while (i < lines.length) {
        final line = lines[i];
        if (line.isOrnament) {
          // A row of asterisks marks a break in the text: it stands alone,
          // joined to neither the paragraph before nor the one after.
          flush();
          final alone = _Paragraph(startsParagraph: true);
          _append(alone, line);
          _emitParagraph(alone);
          prevBody = null;
          lastUnitIsBody = false;
          first = false;
          i++;
          continue;
        }
        if (line.heading > 0) {
          flush();
          prevBody = null;
          var j = i;
          while (j + 1 < lines.length &&
              !lines[j + 1].forceStart &&
              _stacks(lines[j], lines[j + 1])) {
            j++;
          }
          _emitUnit(lines.sublist(i, j + 1), heading: _levelOf(lines, i, j));
          lastUnitIsBody = false;
          first = false;
          i = j + 1;
          continue;
        }
        if (line.isTocRow || line.isTocLabel) {
          flush();
          prevBody = null;
          var j = i;
          while (lines[j].isTocLabel &&
              j + 1 < lines.length &&
              (lines[j + 1].isTocLabel || lines[j + 1].isTocRow)) {
            j++;
          }
          _emitUnit(lines.sublist(i, j + 1), heading: 0);
          lastUnitIsBody = false;
          first = false;
          i = j + 1;
          continue;
        }

        bool starts;
        final prev = prevBody;
        if (prev != null) {
          starts = identical(prev.page, line.page)
              ? _breaksWithinPage(prev, line)
              : _breaksAcrossPages(prev, line).starts;
        } else if (first) {
          final before = _lineBefore(page);
          if (before != null) {
            final across = _breaksAcrossPages(before, line);
            starts = across.starts;
            continuesPrevious = across.continues;
          } else if (page.pageIndex == 0 || _textBefore(page)) {
            starts = true;
          } else {
            // Nothing is known about the previous page.
            continuesPrevious = line.startsLower && !_indented(line);
            starts = !continuesPrevious;
          }
        } else {
          starts = true;
        }
        if (line.forceStart) {
          starts = true;
          if (first) continuesPrevious = false;
        }
        if (starts || paragraph == null) {
          flush();
          paragraph = _Paragraph(startsParagraph: starts);
        }
        _append(paragraph!, line);
        prevBody = line;
        lastBody = line;
        lastUnitIsBody = true;
        first = false;
        i++;
      }
    }
    flush();

    final endsWithSplitWord =
        lastUnitIsBody && lastBody != null && _markSplitWord(lastBody);
    final words = <String>[for (final s in _sentences) ...s.words];
    final starts = _pageStarts(emitted, words);
    if (continuesPrevious && starts.isNotEmpty && words.isNotEmpty) {
      _relabelFirstPage(emitted, starts, words);
    }
    return PdfLayoutResult(
      sentences: _sentences,
      pageStarts: starts,
      outline: _outlineEntries(located, starts),
      continuesPrevious: continuesPrevious && _sentences.isNotEmpty,
      endsWithSplitWord: endsWithSplitWord,
    );
  }

  int _levelOf(List<_Line> lines, int from, int to) {
    var level = lines[from].heading;
    for (var k = from + 1; k <= to; k++) {
      level = math.min(level, lines[k].heading);
    }
    return level;
  }

  /// The last line of text before [page] in the window, when it is running
  /// text; null when there is none or it is a heading or a contents row.
  _Line? _lineBefore(_Page page) {
    for (var s = page.slot - 1; s >= 0; s--) {
      final lines = _pages[s].lines;
      if (lines.isEmpty) continue;
      final last = lines.last;
      return last.isBody ? last : null;
    }
    return null;
  }

  /// Whether any earlier page in the window has text.
  bool _textBefore(_Page page) {
    for (var s = page.slot - 1; s >= 0; s--) {
      if (_pages[s].lines.isNotEmpty) return true;
    }
    return false;
  }

  /// The first line of text after [page] in the window, or null.
  _Line? _lineAfter(_Page page) {
    for (var s = page.slot + 1; s < _pages.length; s++) {
      final lines = _pages[s].lines;
      if (lines.isNotEmpty) return lines.first;
    }
    return null;
  }

  // Paragraph breaks ────────────────────────────────────────────────────

  /// Whether [line] opens a paragraph, given the body line [prev] before it
  /// on the same page.
  bool _breaksWithinPage(_Line prev, _Line line) {
    // Text with a layout and text without one are different passages.
    if (prev.hasBox != line.hasBox) return true;
    if (!prev.hasBox) return false;
    final cap = math.max(prev.capHeight, line.capHeight);
    final drop = prev.baseline - line.baseline;
    final sameColumn = line.left <= prev.right && line.right >= prev.left;
    if (drop.abs() < 0.4 * cap && line.left >= prev.left) {
      return false; // the same row, further along
    }
    if (drop <= 0 || !sameColumn) {
      // The text moved to another column or block.
      return _breaksAcrossPages(prev, line).starts;
    }
    if (math.min(prev.capHeight, line.capHeight) < cap / 1.18) return true;
    if (drop > _paragraphGapPitches * _pitchFor(line)) return true;
    // Half a word is waiting for the rest of it. (Only pdfium's own mark
    // says so for certain: a hyphen at a line end may be standing in for
    // a dash.)
    if (prev.softBreak) return false;
    if (line.listMarker && prev.listMarker) return true;
    if (line.startsLower) return false;
    final short = _fitsAfter(prev, line);
    if (line.flowLeft - prev.flowLeft >= _minIndent &&
        (prev.endsClause || short)) {
      return true;
    }
    if (short && (prev.endsClause || line.listMarker || _indented(line))) {
      return true;
    }
    return short && _clearlyShort(prev);
  }

  /// Whether [line] opens a paragraph when [prev] is the last body line
  /// before a page (or column) break, and whether [prev]'s sentence runs on
  /// into it.
  ({bool starts, bool continues}) _breaksAcrossPages(_Line prev, _Line line) {
    final broken = prev.softBreak || prev.endsHyphen;
    if (line.startsLower) {
      return (starts: false, continues: broken || !prev.endsSentence);
    }
    if (!prev.endsSentence) {
      if (prev.softBreak || (prev.endsHyphen && _finishesWord(line))) {
        return (starts: false, continues: true);
      }
      if (_fitsAfter(prev, line) && _clearlyShort(prev)) {
        return (starts: true, continues: false);
      }
      return (starts: false, continues: true);
    }
    return (
      starts: _indented(line) || _fitsAfter(prev, line),
      continues: false,
    );
  }

  /// Whether [line], which follows a line ending in a hyphen and does not
  /// begin in lower case, can be the second half of that word ("Anglo-" +
  /// "Saxon"). An indented line, or one that opens with a quotation mark,
  /// is a new start: the hyphen before it was standing in for a dash.
  bool _finishesWord(_Line line) =>
      _startsWithWord(line.text) && !_indented(line);

  double get _minIndent => math.max(2.5, 0.55 * _bodyCap);

  /// Whether [line] is indented against the lines that follow it.
  bool _indented(_Line line) {
    if (!line.hasBox) return false;
    final lines = line.page.lines;
    var margin = double.infinity;
    var seen = 0;
    for (var j = line.index + 1; j < lines.length && seen < 3; j++) {
      final next = lines[j];
      if (!_sameColumn(line, next) || next.baseline >= line.baseline) break;
      margin = math.min(margin, next.flowLeft);
      seen++;
    }
    return seen > 0 && line.flowLeft - margin >= _minIndent;
  }

  bool _sameColumn(_Line a, _Line b) {
    if (!a.hasBox || !b.hasBox || !b.isBody) return false;
    if (b.left > a.right || b.right < a.left) return false;
    final cap = math.max(a.capHeight, b.capHeight);
    return math.min(a.capHeight, b.capHeight) >= cap / 1.2;
  }

  /// The left and right edges of the column [line] belongs to: the block
  /// of lines on its page that it starts with and does not overrun. On a
  /// page with no such block (verse, a list) the widest of the lines around
  /// it stands in.
  ({double left, double right})? _column(_Line line) {
    _Column? best;
    var bestOffset = double.infinity;
    for (final column in line.page.columns) {
      if (column.right < line.right - _edgeTolerance) continue;
      if (column.left > line.right || column.right < line.left) continue;
      final offset = (column.left - line.flowLeft).abs();
      if (offset < bestOffset ||
          (offset == bestOffset && best != null && column.right < best.right)) {
        best = column;
        bestOffset = offset;
      }
    }
    if (best != null) return (left: best.left, right: best.right);

    final lines = line.page.lines;
    var right = double.negativeInfinity;
    var left = line.flowLeft;
    for (final step in const [-1, 1]) {
      var found = 0;
      for (
        var j = line.index + step, steps = 0;
        j >= 0 && j < lines.length && steps < 6;
        j += step, steps++
      ) {
        final other = lines[j];
        if (!_sameColumn(line, other)) continue;
        right = math.max(right, other.right);
        left = math.min(left, other.flowLeft);
        if (++found >= _neighbourLines) break;
      }
    }
    return right.isInfinite ? null : (left: left, right: right);
  }

  /// Whether the first word of [next] would have fitted at the end of
  /// [line]: the line was ended on purpose, not by running out of room.
  bool _fitsAfter(_Line line, _Line next) {
    if (!line.hasBox) return false;
    final column = _column(line);
    if (column == null) return false;
    final cap = line.capHeight;
    final word = next.hasBox && next.firstWordWidth > 0
        ? next.firstWordWidth
        : 3 * cap;
    return line.right + 0.3 * cap + word + 0.3 * cap <= column.right;
  }

  /// Whether [line] stops well short of its column.
  bool _clearlyShort(_Line line) {
    final column = _column(line);
    if (column == null) return false;
    final width = column.right - column.left;
    return width > 0 && column.right - line.right >= _clearShortfall * width;
  }

  // Assembly ────────────────────────────────────────────────────────────

  /// Adds [line]'s words to [paragraph], repairing the join with the line
  /// before it.
  void _append(_Paragraph paragraph, _Line line) {
    final prev = paragraph.lines.isEmpty ? null : paragraph.lines.last;
    line.firstToken = _appendTokens(paragraph.tokens, prev, line);
    paragraph.lines.add(line);
  }

  /// Appends [line]'s words to [tokens] and returns the index of its first
  /// word, which is the last word of [prev] when the two were one word.
  int _appendTokens(List<String> tokens, _Line? prev, _Line line) {
    final words = line.text.split(' ');
    if (prev == null || tokens.isEmpty) {
      tokens.addAll(words);
      return 0;
    }
    final last = tokens.last;
    final first = words.first;
    String? glued;
    if (prev.softBreak) {
      glued = _joinBroken(last, first);
    } else if (prev.endsHyphen) {
      if (line.startsLower) {
        glued = _joinBroken(last.substring(0, last.length - 1), first);
      } else if (_finishesWord(line)) {
        glued = '$last$first'; // "Anglo-" + "Saxon"
      }
    } else if (_endsClosedDash.hasMatch(last) ||
        _startsClosedDash.hasMatch(first) ||
        _startsClosing.hasMatch(first) ||
        _endsOpening.hasMatch(last) ||
        // A closing quote that wrapped onto a line by itself.
        (!_hasWord(line.text) && _closesPrevious.hasMatch(first))) {
      glued = '$last$first';
    }
    if (glued == null || glued.contains(' ')) {
      if (glued != null) {
        // A suspended hyphen: "pre- and post-war".
        tokens[tokens.length - 1] = glued.substring(0, glued.indexOf(' '));
      }
      final index = tokens.length;
      tokens.addAll(words);
      return index;
    }
    final index = tokens.length - 1;
    tokens[index] = glued;
    tokens.addAll(words.skip(1));
    return index;
  }

  /// Joins the halves of a word broken at a line end: "con" + "fidences".
  ///
  /// The document decides where it can: if the joined word occurs elsewhere
  /// it is one word; if the hyphenated form occurs, the hyphen belongs to
  /// it. A compound of several parts broken between two whole words keeps
  /// its hyphen ("English" + "to-German"), unlike one whose own part was
  /// hyphenated ("un" + "der-mate"). Otherwise [joinSplitWord] decides.
  String _joinBroken(String left, String right) {
    final a = _core(left);
    final b = _core(right);
    if (a.isEmpty || b.isEmpty) return '$left$right';
    if (_known('$a$b')) return '$left$right';
    if (_known('$a-$b')) return '$left-$right';
    if (a.contains('-') || b.contains('-')) {
      final before = a.substring(a.lastIndexOf('-') + 1);
      final cut = b.indexOf('-');
      final after = cut < 0 ? b : b.substring(0, cut);
      if (_known(before) && _known(after)) return '$left-$right';
    }
    if (_conjunctions.contains(b)) return '$left- $right';
    if (_allCaps.hasMatch(left) && _startsTwoCaps.hasMatch(right)) {
      return '$left$right'; // "LI" + "CENSE"
    }
    final joined = joinSplitWord('$left-', right);
    // joinSplitWord keeps the hyphen after a prefix such as "ex", "self" or
    // "great". At a line break that is wrong when the prefix is simply how
    // the word begins ("ex-" + "plained") or an ending follows ("self-" +
    // "ish", "great-" + "er").
    if (joined == '$left-$right' &&
        _startsLower.hasMatch(right) &&
        (a == 'ex' || _wordEndings.contains(b))) {
      return '$left$right';
    }
    return joined;
  }

  /// Emits a body paragraph through the shared sentence segmenter.
  void _emitParagraph(_Paragraph p) {
    if (p.tokens.isEmpty) return;
    final sentences = textToSentences(p.tokens.join(' '));
    final at = _align(p.tokens, sentences);
    for (final line in p.lines) {
      line.wordIndex = _wordCount + at[line.firstToken];
    }
    for (var k = 0; k < sentences.length; k++) {
      final s = sentences[k];
      _sentenceStarts.add(_wordCount);
      _wordCount += s.words.length;
      _sentences.add(
        k == 0
            ? Sentence(words: s.words, startsParagraph: p.startsParagraph)
            : s,
      );
    }
  }

  /// Emits a heading or a contents row as one sentence, never split on its
  /// own punctuation.
  void _emitUnit(List<_Line> lines, {required int heading}) {
    final tokens = <String>[];
    _Line? prev;
    for (final line in lines) {
      line.firstToken = _appendTokens(tokens, prev, line);
      prev = line;
    }
    for (final line in lines) {
      line.wordIndex = _wordCount + line.firstToken;
    }
    if (tokens.isEmpty) return;
    _sentenceStarts.add(_wordCount);
    _wordCount += tokens.length;
    _sentences.add(
      Sentence(words: tokens, startsParagraph: true, heading: heading),
    );
  }

  /// Maps each of [tokens] to its position among the words the segmenter
  /// returned. The segmenter may drop a token (a stray full stop); nothing
  /// else changes, so the words are a subsequence of the tokens.
  List<int> _align(List<String> tokens, List<Sentence> sentences) {
    final at = List<int>.filled(tokens.length + 1, 0);
    var total = 0;
    for (final s in sentences) {
      total += s.words.length;
    }
    if (total == tokens.length) {
      for (var i = 0; i <= tokens.length; i++) {
        at[i] = i;
      }
      return at;
    }
    final words = <String>[for (final s in sentences) ...s.words];
    var k = 0;
    for (var i = 0; i < tokens.length; i++) {
      at[i] = k;
      if (k < words.length && words[k] == tokens[i]) k++;
    }
    at[tokens.length] = k;
    if (k != words.length) {
      for (var i = 0; i <= tokens.length; i++) {
        at[i] = tokens.isEmpty ? 0 : i * total ~/ tokens.length;
      }
    }
    return at;
  }

  // Window edges ────────────────────────────────────────────────────────

  /// Leaves [kSplitWordMarker] on the last word when the window's last line
  /// ends in half a word and the text after the window carries on with it.
  bool _markSplitWord(_Line last) {
    if (!last.softBreak && !last.endsHyphen) return false;
    if (_sentences.isEmpty) return false;
    final next = _lineAfter(last.page);
    if (next != null) {
      if (!next.isBody || !_breaksAcrossPages(last, next).continues) {
        return false;
      }
    }
    final sentence = _sentences.last;
    if (sentence.isHeading || sentence.words.isEmpty) return false;
    final word = sentence.words.last;
    final stem = last.softBreak ? word : _withoutTrailingHyphens(word);
    if (stem.isEmpty || (!last.softBreak && stem == word)) return false;
    _sentences[_sentences.length - 1] = Sentence(
      words: <String>[
        ...sentence.words.take(sentence.words.length - 1),
        '$stem$kSplitWordMarker',
      ],
      startsParagraph: sentence.startsParagraph,
    );
    return true;
  }

  // Positions ───────────────────────────────────────────────────────────

  int _sentenceAt(int wordIndex) {
    if (wordIndex >= _wordCount) return _sentences.length;
    var lo = 0;
    var hi = _sentenceStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_sentenceStarts[mid] <= wordIndex) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  List<PdfPageStart> _pageStarts(List<_Page> emitted, List<String> words) {
    final starts = List<int>.filled(emitted.length, -1);
    for (var p = 0; p < emitted.length; p++) {
      for (final line in emitted[p].lines) {
        if (line.wordIndex >= 0) {
          starts[p] = line.wordIndex;
          break;
        }
      }
    }
    // A page with no text begins where the next text begins.
    var next = _wordCount;
    for (var p = emitted.length - 1; p >= 0; p--) {
      if (starts[p] < 0) {
        starts[p] = next;
      } else {
        next = starts[p];
      }
    }
    return <PdfPageStart>[
      for (var p = 0; p < emitted.length; p++)
        PdfPageStart(
          pageIndex: emitted[p].pageIndex,
          startWordIndex: starts[p],
          startSentenceIndex: _sentenceAt(starts[p]),
          firstWords: _preview(
            words,
            starts[p],
            p + 1 < emitted.length ? starts[p + 1] : _wordCount,
          ),
        ),
    ];
  }

  String _preview(List<String> words, int from, int to) {
    final end = math.min(math.min(from + 5, to), words.length);
    return from >= end ? '' : words.sublist(from, end).join(' ');
  }

  /// A window that opens on the second half of a hyphenated word labels its
  /// first page with the whole word, as the merged document will read.
  void _relabelFirstPage(
    List<_Page> emitted,
    List<PdfPageStart> starts,
    List<String> words,
  ) {
    final before = _lineBefore(emitted.first);
    if (before == null || !(before.softBreak || before.endsHyphen)) return;
    final first = starts.first;
    if (first.startWordIndex != 0 || first.firstWords.isEmpty) return;
    final half = before.text.substring(before.text.lastIndexOf(' ') + 1);
    final rest = first.firstWords.contains(' ')
        ? first.firstWords.substring(first.firstWords.indexOf(' '))
        : '';
    starts[0] = PdfPageStart(
      pageIndex: first.pageIndex,
      startWordIndex: first.startWordIndex,
      startSentenceIndex: first.startSentenceIndex,
      firstWords:
          '${joinSplitWord('$half$kSplitWordMarker', words.first)}$rest',
    );
  }

  List<OutlineEntry> _outlineEntries(
    List<_Line?> located,
    List<PdfPageStart> starts,
  ) {
    final pageStart = <int, int>{
      for (final s in starts) s.pageIndex: s.startWordIndex,
    };
    final entries = <OutlineEntry>[];
    for (var i = 0; i < _outline.length; i++) {
      final target = _outline[i];
      final fallback = pageStart[target.pageIndex];
      if (fallback == null) continue; // not an emitted page
      final line = located[i];
      final word = line != null && line.wordIndex >= 0
          ? line.wordIndex
          : fallback;
      entries.add(
        OutlineEntry(
          title: target.title.replaceAll(_spaces, ' ').trim(),
          startWordIndex: word,
          startSentenceIndex: _sentenceAt(word),
          depth: target.depth,
        ),
      );
    }
    // Reading order; bookmarks at the same place keep their tree order.
    final order = List<int>.generate(entries.length, (i) => i)
      ..sort((a, b) {
        final byWord = entries[a].startWordIndex.compareTo(
          entries[b].startWordIndex,
        );
        return byWord != 0 ? byWord : a.compareTo(b);
      });
    return <OutlineEntry>[for (final i in order) entries[i]];
  }
}

// ── Characters ────────────────────────────────────────────────────────

bool _isSpace(int c) =>
    c == 0x20 ||
    c == 0x09 ||
    c == 0x0B ||
    c == 0x0C ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000;

/// Control characters (pdfium's line and hyphenation marks, a page-number
/// placeholder), zero-width characters, the replacement character, and the
/// private-use characters this app reserves for its own extraction marks
/// ([kReservedMarkChars]): a PDF that happened to contain one at the start
/// of a paragraph would have that paragraph read as a marked heading.
bool _isIgnorable(int c) =>
    c < 0x20 ||
    (c >= 0x7F && c <= 0x9F) ||
    (c >= 0xE000 && c <= 0xE00F) ||
    c == 0x200B ||
    c == 0x200E ||
    c == 0x200F ||
    c == 0x2060 ||
    c == 0xFEFF ||
    c == 0xFFFD;

/// Letters and digits, as opposed to punctuation and symbols.
///
/// A plain test on the code unit: these checks run for every character and
/// every word, where a `\p{L}` pattern is many times slower. Beyond Latin-1
/// everything counts as a letter except the punctuation and symbol blocks
/// (U+2000–U+2BFF: dashes, quotes, arrows, shapes, dingbats) and CJK
/// punctuation.
bool _isWordChar(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0xC0 &&
        c != 0xD7 &&
        c != 0xF7 &&
        !(c >= 0x2000 && c <= 0x2BFF) &&
        !(c >= 0x3000 && c <= 0x303F));

/// Whether [text] holds a letter or a digit.
bool _hasWord(String text) {
  for (var i = 0; i < text.length; i++) {
    if (_isWordChar(text.codeUnitAt(i))) return true;
  }
  return false;
}

/// Whether [text] begins with a letter or a digit.
bool _startsWithWord(String text) =>
    text.isNotEmpty && _isWordChar(text.codeUnitAt(0));

/// A hyphen that can end a line inside a word: the hyphen-minus, the
/// hyphen (U+2010) and the non-breaking hyphen (U+2011).
bool _isHyphen(int c) => c == 0x2D || c == 0x2010 || c == 0x2011;

/// Whether [text] ends in a hyphen attached to a word.
bool _endsInHyphen(String text) {
  final n = text.length;
  return n >= 2 &&
      _isHyphen(text.codeUnitAt(n - 1)) &&
      _isWordChar(text.codeUnitAt(n - 2));
}

/// [word] without the hyphens at its end.
String _withoutTrailingHyphens(String word) {
  var end = word.length;
  while (end > 0 && _isHyphen(word.codeUnitAt(end - 1))) {
    end--;
  }
  return word.substring(0, end);
}

/// The runs of letters and digits in [text].
List<String> _wordRuns(String text) {
  final runs = <String>[];
  var start = -1;
  for (var i = 0; i <= text.length; i++) {
    final inWord = i < text.length && _isWordChar(text.codeUnitAt(i));
    if (inWord) {
      if (start < 0) start = i;
    } else if (start >= 0) {
      runs.add(text.substring(start, i));
      start = -1;
    }
  }
  return runs;
}

/// Lower-case letters exactly one x-height tall: no ascender, descender,
/// dot or accent.
bool _isXClass(int c) =>
    c == 0x61 ||
    c == 0x63 ||
    c == 0x65 ||
    c == 0x6D ||
    c == 0x6E ||
    c == 0x6F ||
    c == 0x72 ||
    c == 0x73 ||
    (c >= 0x75 && c <= 0x78) ||
    c == 0x7A;

/// Capitals, digits and plain ascenders: glyphs as tall as the type's cap
/// height. J and Q are left out because their tails make them taller.
bool _isCapClass(int c) =>
    (c >= 0x41 && c <= 0x5A && c != 0x4A && c != 0x51) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x62 ||
    c == 0x64 ||
    c == 0x68 ||
    c == 0x6B ||
    c == 0x6C;

const Map<int, String> _ligatures = <int, String>{
  0xFB00: 'ff',
  0xFB01: 'fi',
  0xFB02: 'fl',
  0xFB03: 'ffi',
  0xFB04: 'ffl',
  0xFB05: 'st',
  0xFB06: 'st',
};

/// Letters that are words by themselves, lower-cased.
const Set<String> _standaloneCaps = <String>{'a', 'i', 'o'};

/// Endings that make one word with what precedes them, never a compound.
const Set<String> _wordEndings = <String>{
  's',
  'es',
  'ed',
  'er',
  'ers',
  'est',
  'ing',
  'ings',
  'ish',
  'ly',
  'ness',
  'ful',
  'fully',
  'less',
  'ment',
  'ments',
  'hood',
  'ways',
  'wise',
};

/// Words after which a line-end hyphen is a suspended one ("pre- and").
const Set<String> _conjunctions = <String>{'and', 'or', 'und', 'oder'};

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.of(values)..sort();
  return sorted[sorted.length ~/ 2];
}

double _quartile(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.of(values)..sort();
  return sorted[sorted.length ~/ 4];
}

/// [token] lower-cased without the punctuation around it. Called for every
/// word of the window, so it scans code units instead of matching a
/// pattern.
String _core(String token) {
  var start = 0;
  var end = token.length;
  while (start < end && !_isWordChar(token.codeUnitAt(start))) {
    start++;
  }
  while (end > start && !_isWordChar(token.codeUnitAt(end - 1))) {
    end--;
  }
  final word = start == 0 && end == token.length
      ? token
      : token.substring(start, end);
  return word.toLowerCase();
}

/// [text] reduced to its letters and digits, for comparing titles.
String _squash(String text) => _wordRuns(text).join().toLowerCase();

int _dotCount(String leader) {
  var dots = 0;
  for (var i = 0; i < leader.length; i++) {
    final c = leader.codeUnitAt(i);
    if (c == 0x2E || c == 0xB7) dots++;
    if (c == 0x2026) dots += 3;
  }
  return dots;
}

int _offsetKey(int value, bool roman, int pageIndex) =>
    (value - pageIndex) * 2 + (roman ? 1 : 0);

/// The value of [token] as a page or chapter number: digits or a Roman
/// numeral in one case. Null for anything else.
int? _numberValue(String token) {
  if (token.isEmpty) return null;
  // Most tokens are ordinary words: rule them out before any pattern runs.
  var digits = true;
  var numerals = true;
  for (var i = 0; i < token.length && (digits || numerals); i++) {
    final c = token.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) digits = false;
    if (!_isRomanLetter(c)) numerals = false;
  }
  if (digits) return token.length > 6 ? null : int.parse(token);
  if (!numerals || token.length > 8) return null;
  final lower = token.toLowerCase();
  if (token != lower && token != token.toUpperCase()) return null;
  if (!_roman.hasMatch(lower)) return null;
  var value = 0;
  var prev = 0;
  for (var i = lower.length - 1; i >= 0; i--) {
    final v = _romanDigits[lower[i]]!;
    value += v < prev ? -v : v;
    prev = v;
  }
  // Page and chapter numerals are small; "mix" and "dc" are words.
  return value > 0 && value <= 400 ? value : null;
}

/// i, v, x, l, c, d, m in either case.
bool _isRomanLetter(int c) {
  final lower = c | 0x20;
  return lower == 0x69 ||
      lower == 0x76 ||
      lower == 0x78 ||
      lower == 0x6C ||
      lower == 0x63 ||
      lower == 0x64 ||
      lower == 0x6D;
}

bool _isPageNumber(String token) => _numberValue(token) != null;

bool _endsPageNumber(String text) {
  final space = text.lastIndexOf(' ');
  return space > 0 && _numberValue(text.substring(space + 1)) != null;
}

const Map<String, int> _romanDigits = <String, int>{
  'i': 1,
  'v': 5,
  'x': 10,
  'l': 50,
  'c': 100,
  'd': 500,
  'm': 1000,
};

// ── Patterns ──────────────────────────────────────────────────────────

final RegExp _spaces = RegExp(r'\s+');
final RegExp _digits = RegExp(r'^\d+$');
final RegExp _hasDigit = RegExp(r'\d');
final RegExp _digitRun = RegExp(r'\d+');
final RegExp _roman = RegExp(
  r'^m{0,3}(cm|cd|d?c{0,3})(xc|xl|l?x{0,3})(ix|iv|v?i{0,3})$',
);
final RegExp _lowerLetter = RegExp(r'\p{Ll}', unicode: true);
final RegExp _upperLetter = RegExp(r'\p{Lu}', unicode: true);

/// The first letter or digit of the text, past any opening punctuation.
final RegExp _startsLower = RegExp(r'^[^\p{L}\p{N}]*\p{Ll}', unicode: true);
final RegExp _startsUpper = RegExp(
  r'^[^\p{L}\p{N}]*[\p{Lu}\p{Lt}\p{N}]',
  unicode: true,
);

/// Mirrors the sentence break of `textToSentences`: a stop, then any
/// closing quotes or brackets.
final RegExp _endsSentence = RegExp('[.!?…][”’"\')\\]]*\$');
final RegExp _endsColon = RegExp('[:][—–-]?[”’"\')\\]]*\$');
final RegExp _endsStop = RegExp(r'[.!?,;:—–-]$');
final RegExp _endsSoft = RegExp(r'[,;]$');

/// An em or en dash set tight against a word: "temperament’—".
final RegExp _endsClosedDash = RegExp(r'[^\s—–][—–]$');
final RegExp _startsClosedDash = RegExp(r'^—[^\s—]');
final RegExp _startsClosing = RegExp(r'^[,.;:!?)\]}]');

/// A line of punctuation that finishes the line before it (a closing quote
/// or the second half of a dash that wrapped) rather than standing alone
/// like a row of asterisks.
final RegExp _closesPrevious = RegExp('^(?:[,.;:!?)\\]}’”"…]|—[^\\s—])');
final RegExp _endsOpening = RegExp(r'[(\[{]$');
final RegExp _allCaps = RegExp(r'^[^\p{L}]*\p{Lu}{2,}$', unicode: true);
final RegExp _startsTwoCaps = RegExp(r'^\p{Lu}{2}', unicode: true);

final RegExp _dropCapText = RegExp(
  r'^[“‘"«'
  "'"
  r']?\p{L}{1,2}$',
  unicode: true,
);

/// A run of leader dots: ". . . . .", "....." or "… … …". Runs of fewer
/// than four dots (an ellipsis counts three) are left alone.
final RegExp _leader = RegExp(r'(?:\s*[.·…]){2,}\s*');
final RegExp _tocTail = RegExp(
  r'(?:\s*[.·…]){2,}\s*(\d{1,4}|[ivxlcdm]{1,7}|[IVXLCDM]{1,7})?\s*$',
);

/// A line that is nothing but a page number: "12", "xiv", "Page 12",
/// "– 12 –", "[12]", "12 of 300". Not "1984.": that ends a sentence.
final RegExp _pageNumberOnly = RegExp(
  r'^[\s\-–—\[(|·•]*(?:page|pg\.?|p\.)?\s*(\d{1,5}|[ivxlcdm]{1,7})'
  r'(?:\s*(?:of|/)\s*\d{1,5})?[\s\-–—\])|·•]*$',
  caseSensitive: false,
);

const String _numberWords =
    'one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|'
    'thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty';
const String _divisionWords =
    'chapter|part|book|volume|section|letter|act|scene|canto|stave|appendix';

/// "Chapter 3", "PART II. The Voyage", "Book One": a division word, its
/// number, and an optional title.
final RegExp _numberedHeading = RegExp(
  '^(?:$_divisionWords)\\s+'
  '(\\d{1,3}|[ivxlcdm]{1,7}|$_numberWords|[a-z])\\b'
  '[\\s.:—–-]*(.*)\$',
  caseSensitive: false,
);
final RegExp _numberWord = RegExp('^(?:$_numberWords)\$', caseSensitive: false);

/// A line that begins like a numbered division: one row of a contents list.
final RegExp _chapterPrefix = RegExp(
  '^(?:$_divisionWords)\\s+(?:\\d{1,3}|[ivxlcdm]{1,7}|$_numberWords)\\b',
  caseSensitive: false,
);

final RegExp _namedHeading = RegExp(
  r'^(?:prologue|epilogue|introduction|preface|foreword|afterword|contents|'
  r'table of contents|appendix|appendices|acknowledge?ments?|dedication|'
  r'bibliography|references|index|glossary|notes|conclusions?|abstract|'
  r'postscript|epigraph|interlude|prelude|summary|'
  r'about the authors?|list of (?:figures|tables|illustrations))[.:]?$',
  caseSensitive: false,
);
final RegExp _bareNumeral = RegExp(r'^(\d{1,3}|[IVXLC]{1,7})\.?$');

/// "3.2.1 Scaled Dot-Product Attention": a numbered subsection.
final RegExp _sectionHeading = RegExp(
  r'^(\d{1,2}(?:\.\d{1,2}){1,3})\.?\s+\p{Lu}.*[^.!?,;:]$',
  unicode: true,
);

/// A bullet or an item number at the start of a line.
final RegExp _listMarker = RegExp(
  r'^(?:[•◦▪■●○‣∙*]|\(?\d{1,3}[.)]|\(?[a-zA-Z][.)]|\[\d{1,3}\])\s',
);
