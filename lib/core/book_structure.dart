/// Book structure: where the real book starts and ends, and its chapters.
///
/// Books open on a cover, a copyright page, a contents list and forewords,
/// and end in notes, indexes and licences. Readers want the chapters.
/// [analyzeBookStructure] turns what the extractors recorded (the source's
/// own navigation, heading levels, paragraph starts) into an ordered list of
/// [BookSection]s, each marked front matter, body or back matter.
///
/// Pure and linear in the number of sentences: safe to run when a book
/// opens. It never touches files, the network or the timer.
library;

import 'package:runthru/services/models.dart';

/// Where a section sits in the book.
enum SectionKind {
  /// Before the first real chapter: cover, title page, copyright, contents,
  /// forewords.
  front,

  /// The book itself.
  body,

  /// After the last chapter: notes, index, about the author, licence.
  back,
}

/// What a section is.
enum SectionRole {
  /// Cover page.
  cover,

  /// Title or half-title page.
  titlePage,

  /// Copyright page, imprint, colophon.
  copyright,

  /// Dedication.
  dedication,

  /// Epigraph.
  epigraph,

  /// Table of contents or a list of figures.
  contents,

  /// Foreword (by someone else).
  foreword,

  /// Preface, editor's or translator's note, attributed introduction.
  preface,

  /// The author's introduction.
  introduction,

  /// Prologue.
  prologue,

  /// A part, book or volume that groups chapters.
  part,

  /// A chapter (or letter, canto, lecture…).
  chapter,

  /// Epilogue.
  epilogue,

  /// Afterword or postscript.
  afterword,

  /// Appendix.
  appendix,

  /// Acknowledgments.
  acknowledgments,

  /// Notes and references.
  notes,

  /// Bibliography or further reading.
  bibliography,

  /// Glossary.
  glossary,

  /// Index.
  bookIndex,

  /// About the author.
  aboutAuthor,

  /// Other books by the author.
  alsoBy,

  /// Distribution boilerplate (Project Gutenberg header and licence).
  license,

  /// A preview of another book, or a reading-group guide.
  extra,

  /// A titled section of no recognised kind (most chapters without a
  /// "Chapter" label).
  other,
}

/// One section of a book: a contiguous run of words.
class BookSection {
  /// Creates a section.
  const BookSection({
    required this.index,
    required this.kind,
    required this.role,
    required this.start,
    required this.end,
    this.label = '',
    this.title = '',
    this.subtitle,
    this.groupTitle,
    this.headingWords = 0,
    this.depth = 0,
  });

  /// Position in [BookStructure.sections].
  final int index;

  /// Front matter, body or back matter.
  final SectionKind kind;

  /// What the section is.
  final SectionRole role;

  /// First word of the section (its heading, when it has one).
  final int start;

  /// One past the last word of the section.
  final int end;

  /// The numbering part of the heading ("Chapter 3", "Part II", "7"), or
  /// empty when the heading has none.
  final String label;

  /// The name of the section ("The Ledger"). Empty when the section has
  /// only a [label], or no heading at all.
  final String title;

  /// A second heading line under the title, if any.
  final String? subtitle;

  /// The part this section opens ("Part Two"), when a part heading stands
  /// directly above it.
  final String? groupTitle;

  /// How many words at [start] are the heading itself. The reader shows
  /// them as a title card instead of flashing them one by one.
  final int headingWords;

  /// Nesting depth (0 = top level, 1 = a chapter inside a part).
  final int depth;

  /// First word after the heading.
  int get textStart => (start + headingWords).clamp(start, end);

  /// Words of running text (heading excluded).
  int get wordCount => end - textStart;

  /// Whether the section has a heading of its own.
  bool get isTitled => label.isNotEmpty || title.isNotEmpty;

  /// One line naming the section: "Chapter 3: The Ledger", "The Ledger",
  /// "Chapter 3", or [fallback] for an untitled section.
  String displayName({String fallback = ''}) {
    if (label.isNotEmpty && title.isNotEmpty) return '$label: $title';
    if (title.isNotEmpty) return title;
    if (label.isNotEmpty) return label;
    return fallback;
  }

  /// The largest line of the heading: the title, or the label when the
  /// heading is only "Chapter 3".
  String get headline => title.isNotEmpty ? title : label;

  /// The small line above [headline]: the label when there is also a
  /// title, otherwise empty.
  String get overline => title.isNotEmpty ? label : '';

  BookSection _copy({
    int? index,
    SectionKind? kind,
    int? start,
    int? end,
    int? headingWords,
    String? groupTitle,
  }) {
    return BookSection(
      index: index ?? this.index,
      kind: kind ?? this.kind,
      role: role,
      start: start ?? this.start,
      end: end ?? this.end,
      label: label,
      title: title,
      subtitle: subtitle,
      groupTitle: groupTitle ?? this.groupTitle,
      headingWords: headingWords ?? this.headingWords,
      depth: depth,
    );
  }
}

/// A heading inside a section (a sub-section of a chapter).
class SubHeading {
  /// Creates a sub-heading.
  const SubHeading({
    required this.start,
    required this.wordCount,
    required this.text,
  });

  /// First word of the heading.
  final int start;

  /// Words in the heading.
  final int wordCount;

  /// The heading text.
  final String text;
}

/// The sections of one document.
class BookStructure {
  /// Creates a structure. [sections] must be contiguous and cover
  /// `0..totalWords`.
  BookStructure({
    required this.sections,
    required this.totalWords,
    this.subHeadings = const [],
  });

