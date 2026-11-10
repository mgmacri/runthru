/// Test fixture: synthetic PDF pages shaped the way pdfium reports them.
///
/// pdfium cannot run under `flutter test`, so layout tests build their pages
/// here. The glyph model is deliberately crude (monospaced advance) but keeps
/// what the analyzer measures: capitals and ascenders reach cap height,
/// x-height letters are lower, descenders hang below the baseline,
/// punctuation is small, generated spaces and line ends have empty boxes, and
/// a word hyphenated inside a page is one raw line with U+0002 in place of
/// the hyphen.
library;

import 'dart:typed_data';

import 'package:runthru/services/pdf_text_layout.dart';

/// pdfium's mark for a word hyphenated at a line end.
const String kStx = '\u0002';

/// Default page: 400 x 600 pt. Top furniture zone is above y = 510, bottom
/// zone below y = 90.
const double kPageWidth = 400;
const double kPageHeight = 600;

/// Default text block.
const double kLeft = 50;
const double kMeasure = 300;
const double kRight = kLeft + kMeasure;
const double kBodySize = 10;
const double kPitch = 12;

/// Advance of one glyph at [size].
double advance(double size) => size * 0.5;

/// Builds one page line by line. Lines are reported in call order, which is
/// the page's text order (pdfium's is the order the file draws in).
class PageBuilder {
  PageBuilder(
    this.pageIndex, {
    this.width = kPageWidth,
    this.height = kPageHeight,
  });

  final int pageIndex;
  final double width;
  final double height;

  final StringBuffer _text = StringBuffer();
  final List<double> _boxes = <double>[];

  /// A line of [text] starting at [x] with its baseline at [y].
  void line(
    String text, {
    required double y,
    double x = kLeft,
    double size = kBodySize,
  }) {
    _run(text, x, y, size);
    _lineEnd(x + text.length * advance(size), y);
  }

  /// A line of [words] set flush left at [x] and, when [justifyTo] is given,
  /// stretched so the last glyph ends at that x.
  void words(
    List<String> words, {
    required double y,
    double x = kLeft,
    double size = kBodySize,
    double? justifyTo,
    bool endLine = true,
  }) {
    final a = advance(size);
    var letters = 0;
    for (final w in words) {
      letters += w.length;
    }
    final gaps = words.length - 1;
    final gap = justifyTo == null || gaps == 0
        ? a
        : (justifyTo - x - letters * a) / gaps;
    assert(
      gap >= 0.5 * a,
      'row too long for its measure: "${words.join(' ')}"',
    );
    var cursor = x;
    for (var i = 0; i < words.length; i++) {
      if (i > 0) {
        _box(0x20, cursor, y, cursor + gap * 0.9, y);
        cursor += gap;
      }
      _run(words[i], cursor, y, size);
      cursor += words[i].length * a;
    }
    if (endLine) _lineEnd(cursor, y);
  }

  /// A word hyphenated by the typesetter inside the page, as pdfium reports
  /// it: [before] on the row at [y], U+0002 where the hyphen was, [after] on
  /// the next row, and no line break between them.
  void broken(
    String before,
    String after, {
    required double y,
    double x = kLeft,
    double? afterX,
    double size = kBodySize,
    double pitch = kPitch,
  }) {
    _run(before, x, y, size);
    hyphenMark(x + before.length * advance(size), y, size);
    line(after, x: afterX ?? x, y: y - pitch, size: size);
  }

  /// The U+0002 pdfium puts where a line-end hyphen was; it carries the
  /// hyphen's box.
  void hyphenMark(double x, double y, double size) {
    _box(0x02, x, y + 0.26 * size, x + 0.45 * size, y + 0.2 * size);
  }

  /// Ends the current raw line (pdfium writes CR LF with empty boxes).
  void endLine(double x, double y) => _lineEnd(x, y);

  /// Glyphs without a line end, for building a raw line piece by piece.
  void run(
    String text, {
    required double x,
    required double y,
    double size = kBodySize,
  }) {
    _run(text, x, y, size);
  }