  /// A document with no detectable structure: one untitled body section.
  factory BookStructure.flat(int totalWords) {
    return BookStructure(
      totalWords: totalWords,
      sections: [
        BookSection(
          index: 0,
          kind: SectionKind.body,
          role: SectionRole.other,
          start: 0,
          end: totalWords,
        ),
      ],
    );
  }

  /// Sections in reading order, covering every word exactly once.
  final List<BookSection> sections;

  /// Headings inside sections, in reading order.
  final List<SubHeading> subHeadings;

  /// Words in the document.
  final int totalWords;

  late final List<BookSection> _body = [
    for (final s in sections)
      if (s.kind == SectionKind.body) s,
  ];

  /// The body's sections (chapters), in order.
  List<BookSection> get chapters => _body;

  /// Whether the document has chapters worth announcing: at least two
  /// titled body sections.
  late final bool hasChapters = _body.where((s) => s.isTitled).length >= 2;

  /// First word of the body (0 when there is no front matter).
  late final int bodyStart = _body.isEmpty ? 0 : _body.first.start;

  /// One past the last word of the body.
  late final int bodyEnd = _body.isEmpty ? totalWords : _body.last.end;

  /// Whether anything precedes the body.
  bool get hasFrontMatter => bodyStart > 0;

  /// Whether anything follows the body.
  bool get hasBackMatter => bodyEnd < totalWords;

  /// The section containing word [index] (clamped into the document).
  BookSection sectionAt(int index) {
    var lo = 0;
    var hi = sections.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (sections[mid].start <= index) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return sections[lo];
  }

  /// The section after [section], or null at the end.
  BookSection? next(BookSection section) =>
      section.index + 1 < sections.length ? sections[section.index + 1] : null;

  /// 1-based position of [section] among the body's sections, or 0 when it
  /// is not a body section.
  int chapterNumber(BookSection section) {
    final i = _body.indexWhere((s) => s.index == section.index);
    return i + 1;
  }

  /// The sub-heading that starts exactly at word [index], or null.
  SubHeading? subHeadingAt(int index) {
    var lo = 0;
    var hi = subHeadings.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final start = subHeadings[mid].start;
      if (start == index) return subHeadings[mid];
      if (start < index) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return null;
  }

  /// Titles of the front-matter sections a new reader skips, for the
  /// "skipped" note ("Foreword", "Preface"). Untitled ones are left out.
  List<String> get skippedFrontTitles => [
    for (final s in sections)
      if (s.kind == SectionKind.front && s.isTitled) s.displayName(),
  ];
}

// ── Analysis ────────────────────────────────────────────────────────────

/// Detects the sections of [doc].
///
/// Evidence, strongest first:
/// 1. The source's own navigation ([ExtractedDocument.outline]): EPUB
///    contents and landmarks (`bodymatter`, `backmatter`, per-file
///    `epub:type`), PDF bookmarks.
/// 2. Heading lines ([Sentence.heading]) and their levels.
/// 3. Heading patterns in plain paragraphs ("Chapter 7", "PROLOGUE"), for
///    text with no markup, accepted only when they are not a contents list.
/// 4. Boilerplate markers that hold whatever the markup says: the Project
///    Gutenberg "*** START OF…" and "*** END OF…" lines, a closing
///    "THE END".
///
/// A new reader starts at [BookStructure.bodyStart]: the publisher's stated
/// start of the text when there is one, otherwise the first numbered
/// chapter (with a prologue or the author's introduction directly before
/// it), otherwise the first section after the last front-matter page.
BookStructure analyzeBookStructure(ExtractedDocument doc) {
  final sentences = doc.sentences;
  if (sentences.isEmpty) return BookStructure.flat(0);

  // Word offset of each sentence.
  final starts = List<int>.filled(sentences.length + 1, 0);
  for (var i = 0; i < sentences.length; i++) {
    starts[i + 1] = starts[i] + sentences[i].words.length;
  }
  final total = starts.last;
  if (total == 0) return BookStructure.flat(0);

  int sentenceAt(int word) {
    var lo = 0;
    var hi = sentences.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (starts[mid] <= word) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  // ── 1. Candidate section starts ──
  final titled = [
    for (final e in doc.outline)
      if (e.title.trim().isNotEmpty &&
          e.startWordIndex >= 0 &&
          e.startWordIndex < total)
        e,
  ];
  final hasFlaggedHeadings = sentences.any((s) => s.isHeading);

  final nodes = <_Node>[];
  if (titled.length >= 2) {
    for (final e in titled) {
      nodes.add(
        _Node(
          sentence: sentenceAt(e.startWordIndex),
          word: e.startWordIndex,
          depth: e.depth,
          title: e.title.trim(),
          types: _tokens(e.type),
        )..fromOutline = true,
      );
    }
  } else {
    nodes.addAll(
      _headingNodes(sentences, starts, usePatterns: !hasFlaggedHeadings),
    );
  }
  nodes.sort((a, b) {
    final byWord = a.word.compareTo(b.word);
    return byWord != 0 ? byWord : a.depth.compareTo(b.depth);
  });
  // Two entries at one word: keep the first (the shallower one).
  for (var i = nodes.length - 1; i > 0; i--) {
    if (nodes[i].word == nodes[i - 1].word) {
      nodes[i - 1].types.addAll(nodes[i].types);
      nodes.removeAt(i);
    }
  }

  // ── 2. Heading blocks: the heading lines standing at each start ──
  final nodeAtSentence = <int, _Node>{for (final n in nodes) n.sentence: n};
  for (final node in nodes) {
    final preset = node.presetHeadingWords;
    if (preset != null) {
      node.headingWords = preset;
      continue;
    }
    var s = node.sentence;
    var words = 0;
    while (s < sentences.length &&
        sentences[s].isHeading &&
        node.lines.length < _maxHeadingLines &&
        words + sentences[s].words.length <= _maxHeadingWords &&
        (s == node.sentence || !nodeAtSentence.containsKey(s))) {
      node.lines.add(sentences[s].words.join(' '));
      words += sentences[s].words.length;
      s++;
    }
    if (node.lines.isEmpty) {
      // No heading element: the title may still open the text as a plain
      // paragraph ("Chapter One" in a <p>).
      words = _titleWordsAt(sentences, node.sentence, node.title);
    }
    node.headingWords = words;
  }

  // ── 3. Tree shape: own text, children, containers, subtitles ──
  final ancestors = <_Node>[];
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    final nextWord = i + 1 < nodes.length ? nodes[i + 1].word : total;
    node.ownWords = (nextWord - node.word - node.headingWords).clamp(0, total);
    while (ancestors.isNotEmpty && ancestors.last.depth >= node.depth) {
      ancestors.removeLast();
    }
    if (ancestors.isNotEmpty) {
      node.parent = ancestors.last;
      ancestors.last.children.add(node);
    }
    ancestors.add(node);
  }
  // A lone child standing right under its parent's heading is a subtitle
  // ("ETYMOLOGY." / "(Supplied by a Late Consumptive Usher…)").
  for (final node in List<_Node>.of(nodes)) {
    final parent = node.parent;
    if (parent == null) continue;
    if (parent.children.length == 1 &&
        parent.ownWords == 0 &&
        node.children.isEmpty &&
        !_strongHeading.hasMatch(node.title)) {
      parent
        ..subtitle = node.title
        ..headingWords += node.headingWords
        ..ownWords = node.ownWords
        ..children.clear();
      nodes.remove(node);
    }
  }

  final depthCounts = <int, int>{};
  for (final n in nodes) {
    depthCounts[n.depth] = (depthCounts[n.depth] ?? 0) + 1;
  }
  final depths = depthCounts.keys.toList()..sort();
  final majorDepth = depths.isEmpty
      ? 0
      : depths.firstWhere(
          (d) => depthCounts[d]! >= 2,
          orElse: () => depths.first,
        );
  bool isContainer(_Node n) =>
      n.children.length >= 2 && n.ownWords < _containerMaxWords;
  bool isSection(_Node n) {
    if (n.depth <= majorDepth) return true;
    final parent = n.parent;
    return parent != null && isSection(parent) && isContainer(parent);
  }

  final sectionNodes = <_Node>[];
  final subHeadings = <SubHeading>[];
  for (final n in nodes) {
    if (isSection(n)) {
      sectionNodes.add(n);
    } else if (n.headingWords > 0) {
      subHeadings.add(
        SubHeading(start: n.word, wordCount: n.headingWords, text: n.title),
      );
    }
  }
  // Heading lines that start no section are sub-headings too.
  if (titled.length >= 2 && hasFlaggedHeadings) {
    final covered = <int>{};
    for (final n in nodes) {
      var s = n.sentence;
      var left = n.headingWords;
      while (left > 0 && s < sentences.length) {
        covered.add(s);
        left -= sentences[s].words.length;
        s++;
      }
    }
    for (var s = 0; s < sentences.length; s++) {
      if (!sentences[s].isHeading || covered.contains(s)) continue;
      subHeadings.add(
        SubHeading(
          start: starts[s],
          wordCount: sentences[s].words.length,
          text: sentences[s].words.join(' '),
        ),
      );
    }
  }
  subHeadings.sort((a, b) => a.start.compareTo(b.start));

  // A heading in the tail that names back matter ("References", "Index")
  // starts a section even when the navigation does not list it.
  final lastStart = sectionNodes.isEmpty ? 0 : sectionNodes.last.word;
  for (final sub in List<SubHeading>.of(subHeadings)) {
    if (sub.start <= lastStart || sub.start < total * 0.6) continue;
    final role = _roleFromTitle(sub.text);
    if (!_backRoles.contains(role) && !_eitherEndRoles.contains(role)) {
      continue;
    }
    subHeadings.remove(sub);
    sectionNodes.add(
      _Node(
          sentence: sentenceAt(sub.start),
          word: sub.start,
          depth: majorDepth,
          title: sub.text,
        )
        ..headingWords = sub.wordCount
        ..lines.add(sub.text)
        ..role = role,
    );
  }

  // A contents list read as headings: many chapter-like "sections" with
  // almost no text between them. Collapse the run into one contents page.
  _collapseContentsRuns(sectionNodes, total);

  // ── 4. Roles ──
  for (final n in sectionNodes) {
    n.role ??= _roleFromTypes(n.types) ?? _roleFromTitle(n.title);
  }

  // ── 5. Boundaries the text itself states ──
  var frontLimit = 0; // everything before this word is front matter
  var backLimit = total; // everything from this word on is back matter
  var explicitBody = -1;
  var explicitBack = -1;
  for (final e in doc.outline) {
    final types = _tokens(e.type);
    final word = e.startWordIndex.clamp(0, total);
    if (types.contains('bodymatter') && explicitBody < 0) explicitBody = word;
    if (types.contains('pg-footer') && word > 0 && word < backLimit) {
      backLimit = word;
    }
  }
  for (final e in doc.outline) {
    final types = _tokens(e.type);
    final word = e.startWordIndex.clamp(0, total);
    if (types.contains('backmatter') &&
        word > (explicitBody < 0 ? 0 : explicitBody) &&
        (explicitBack < 0 || word < explicitBack)) {
      explicitBack = word;
    }
  }
  // Project Gutenberg's own markers, whatever the container says.
  final scanHead = sentences.length < _markerScan
      ? sentences.length
      : _markerScan;
  for (var s = 0; s < scanHead; s++) {
    if (_pgStart.hasMatch(_joined(sentences[s], 14))) {
      frontLimit = starts[s + 1];
      break;
    }
  }
  for (
    var s = sentences.length - 1;
    s >= 0 && s >= sentences.length - _markerScan;
    s--
  ) {
    if (_pgEnd.hasMatch(_joined(sentences[s], 14))) {
      if (starts[s] > frontLimit && starts[s] < backLimit) {
        backLimit = starts[s];
      }
      break;
    }
  }
  // A closing "THE END" ends the story; what follows it is back matter.
  final tailFrom = sentenceAt((total * 0.6).floor());
  for (var s = sentences.length - 1; s > tailFrom; s--) {
    final sentence = sentences[s];
    if (sentence.words.length > 3 ||
        !(sentence.startsParagraph || sentence.isHeading)) {
      continue;
    }
    if (_theEnd.hasMatch(sentence.words.join(' '))) {
      if (starts[s + 1] < backLimit && starts[s + 1] > frontLimit) {
        backLimit = starts[s + 1];
      }
      break;
    }
  }

  // ── 6. Body range ──
  var bodyStart = frontLimit;
  if (explicitBody >= 0 && explicitBody < backLimit) {
    bodyStart = explicitBody > frontLimit ? explicitBody : frontLimit;
  } else {
    final first = _firstBodyNode(sectionNodes, frontLimit, total);
    if (first != null && first.word > frontLimit) {
      bodyStart = first.word;
      // Long unheaded prose right before the first chapter, with nothing
      // that marks it as front matter, is the book's opening (a prologue
      // whose heading was not detected), not something to skip.
      final isFirstNode = identical(first, sectionNodes.first);
      if (isFirstNode &&
          first.word - frontLimit >= _unheadedOpeningWords &&
          !_looksLikeFrontMatter(sentences, starts, frontLimit, first.word)) {
        bodyStart = frontLimit;
      }
    }
  }

  var bodyEnd = backLimit;
  if (explicitBack > bodyStart && explicitBack < bodyEnd) {
    bodyEnd = explicitBack;
  }
  // Trailing sections that are plainly back matter.
  for (var i = sectionNodes.length - 1; i >= 0; i--) {
    final n = sectionNodes[i];
    if (n.word <= bodyStart) break;
    if (n.word >= bodyEnd) continue;
    final role = n.role!;
    final isBack =
        _backRoles.contains(role) ||
        (_eitherEndRoles.contains(role) && n.word > total * 0.5);
    if (!isBack) break;
    bodyEnd = n.word;
  }
  if (bodyEnd <= bodyStart) {
    bodyStart = frontLimit;
    bodyEnd = backLimit > bodyStart ? backLimit : total;
  }

  // ── 7. Sections ──
  final cuts = <int>{0, bodyStart, bodyEnd, total};
  for (final n in sectionNodes) {
    cuts.add(n.word);
  }
  final ordered = cuts.where((c) => c >= 0 && c <= total).toList()..sort();
  final nodeAtWord = <int, _Node>{for (final n in sectionNodes) n.word: n};

  final sections = <BookSection>[];
  for (var i = 0; i + 1 < ordered.length; i++) {
    final start = ordered[i];
    final end = ordered[i + 1];
    if (end <= start) continue;
    final kind = start < bodyStart
        ? SectionKind.front
        : start >= bodyEnd
        ? SectionKind.back
        : SectionKind.body;
    final node = nodeAtWord[start];
    if (node == null) {
      sections.add(
        BookSection(
          index: sections.length,
          kind: kind,
          role: SectionRole.other,
          start: start,
          end: end,
        ),
      );
      continue;
    }
    final heading = _parseHeading(node);
    sections.add(
      BookSection(
        index: sections.length,
        kind: kind,
        role: node.role!,
        start: start,
        end: end,
        label: heading.label,
        title: heading.title,
        subtitle: heading.subtitle,
        headingWords: node.headingWords.clamp(0, end - start),
        depth: (node.depth - majorDepth).clamp(0, 3),
      ),
    );
  }

  // A part heading with nothing under it but its first chapter belongs to
  // that chapter: one title card, "Part Two" above "Chapter 12".
  final merged = <BookSection>[];
  for (var i = 0; i < sections.length; i++) {
    final section = sections[i];
    final next = i + 1 < sections.length ? sections[i + 1] : null;
    if (next != null &&
        section.isTitled &&
        section.wordCount == 0 &&
        section.kind == next.kind &&
        next.isTitled &&
        next.depth > section.depth) {
      merged.add(
        next._copy(
          start: section.start,
          headingWords: section.headingWords + next.headingWords,
          groupTitle: section.displayName(),
        ),
      );
      i++;
      continue;
    }
    merged.add(section);
  }
  final result = [
    for (var i = 0; i < merged.length; i++) merged[i]._copy(index: i),
  ];

  if (result.isEmpty) return BookStructure.flat(total);
  return BookStructure(
    sections: result,
    totalWords: total,
    subHeadings: subHeadings,
  );
}