  /// [text] set vertically, reading upwards from [y], as a margin watermark
  /// is: each glyph box is as wide as the type is tall.
  void vertical(
    String text, {
    required double x,
    required double y,
    double size = kBodySize,
  }) {
    final a = advance(size);
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      final bottom = y + i * a;
      if (c == 0x20) {
        _box(c, x, bottom, x, bottom);
      } else {
        _box(c, x, bottom + 0.9 * a, x + 0.7 * size, bottom);
      }
    }
    _lineEnd(x, y + text.length * a);
  }

  /// Appends raw characters with empty boxes (control characters, a page
  /// with text but no geometry).
  void raw(String text) {
    for (var i = 0; i < text.length; i++) {
      _box(text.codeUnitAt(i), 0, 0, 0, 0);
    }
  }

  PdfRawPage build({bool withBoxes = true}) => PdfRawPage(
    pageIndex: pageIndex,
    width: width,
    height: height,
    text: _text.toString(),
    charBoxes: withBoxes ? Float64List.fromList(_boxes) : Float64List(0),
  );

  void _run(String text, double x, double y, double size) {
    final a = advance(size);
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      final left = x + i * a;
      if (c == 0x20) {
        // A generated space: it has a width but no height.
        _box(c, left, y, left + 0.9 * a, y);
        continue;
      }
      final (bottom, top) = _extent(c, y, size);
      _box(c, left, top, left + 0.9 * a, bottom);
    }
  }

  void _lineEnd(double x, double y) {
    _box(0x0D, x, y, x, y);
    _box(0x0A, x, y, x, y);
  }

  void _box(int unit, double left, double top, double right, double bottom) {
    _text.writeCharCode(unit);
    _boxes
      ..add(left)
      ..add(top)
      ..add(right)
      ..add(bottom);
  }
}

/// Sets [rows] as consecutive body lines from the baseline [y] downwards and
/// returns the baseline below the last one.
///
/// Each row is stretched to [right], as justified text is, unless it ends in
/// `$`: a short last line. A leading `>` indents the row by 12 pt. A trailing
/// `~` breaks the row's last word the way pdfium reports it: no line end,
/// U+0002 for the hyphen, the word's other half on the next row.
double block(
  PageBuilder page,
  List<String> rows, {
  double y = 500,
  double x = kLeft,
  double right = kRight,
  double size = kBodySize,
  double pitch = kPitch,
}) {
  final a = advance(size);
  var baseline = y;
  for (final spec in rows) {
    var row = spec;
    var left = x;
    if (row.startsWith('>')) {
      row = row.substring(1);
      left += 12;
    }
    final short = row.endsWith(r'$');
    final soft = row.endsWith('~');
    if (short || soft) row = row.substring(0, row.length - 1);
    page.words(
      row.split(' '),
      x: left,
      y: baseline,
      size: size,
      justifyTo: short
          ? null
          : soft
          ? right - a
          : right,
      endLine: !soft,
    );
    if (soft) page.hyphenMark(right - a, baseline, size);
    baseline -= pitch;
  }
  return baseline;
}

/// The vertical extent of a glyph on the baseline [y] at [size].
(double bottom, double top) _extent(int c, double y, double size) {
  final ch = String.fromCharCode(c);
  if ('gjpqy'.contains(ch)) return (y - 0.22 * size, y + 0.46 * size);
  if ('acemnorsuvwxz'.contains(ch)) return (y, y + 0.46 * size);
  if (ch == 'i') return (y, y + 0.65 * size);
  if (ch == 't') return (y, y + 0.6 * size);
  if ('.,…'.contains(ch)) return (y, y + 0.1 * size);
  if ('-–—'.contains(ch)) return (y + 0.2 * size, y + 0.26 * size);
  if ('\'"‘’“”*'.contains(ch)) return (y + 0.45 * size, y + 0.7 * size);
  if ('()[]'.contains(ch)) return (y - 0.2 * size, y + 0.8 * size);
  if (ch == 'Q') return (y - 0.18 * size, y + 0.7 * size);
  // Capitals, digits, ascenders and anything else stand cap-height tall.
  return (y, y + 0.7 * size);
}

/// A small typesetter: flows headings and paragraphs down pages of a fixed
/// size, with optional running heads and feet, first-line indents or
/// paragraph spacing, justification and hyphenation.
class Typesetter {
  Typesetter({
    this.measure = kMeasure,
    this.top = 500,
    this.bottom = 110,
    this.size = kBodySize,
    this.pitch = kPitch,
    this.indent = 0,
    this.paragraphGap = 0,
    this.justify = true,
    this.hyphenation = const <String, int>{},
    this.header,
    this.footer,
    this.footerFirst = false,
    this.headerSize,
    this.footerSize,
    this.headerY = 560,
    this.footerY = 40,
    this.leftFor,
    this.firstPageIndex = 0,
  });

  final double measure;