// ── Internals ───────────────────────────────────────────────────────────

const int _maxHeadingLines = 4;
const int _maxHeadingWords = 40;
const int _containerMaxWords = 60;
const int _markerScan = 400;

class _Node {
  _Node({
    required this.sentence,
    required this.word,
    required this.depth,
    required this.title,
    Set<String>? types,
  }) : types = types ?? <String>{};

  final int sentence;
  final int word;
  final int depth;

  /// The navigation title, or the heading lines joined.
  String title;
  final Set<String> types;

  /// Whether the node comes from the source's navigation (its [title] is
  /// the publisher's wording) rather than from heading lines in the text.
  bool fromOutline = false;

  /// Heading words already known (pattern headings carry no flag to scan).
  int? presetHeadingWords;

  /// Heading lines standing at the start.
  final List<String> lines = [];
  int headingWords = 0;
  int ownWords = 0;
  String? subtitle;
  _Node? parent;
  final List<_Node> children = [];
  SectionRole? role;
}

Set<String> _tokens(String? type) => type == null || type.isEmpty
    ? <String>{}
    : type.split(' ').where((t) => t.isNotEmpty).toSet();

String _joined(Sentence s, int maxWords) => s.words.take(maxWords).join(' ');

/// Section starts from heading lines.
///
/// A run of consecutive heading lines is one start (label, title,
/// subtitle). With [usePatterns], short paragraphs that read as headings
/// ("Chapter 7", "PROLOGUE") count as well: text with no markup.
List<_Node> _headingNodes(
  List<Sentence> sentences,
  List<int> starts, {
  required bool usePatterns,
}) {
  // Level of each heading line (0 = not a heading).
  final levels = List<int>.filled(sentences.length, 0);
  for (var i = 0; i < sentences.length; i++) {
    final s = sentences[i];
    if (s.isHeading) {
      levels[i] = s.heading;
    } else if (usePatterns &&
        s.startsParagraph &&
        s.words.length <= 12 &&
        _isStandalone(sentences, i)) {
      final text = s.words.join(' ');
      if (_strongHeading.hasMatch(text) || _roleWordHeading.hasMatch(text)) {
        levels[i] = 2;
      }
    }
  }
  final present = levels.where((l) => l > 0).toSet().toList()..sort();
  if (present.isEmpty) return const [];
  final rank = {for (var i = 0; i < present.length; i++) present[i]: i};

  final nodes = <_Node>[];
  var i = 0;
  while (i < sentences.length) {
    if (levels[i] == 0) {
      i++;
      continue;
    }
    // A run of consecutive heading lines is one heading.
    var end = i + 1;
    var best = levels[i];
    while (end < sentences.length &&
        levels[end] > 0 &&
        end - i < _maxHeadingLines) {
      // A heading that names a section of its own always starts one:
      // "Part One" then "Chapter 1", a title then "Introduction",
      // "Contents" then its first row. Anything else is a further line of
      // the same heading ("Chapter One" / "The Arrival").
      final line = sentences[end].words.join(' ');
      if (_strongHeading.hasMatch(line) ||
          _roleFromTitle(line) != SectionRole.other) {
        break;
      }
      if (levels[end] < best) best = levels[end];
      end++;
    }
    final node = _Node(
      sentence: i,
      word: starts[i],
      depth: rank[best]!,
      title: [
        for (var k = i; k < end; k++) sentences[k].words.join(' '),
      ].join(' '),
    );
    if (!sentences[i].isHeading) {
      // Pattern headings carry no flag: record the lines here.
      for (var k = i; k < end; k++) {
        node.lines.add(sentences[k].words.join(' '));
      }
      node.presetHeadingWords = starts[end] - starts[i];
    }
    nodes.add(node);
    i = end;
  }
  return nodes;
}

/// Whether sentence [i] is a paragraph of its own (the next sentence
/// starts a new paragraph, or the text ends).
bool _isStandalone(List<Sentence> sentences, int i) {
  if (i + 1 >= sentences.length) return true;
  return sentences[i + 1].startsParagraph || sentences[i + 1].isHeading;
}

/// When a section has no heading element, how many of its first words
/// repeat its navigation [title] (so they are the heading, not text).
int _titleWordsAt(List<Sentence> sentences, int sentence, String title) {
  final want = _normaliseWords(title);
  if (want.isEmpty || sentence >= sentences.length) return 0;
  final have = <String>[];
  var count = 0;
  for (var s = sentence; s < sentences.length && s < sentence + 3; s++) {
    if (s > sentence && !sentences[s].startsParagraph) break;
    for (final w in sentences[s].words) {
      final n = _normaliseWord(w);
      count++;
      if (n.isEmpty) continue;
      have.add(n);
      if (have.length > want.length) return 0;
      if (have.last != want[have.length - 1]) return 0;
      if (have.length == want.length) return count;
    }
  }
  return 0;
}

List<String> _normaliseWords(String text) => [
  for (final w in text.split(RegExp(r'\s+')))
    if (_normaliseWord(w).isNotEmpty) _normaliseWord(w),
];

String _normaliseWord(String word) =>
    word.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// Collapses a run of chapter-like starts with almost no text between them