  /// Baseline of the first and of the last possible text line on a page.
  final double top;
  final double bottom;

  final double size;
  final double pitch;

  /// First-line indent of a paragraph.
  final double indent;

  /// Extra space above a paragraph (on top of [pitch]).
  final double paragraphGap;

  final bool justify;

  /// Words that may be hyphenated at a line end: lower-cased word → length
  /// of the part that stays on the line.
  final Map<String, int> hyphenation;

  /// Running head and foot for a page index, or null for none.
  final String? Function(int pageIndex)? header;
  final String? Function(int pageIndex)? footer;

  /// Whether the foot is drawn (and so reported) before the page's text.
  final bool footerFirst;

  final double? headerSize;
  final double? footerSize;
  final double headerY;
  final double footerY;

  /// Left margin for a page index (alternating margins); default [kLeft].
  final double Function(int pageIndex)? leftFor;

  final int firstPageIndex;

  final List<PdfRawPage> _pages = <PdfRawPage>[];
  PageBuilder? _page;
  double _y = 0;
  bool _pageHasText = false;

  /// For each page index, the word its text opens with: whole, even when
  /// only the second half of it is on the page.
  final Map<int, String> firstWordOfPage = <int, String>{};

  void _note(String word) {
    if (!_pageHasText) firstWordOfPage[_index] = word;
  }

  int get _index => firstPageIndex + _pages.length;
  double get _left => leftFor?.call(_index) ?? kLeft;

  PageBuilder _open() {
    final existing = _page;
    if (existing != null) return existing;
    final page = PageBuilder(_index);
    _page = page;
    _y = top;
    _pageHasText = false;
    final head = header?.call(_index);
    final foot = footer?.call(_index);
    if (footerFirst && foot != null) {
      page.line(foot, x: _left, y: footerY, size: footerSize ?? size);
    }
    if (head != null) {
      page.line(head, x: _left, y: headerY, size: headerSize ?? size);
    }
    return page;
  }

  void _close() {
    final page = _page;
    if (page == null) return;
    final foot = footer?.call(_index);
    if (!footerFirst && foot != null) {
      page.line(foot, x: _left, y: footerY, size: footerSize ?? size);
    }
    _pages.add(page.build());
    _page = null;
  }

  /// Ends the current page; the next block starts a new one.
  void pageBreak() => _close();

  /// Adds a page with no text at all (an illustration).
  void blankPage() {
    _close();
    _pages.add(
      PdfRawPage.empty(
        pageIndex: _index,
        width: kPageWidth,
        height: kPageHeight,
      ),
    );
  }

  /// A heading line set [size] large with space around it.
  void heading(String text, {double size = 18, double? spaceAfter}) {
    var page = _open();
    final drop = _pageHasText ? 2.5 * pitch : 0.0;
    if (_y - drop < bottom) {
      _close();
      page = _open();
    } else {
      _y -= drop;
    }
    _note(text.split(' ').first);
    page.line(text, x: _left, y: _y, size: size);
    _pageHasText = true;
    _y -= spaceAfter ?? 2 * pitch;
  }

  /// Leaves [points] of vertical space.
  void space(double points) {
    _open();
    _y -= points;
  }

  /// Hand-placed lines in the flow: [draw] receives the page, the left
  /// margin and the baseline for its first line, and returns the baseline
  /// for whatever follows.
  void custom(
    double Function(PageBuilder page, double left, double y) draw, {
    String? firstWord,
  }) {
    final page = _open();
    if (firstWord != null) _note(firstWord);
    _y = draw(page, _left, _y);
    _pageHasText = true;
  }