/// (a contents list whose rows were read as headings) into one contents
/// section starting at the first row.
void _collapseContentsRuns(List<_Node> nodes, int total) {
  var i = 0;
  while (i < nodes.length) {
    var j = i;
    while (j + 1 < nodes.length &&
        nodes[j + 1].word - nodes[j].word - nodes[j].headingWords <
            _contentsRowMaxWords &&
        _strongHeading.hasMatch(nodes[j].title) &&
        _strongHeading.hasMatch(nodes[j + 1].title)) {
      j++;
    }
    final run = j - i + 1;
    if (run >= 4) {
      // Keep the last row only if real text follows it (then it is the
      // first chapter, not a contents row).
      final last = nodes[j];
      final nextWord = j + 1 < nodes.length ? nodes[j + 1].word : total;
      final lastIsReal =
          nextWord - last.word - last.headingWords >= _contentsRowMaxWords;
      final removeTo = lastIsReal ? j : j + 1;
      final first = nodes[i];
      first
        ..title = 'Contents'
        ..role = SectionRole.contents
        ..headingWords = 0
        ..lines.clear();
      nodes.removeRange(i + 1, removeTo);
    }
    i++;
  }
}

const int _contentsRowMaxWords = 12;

/// The first section of the real book.
///
/// With numbered chapters: the first of them, or the prologue / author's
/// introduction standing directly before it. Without: the first section
/// after the last front-matter page that has real text.
_Node? _firstBodyNode(List<_Node> nodes, int frontLimit, int total) {
  final candidates = [
    for (final n in nodes)
      if (n.word >= frontLimit) n,
  ];
  if (candidates.isEmpty) return null;

  final firstNumbered = candidates.indexWhere(
    (n) => n.role == SectionRole.chapter || n.role == SectionRole.part,
  );
  if (firstNumbered >= 0) {
    var start = firstNumbered;
    while (start > 0 &&
        (candidates[start - 1].role == SectionRole.prologue ||
            candidates[start - 1].role == SectionRole.introduction)) {
      start--;
    }
    return candidates[start];
  }

  // No numbered chapters: skip the leading front-matter pages. A document
  // with none (an article and its sections) starts at its first word.
  var lastFront = -1;
  for (var i = 0; i < candidates.length; i++) {
    if (candidates[i].word > total * 0.35) break;
    if (_frontRoles.contains(candidates[i].role) ||
        _eitherEndRoles.contains(candidates[i].role)) {
      lastFront = i;
    }
  }
  if (lastFront < 0) return null;
  for (var i = lastFront + 1; i < candidates.length; i++) {
    final n = candidates[i];
    if (_backRoles.contains(n.role)) continue;
    if (n.role != SectionRole.other || n.ownWords >= _realTextWords) return n;
  }
  return null;
}

const int _realTextWords = 120;

const int _unheadedOpeningWords = 1500;

/// Whether words [from]..[to] carry the marks of front matter: a copyright
/// notice, an ISBN, a contents list.
bool _looksLikeFrontMatter(
  List<Sentence> sentences,
  List<int> starts,
  int from,
  int to,
) {
  var hits = 0;
  for (var s = 0; s < sentences.length && starts[s] < to; s++) {
    if (starts[s] < from) continue;
    if (_frontMatterSigns.hasMatch(_joined(sentences[s], 30))) hits++;
    if (hits >= 2) return true;
  }
  return false;
}

const Set<SectionRole> _frontRoles = {
  SectionRole.cover,
  SectionRole.titlePage,
  SectionRole.copyright,
  SectionRole.dedication,
  SectionRole.epigraph,
  SectionRole.contents,
  SectionRole.foreword,
  SectionRole.preface,
};

const Set<SectionRole> _backRoles = {
  SectionRole.afterword,
  SectionRole.appendix,
  SectionRole.notes,
  SectionRole.bibliography,
  SectionRole.glossary,
  SectionRole.bookIndex,
  SectionRole.extra,
};

/// Front matter at the front, back matter at the back.
const Set<SectionRole> _eitherEndRoles = {
  SectionRole.acknowledgments,
  SectionRole.aboutAuthor,
  SectionRole.alsoBy,
  SectionRole.copyright,
  SectionRole.license,
};

SectionRole? _roleFromTypes(Set<String> types) {
  for (final entry in _typeRoles.entries) {
    if (types.contains(entry.key)) return entry.value;
  }
  return null;
}

/// Most specific first: a file typed `frontmatter introduction` is an
/// introduction.
const Map<String, SectionRole> _typeRoles = {
  'pg-header': SectionRole.license,
  'pg-footer': SectionRole.license,
  'cover': SectionRole.cover,
  'titlepage': SectionRole.titlePage,
  'halftitlepage': SectionRole.titlePage,
  'copyright-page': SectionRole.copyright,
  'imprint': SectionRole.copyright,
  'colophon': SectionRole.copyright,
  'contributors': SectionRole.copyright,
  'other-credits': SectionRole.copyright,
  'dedication': SectionRole.dedication,
  'epigraph': SectionRole.epigraph,
  'toc': SectionRole.contents,
  'loi': SectionRole.contents,
  'lot': SectionRole.contents,
  'foreword': SectionRole.foreword,
  'preface': SectionRole.preface,
  'introduction': SectionRole.introduction,
  'prologue': SectionRole.prologue,
  'preamble': SectionRole.prologue,
  'part': SectionRole.part,
  'volume': SectionRole.part,
  'chapter': SectionRole.chapter,
  'division': SectionRole.chapter,
  'conclusion': SectionRole.chapter,
  'epilogue': SectionRole.epilogue,
  'afterword': SectionRole.afterword,
  'appendix': SectionRole.appendix,
  'acknowledgments': SectionRole.acknowledgments,
  'endnotes': SectionRole.notes,
  'bibliography': SectionRole.bibliography,
  'glossary': SectionRole.glossary,
  'index': SectionRole.bookIndex,
  'about-author': SectionRole.aboutAuthor,
  'also-by': SectionRole.alsoBy,
};