  /// A paragraph of running text, wrapped to the measure.
  ///
  /// A word listed in [hyphenation] may be broken at a line end. Inside a
  /// page that is reported as pdfium does (no line end, U+0002 in place of
  /// the hyphen); at the foot of a page the hyphen stays a hyphen.
  void paragraph(String text) {
    final a = advance(size);
    final all = text.split(' ');
    var i = 0;
    var first = true;
    String? carried; // the tail of a word hyphenated on the previous row
    var carriedWhole = '';
    while (i < all.length || carried != null) {
      var page = _open();
      if (first && _pageHasText) _y -= paragraphGap;
      if (_y < bottom) {
        _close();
        page = _open();
      }
      final x = _left + (first ? indent : 0);
      final room = ((_left + measure - x) / a).floor();
      final row = <String>[];
      var used = 0;
      if (carried != null) {
        _note(carriedWhole);
        row.add(carried);
        used = carried.length;
        carried = null;
      } else {
        _note(all[i]);
      }
      String? tail;
      while (i < all.length) {
        final word = all[i];
        final need = (row.isEmpty ? 0 : used + 1) + word.length;
        if (need <= room) {
          row.add(word);
          used = need;
          i++;
          continue;
        }
        final keep = hyphenation[_letters(word)];
        final fits = (row.isEmpty ? 0 : used + 1) + (keep ?? room) + 1 <= room;
        if (keep != null && fits) {
          row.add(word.substring(0, keep));
          used += (row.length == 1 ? 0 : 1) + keep;
          tail = word.substring(keep);
          carriedWhole = word;
          i++;
        }
        break;
      }
      final lastOfParagraph = i >= all.length && tail == null;
      final lastOnPage = _y - pitch < bottom;
      final rowEnd = x + used * a;
      if (tail != null && lastOnPage) {
        // Hyphenated at the foot of the page: a literal hyphen, then the
        // line ends.
        row[row.length - 1] = '${row.last}-';
        page.words(
          row,
          x: x,
          y: _y,
          size: size,
          justifyTo: justify ? _left + measure : null,
        );
      } else if (tail != null) {
        // Hyphenated inside the page: no line end, U+0002 for the hyphen.
        final target = justify ? _left + measure - a : null;
        page.words(
          row,
          x: x,
          y: _y,
          size: size,
          justifyTo: target,
          endLine: false,
        );
        page.hyphenMark(target ?? rowEnd, _y, size);
      } else {
        page.words(
          row,
          x: x,
          y: _y,
          size: size,
          justifyTo: justify && !lastOfParagraph ? _left + measure : null,
        );
      }
      carried = tail;
      _pageHasText = true;
      _y -= pitch;
      first = false;
    }
  }

  /// The pages typeset so far.
  List<PdfRawPage> build() {
    _close();
    return List<PdfRawPage>.of(_pages);
  }
}

String _letters(String word) =>
    word.toLowerCase().replaceAll(RegExp('[^a-z]'), '');

/// A filler sentence generator with a small, fixed vocabulary, so tests can
/// build pages of distinct prose without embedding a book.
class Prose {
  Prose([int seed = 7]) : _state = seed;

  int _state;

  static const List<String> _subjects = <String>[
    'The harbour master',
    'An old surveyor',
    'Her younger brother',
    'The night porter',
    'A travelling printer',
    'The ferry captain',
    'Their quiet neighbour',
    'The station clerk',
  ];
  static const List<String> _verbs = <String>[
    'counted',
    'remembered',
    'carried',
    'watched',
    'followed',
    'described',
    'repaired',
    'measured',
  ];
  static const List<String> _objects = <String>[
    'the lanterns along the river',
    'every letter from the coast',
    'a ladder beside the orchard wall',
    'the last tram of the evening',
    'three maps of the northern road',
    'the bells above the market',
    'a basket of winter apples',
    'the shutters of the corner house',
  ];
  static const List<String> _tails = <String>[
    'before the rain came in',
    'while the town was still asleep',
    'until the lamps were lit',
    'as the tide went out',
    'without saying a word',
    'long after the others had gone',
    'on the morning of the fair',
    'with more care than usual',
  ];

  int _next(int n) {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return (_state >> 8) % n;
  }

  /// One sentence ending in a full stop.
  String sentence() =>
      '${_subjects[_next(8)]} ${_verbs[_next(8)]} ${_objects[_next(8)]} '
      '${_tails[_next(8)]}.';

  /// A paragraph of [sentences] sentences.
  String paragraph(int sentences) =>
      List<String>.generate(sentences, (_) => sentence()).join(' ');
}

/// The words of [result]'s sentences as plain strings, one per sentence.
List<String> sentenceTexts(PdfLayoutResult result) => <String>[
  for (final s in result.sentences) s.words.join(' '),
];

/// The text of every paragraph in [result]: sentences joined until the next
/// one that starts a paragraph. Headings are returned as "# text".
List<String> paragraphTexts(PdfLayoutResult result) {
  final out = <String>[];
  for (final s in result.sentences) {
    final text = s.words.join(' ');
    if (s.isHeading) {
      out.add('${'#' * s.heading} $text');
    } else if (s.startsParagraph || out.isEmpty) {
      out.add(text);
    } else {
      out[out.length - 1] = '${out.last} $text';
    }
  }
  return out;
}