SectionRole _roleFromTitle(String title) {
  final t = title
      .toLowerCase()
      .replaceAll(RegExp(r'[‘’]'), "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s*•·\-–—]+|[\s.:*•·\-–—]+$'), '');
  for (final rule in _titleRoles) {
    if (rule.$1.hasMatch(t)) return rule.$2;
  }
  return SectionRole.other;
}

const String _num =
    r'(?:\d+|[ivxlcdm]+|one|two|three|four|five|six|seven|eight|nine|ten'
    r'|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen'
    r'|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety'
    r'|hundred|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth'
    r'|tenth|the first|the second|the third|the fourth|the fifth|the last)';

/// Title patterns, first match wins. Titles are lower-cased and trimmed of
/// surrounding punctuation before matching.
final List<(RegExp, SectionRole)> _titleRoles = [
  (
    RegExp(r'project gutenberg.*licen[cs]e|^(start|end) of (the|this) project'),
    SectionRole.license,
  ),
  (RegExp(r'^(front )?cover( page| image)?$'), SectionRole.cover),
  (
    RegExp(r'^(title ?page|half[- ]?title( ?page)?|frontispiece)$'),
    SectionRole.titlePage,
  ),
  (
    RegExp(
      r"^(copyright( page| notice| information)?|imprint|colophon"
      r"|uncopyright|legal notice|credits|publisher's note|edition notice"
      r"|a note on the type|about the publisher)$",
    ),
    SectionRole.copyright,
  ),
  (RegExp(r'^dedication$'), SectionRole.dedication),
  (RegExp(r'^epigraph$'), SectionRole.epigraph),
  (
    RegExp(
      r'^((table of )?contents|toc|brief contents|detailed contents'
      r'|(list of )?(figures|tables|illustrations|plates|maps|abbreviations))$',
    ),
    SectionRole.contents,
  ),
  (RegExp(r'^foreword\b'), SectionRole.foreword),
  (
    RegExp(
      r"^(preface\b|prefatory note|author's note|a note (on|about|to|from) "
      r"|note (on|to) the |note to the reader|(translator|editor)'s? "
      r"(note|preface|introduction|foreword)|introduction (by|to the) "
      r"|praise for |advance praise|about this (book|edition)"
      r"|how to (use|read) this book|a word (from|about) )",
    ),
    SectionRole.preface,
  ),
  (RegExp(r'^introduction\b'), SectionRole.introduction),
  (
    RegExp(r'^(prologue|prelude|preamble|overture|proem)\b'),
    SectionRole.prologue,
  ),
  (RegExp('^(part|book|volume|act) $_num(\\b|\$)'), SectionRole.part),
  (
    RegExp(
      '^(chapter|chap\\.?|letter|canto|stave|scene|lecture|lesson|day'
      '|night|episode|section|story|tale) $_num(\\b|\$)',
    ),
    SectionRole.chapter,
  ),
  (RegExp(r'^(\d{1,3}|[ivxlcdm]{1,7})([.):]| |$)'), SectionRole.chapter),
  (RegExp(r'^(epilogue|postlude|coda|envoi)\b'), SectionRole.epilogue),
  (RegExp(r'^(afterword|postscript|post-script)\b'), SectionRole.afterword),
  (RegExp(r'^appendi(x|ces)\b'), SectionRole.appendix),
  (RegExp(r'^acknowledge?ments?$'), SectionRole.acknowledgments),
  (
    RegExp(
      r'^(notes|endnotes|footnotes|references|works cited|sources'
      r'|citations|notes and references|chapter notes)$',
    ),
    SectionRole.notes,
  ),
  (
    RegExp(
      r'^((selected |select )?bibliography|further reading'
      r'|(suggested|recommended) reading|reading list)$',
    ),
    SectionRole.bibliography,
  ),
  (RegExp(r'^glossary\b'), SectionRole.glossary),
  (RegExp(r'^(general |subject |name )?index$'), SectionRole.bookIndex),
  (
    RegExp(r'^about the (author|authors|translator|illustrator|editor)s?$'),
    SectionRole.aboutAuthor,
  ),
  (
    RegExp(
      r'^(also by|other books by|books by|by the same author|more from)\b',
    ),
    SectionRole.alsoBy,
  ),
  (
    RegExp(
      r'^(excerpt|preview|sneak peek|bonus chapter|an excerpt from'
      r'|read on for|reading group|discussion questions'
      r'|questions for discussion|book club)\b',
    ),
    SectionRole.extra,
  ),
];

/// "Chapter 7", "Part Two", "BOOK III", "7." — a numbered heading.
final RegExp _strongHeading = RegExp(
  '^\\W*(?:(?:chapter|chap\\.?|part|book|volume|letter|canto|stave|act'
  '|scene|lecture|lesson) $_num\\b'
  r'|(?:\d{1,3}|[IVXLCDM]{1,7})[.)]?$)',
  caseSensitive: false,
);

/// A whole paragraph that is one structural word: "PROLOGUE", "Contents".
final RegExp _roleWordHeading = RegExp(
  r'^\W*(prologue|epilogue|introduction|preface|foreword|afterword'
  r'|contents|table of contents|acknowledge?ments|dedication|appendix'
  r'|bibliography|glossary|index|notes|about the author)\W*$',
  caseSensitive: false,
);

final RegExp _pgStart = RegExp(
  r'\*{3}\s*START OF (THE|THIS) PROJECT GUTENBERG',
  caseSensitive: false,
);
final RegExp _pgEnd = RegExp(
  r'\*{3}\s*END OF (THE|THIS) PROJECT GUTENBERG'
  r'|^End of (the |this )?Project Gutenberg',
  caseSensitive: false,
);
final RegExp _theEnd = RegExp(
  r'^\W*(the end|finis|fin)\W*$',
  caseSensitive: false,
);
final RegExp _frontMatterSigns = RegExp(
  r'©|\bcopyright\b|all rights reserved|\bisbn\b|library of congress'
  r'|first published|published by|printed in|table of contents'
  r'|project gutenberg',
  caseSensitive: false,
);

/// Label, title and subtitle of a section heading.
///
/// From the navigation title when there is one (the publisher's wording),
/// otherwise from the first heading line. Further heading lines fill in a
/// missing title ("Chapter 1" / "The Arrival") and then the subtitle.
({String label, String title, String? subtitle}) _parseHeading(_Node node) {
  final lines = node.lines;
  final String source;
  final List<String> rest;
  if (node.fromOutline || lines.isEmpty) {
    source = node.title;
    final covered = _normaliseWords(source).join(' ');
    rest = [
      for (final line in lines)
        if (_normaliseWords(line).isNotEmpty &&
            !covered.contains(_normaliseWords(line).join(' ')))
          line,
    ];
  } else {
    source = lines.first;
    rest = lines.sublist(1);
  }

  var label = '';
  var title = '';
  final raw = source.replaceAll(RegExp(r'\s+'), ' ').trim();
  final split = _labelTitle.firstMatch(raw);
  if (split != null) {
    label = split.group(1)!.trim();
    title = (split.group(2) ?? '').trim();
  } else {
    final numbered = _numberTitle.firstMatch(raw);
    if (numbered != null) {
      label = numbered.group(1)!;
      title = numbered.group(2)!.trim();
    } else if (_bareNumber.hasMatch(raw)) {
      label = raw;
    } else {
      title = raw;
    }
  }

  if (title.isEmpty && rest.isNotEmpty) title = rest.removeAt(0);
  var subtitle = node.subtitle ?? (rest.isNotEmpty ? rest.first : null);

  label = _presentable(label, isLabel: true);
  title = _presentable(title);
  subtitle = subtitle == null ? null : _presentable(subtitle);
  if (subtitle != null && (subtitle.isEmpty || subtitle == title)) {
    subtitle = null;
  }
  return (label: label, title: title, subtitle: subtitle);
}

final RegExp _labelTitle = RegExp(
  '^((?:chapter|chap\\.?|part|book|volume|letter|canto|stave|act|scene'
  '|lecture|lesson|appendix) $_num)\\b\\s*[.:—–\\-]*\\s*(.*)\$',
  caseSensitive: false,
);
final RegExp _numberTitle = RegExp(
  r'^(\d{1,3}|[IVXLCDM]{1,7})[.):]?\s+(\S.*)$',
);
final RegExp _bareNumber = RegExp(r'^(\d{1,3}|[IVXLCDM]{1,7})[.):]?$');

/// Tidies a heading for display: no trailing full stop, and ALL CAPS
/// becomes Title Case ("THE POOL OF TEARS" → "The Pool of Tears").
String _presentable(String text, {bool isLabel = false}) {
  var t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return t;
  if (t.endsWith('.') && !t.endsWith('..') && !_abbreviationEnd.hasMatch(t)) {
    t = t.substring(0, t.length - 1).trimRight();
  }
  final letters = t.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
  final shouting = letters.length >= 4 && letters == letters.toUpperCase();
  if (shouting || (isLabel && letters == letters.toUpperCase())) {
    t = _titleCase(t, isLabel: isLabel);
  }
  return t;
}

final RegExp _abbreviationEnd = RegExp(
  r'\b(?:[A-Za-z]\.){2,}$|\b(?:Mr|Mrs|Dr|St|Jr|Sr)\.$',
);

const Set<String> _smallWords = {
  'a',
  'an',
  'and',
  'as',
  'at',
  'but',
  'by',
  'for',
  'from',
  'in',
  'into',
  'nor',
  'of',
  'on',
  'or',
  'the',
  'to',
  'with',
};

/// A well-formed Roman numeral ("XIV", not "CIVIL").
final RegExp _romanNumeral = RegExp(
  r'^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$',
);

/// Title-cases [text]. In a label ("CHAPTER XIV") Roman numerals stay
/// upper-case; in a title they are ordinary words ("THE MIX" → "The Mix").
String _titleCase(String text, {bool isLabel = false}) {
  final words = text.split(' ');
  final out = <String>[];
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    final core = word.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
    if (core.isEmpty) {
      out.add(word);
      continue;
    }
    if (isLabel && i > 0 && _romanNumeral.hasMatch(core)) {
      out.add(word);
      continue;
    }
    final lower = word.toLowerCase();
    if (i > 0 && _smallWords.contains(core.toLowerCase())) {
      out.add(lower);
      continue;
    }
    // Capitalise the first letter, and the first after a hyphen or quote.
    out.add(
      lower.replaceAllMapped(
        RegExp('(^|[\\-–—\u2018\u201C"(\\[])(\\p{L})', unicode: true),
        (m) => '${m.group(1)}${m.group(2)!.toUpperCase()}',
      ),
    );
  }
  return out.join(' ');
}
