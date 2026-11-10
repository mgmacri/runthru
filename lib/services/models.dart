/// Data models for the PDF pipeline.
library;

/// Version of the extraction output format.
///
/// Bumped whenever extractors change what they emit, so documents cached by
/// an older build are re-extracted instead of being read with missing data.
///
/// * 1: sentences and page boundaries only.
/// * 2: heading levels, the source's own outline (table of contents), and
///   layout-aware PDF text (running headers removed, hyphenation rejoined).
const int kExtractionVersion = 2;

class Sentence {
  const Sentence({
    required this.words,
    this.startsParagraph = false,
    this.heading = 0,
  });

  factory Sentence.fromJson(Map<String, Object?> json) {
    final words =
        (json['words'] as List<Object?>?)?.cast<String>() ?? <String>[];
    return Sentence(
      words: words,
      startsParagraph: json['p'] == true,
      heading: json['h'] as int? ?? 0,
    );
  }

  final List<String> words;

  /// Whether this sentence opens a paragraph (or a heading). Documents
  /// extracted before paragraph data existed load with every value false.
  final bool startsParagraph;

  /// Heading level when this "sentence" is a whole heading line
  /// (1 = largest, as in `<h1>`), or 0 for body text. A heading is never
  /// split on its own punctuation: "1. The Arrival" is one sentence.
  final int heading;

  /// Whether this sentence is a heading line.
  bool get isHeading => heading > 0;

  /// `p` and `h` are written only when set, so stored documents stay
  /// compact and older readers ignore them.
  Map<String, Object?> toJson() => {
    'words': words,
    if (startsParagraph) 'p': true,
    if (heading > 0) 'h': heading,
  };
}

/// One entry of the source's own navigation: an EPUB table-of-contents or
/// landmark entry, or a PDF bookmark.
///
/// Extractors record these as they find them; `analyzeBookStructure` turns
/// them (with the in-text headings) into the sections the reader shows.
class OutlineEntry {
  const OutlineEntry({
    required this.title,
    required this.startWordIndex,
    required this.startSentenceIndex,
    this.depth = 0,
    this.type,
  });

  factory OutlineEntry.fromJson(Map<String, Object?> json) {
    return OutlineEntry(
      title: json['t'] as String? ?? '',
      startWordIndex: json['w'] as int? ?? 0,
      startSentenceIndex: json['s'] as int? ?? 0,
      depth: json['d'] as int? ?? 0,
      type: json['k'] as String?,
    );
  }

  /// The label the source gives this entry ("Chapter 3", "Index"). Empty
  /// for entries that only carry a [type] (an untitled copyright page).
  final String title;

  /// Global word index the entry points at.
  final int startWordIndex;

  /// Global sentence index the entry points at.
  final int startSentenceIndex;

  /// Nesting depth in the source's navigation (0 = top level).
  final int depth;

  /// The source's own semantic label for the target, lower-case, when it has
  /// one: an `epub:type` / guide type such as `bodymatter`, `toc`,
  /// `copyright-page`, `foreword`, `chapter`, `index`. Null when unknown.
  final String? type;

  /// A copy moved by the given offsets (used when chunks are merged).
  OutlineEntry shifted({required int words, required int sentences}) {
    return OutlineEntry(
      title: title,
      startWordIndex: startWordIndex + words,
      startSentenceIndex: startSentenceIndex + sentences,
      depth: depth,
      type: type,
    );
  }

  Map<String, Object?> toJson() => {
    't': title,
    'w': startWordIndex,
    's': startSentenceIndex,
    if (depth > 0) 'd': depth,
    if (type != null) 'k': type,
  };
}

class ExtractedDocument {
  const ExtractedDocument({
    required this.sentences,
    this.pageBoundaries = const [],
    this.totalPages = 0,
    this.outline = const [],
    this.version = kExtractionVersion,
    this.continuesPrevious = false,
  });

  factory ExtractedDocument.fromJson(Map<String, Object?> json) {
    final sentences =
        (json['sentences'] as List<Object?>?)
            ?.map((e) => Sentence.fromJson(e as Map<String, Object?>))
            .toList() ??
        <Sentence>[];
    final pageBoundaries =
        (json['pageBoundaries'] as List<Object?>?)
            ?.map((e) => PageBoundary.fromJson(e as Map<String, Object?>))
            .toList() ??
        <PageBoundary>[];
    final outline =
        (json['outline'] as List<Object?>?)
            ?.map((e) => OutlineEntry.fromJson(e as Map<String, Object?>))
            .toList() ??
        const <OutlineEntry>[];
    return ExtractedDocument(
      sentences: sentences,
      pageBoundaries: pageBoundaries,
      totalPages: json['totalPages'] as int? ?? 0,
      outline: outline,
      // Documents stored before the field existed are version 1.
      version: json['v'] as int? ?? 1,
    );
  }

  final List<Sentence> sentences;
  final List<PageBoundary> pageBoundaries;
  final int totalPages;

  /// The source's own navigation (EPUB table of contents and landmarks, PDF
  /// bookmarks), in reading order. Empty when the source has none.
  final List<OutlineEntry> outline;

  /// The [kExtractionVersion] that produced this document.
  final int version;

  /// Set on an extraction chunk whose first sentence continues the sentence
  /// the previous chunk ended on (a page or file boundary fell mid-sentence).
  /// [merge] joins the two. Never stored.
  final bool continuesPrevious;

  /// Total word count across all sentences.
  int get totalWords => sentences.fold(0, (sum, s) => sum + s.words.length);

  /// Flat list of all words in reading order.
  List<String> get allWords => sentences.expand((s) => s.words).toList();

  /// Whether this document has page boundary data (for range picker support).
  bool get hasPageBoundaries => pageBoundaries.isNotEmpty;

  /// Append sentences from another document (used for progressive extraction).
  ///
  /// Phase-2 extractions start their own word and sentence indices from zero.
  /// We offset every incoming [PageBoundary] and [OutlineEntry] by this
  /// document's current word and sentence counts so the merged positions are
  /// globally correct.
  ///
  /// When [other] is marked [continuesPrevious], its first sentence is
  /// joined onto this document's last one, and a word hyphenated across the
  /// boundary (left ending in [kSplitWordMarker]) becomes one word again.
  ExtractedDocument merge(ExtractedDocument other) {
    var merged = sentences;
    var incoming = other.sentences;
    var wordOffset = totalWords;
    var sentenceOffset = sentences.length;

    if (other.continuesPrevious &&
        sentences.isNotEmpty &&
        incoming.isNotEmpty &&
        !sentences.last.isHeading &&
        !incoming.first.isHeading) {
      final last = sentences.last;
      final first = incoming.first;
      final List<String> words;
      if (last.words.isNotEmpty &&
          first.words.isNotEmpty &&
          last.words.last.endsWith(kSplitWordMarker)) {
        words = [
          ...last.words.take(last.words.length - 1),
          joinSplitWord(last.words.last, first.words.first),
          ...first.words.skip(1),
        ];
        wordOffset -= 1;
      } else {
        words = [...last.words, ...first.words];
      }
      merged = [
        ...sentences.take(sentences.length - 1),
        Sentence(
          words: words,
          startsParagraph: last.startsParagraph,
          heading: last.heading,
        ),
      ];
      incoming = incoming.sublist(1);
      sentenceOffset -= 1;
    }

    final offsetBoundaries = other.pageBoundaries
        .map(
          (b) => PageBoundary(
            pageNumber: b.pageNumber,
            startSentenceIndex: b.startSentenceIndex + sentenceOffset,
            startWordIndex: b.startWordIndex + wordOffset,
            firstWords: b.firstWords,
          ),
        )
        .toList();
    final offsetOutline = [
      for (final e in other.outline)
        e.shifted(words: wordOffset, sentences: sentenceOffset),
    ];
    return ExtractedDocument(
      sentences: [...merged, ...incoming],
      pageBoundaries: [...pageBoundaries, ...offsetBoundaries],
      totalPages: other.totalPages > 0 ? other.totalPages : totalPages,
      outline: [...outline, ...offsetOutline],
      version: version < other.version ? version : other.version,
    );
  }

  Map<String, Object?> toJson() => {
    'sentences': sentences.map((s) => s.toJson()).toList(),
    'pageBoundaries': pageBoundaries.map((b) => b.toJson()).toList(),
    'totalPages': totalPages,
    if (outline.isNotEmpty) 'outline': outline.map((e) => e.toJson()).toList(),
    'v': version,
  };
}

/// Marks a word that was hyphenated across an extraction boundary: the left
/// half ends with this (a soft hyphen, invisible when rendered) until
/// [ExtractedDocument.merge] joins it to its other half.
const String kSplitWordMarker = '\u00AD';

/// Joins the two halves of a word hyphenated across a line, page or chunk
/// break. The hyphen is dropped ("fa-" + "ther" → "father") unless it is
/// part of the word: the right half starts with a capital or a digit
/// ("Anglo-" + "Saxon"), or the left half is a prefix that takes a hyphen
/// ("self-" + "aware").
String joinSplitWord(String left, String right) {
  var stem = left;
  while (stem.isNotEmpty &&
      (stem.endsWith(kSplitWordMarker) ||
          stem.endsWith('-') ||
          stem.endsWith('\u2010'))) {
    stem = stem.substring(0, stem.length - 1);
  }
  if (right.isEmpty) return stem;
  final keepHyphen =
      _startsUpperOrDigit.hasMatch(right) ||
      _hyphenPrefixes.contains(_lettersOnly(stem).toLowerCase());
  return keepHyphen ? '$stem-$right' : '$stem$right';
}

final RegExp _startsUpperOrDigit = RegExp(r'^[\p{Lu}\d]', unicode: true);

String _lettersOnly(String s) =>
    s.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');

/// Prefixes that keep their hyphen in English compounds.
const Set<String> _hyphenPrefixes = {
  'self',
  'well',
  'half',
  'ex',
  'all',
  'cross',
  'great',
  'quasi',
  'ill',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
};

enum PdfStatus {
  pending,
  queued,
  processing,

  /// Phase 1 complete — pages 1–3 extracted, remaining pages pending.
  preview,
  ready,
  error,
  unsupported,
  permanentlyFailed,
}

/// Per-file progress tracking for chunked extraction.
class PdfProgress {
  const PdfProgress({
    this.lastCompletedPage = 0,
    this.totalPages = 0,
    this.phase = ExtractionPhase.pending,
  });

  final int lastCompletedPage;
  final int totalPages;
  final ExtractionPhase phase;

  /// 0.0–1.0 page completion ratio.
  double get fraction => totalPages > 0 ? lastCompletedPage / totalPages : 0.0;

  PdfProgress copyWith({
    int? lastCompletedPage,
    int? totalPages,
    ExtractionPhase? phase,
  }) {
    return PdfProgress(
      lastCompletedPage: lastCompletedPage ?? this.lastCompletedPage,
      totalPages: totalPages ?? this.totalPages,
      phase: phase ?? this.phase,
    );
  }
}

enum ExtractionPhase { pending, preview, backgroundCompletion, done }

class PdfEntry {
  const PdfEntry({
    required this.filePath,
    required this.fileName,
    this.status = PdfStatus.pending,
    this.document,
    this.errorMessage,
    this.retryCount = 0,
    this.progress = const PdfProgress(),
  });

  final String filePath;
  final String fileName;
  final PdfStatus status;
  final ExtractedDocument? document;
  final String? errorMessage;
  final int retryCount;
  final PdfProgress progress;

  /// Max retries before marking as permanently failed.
  static const int maxRetries = 3;

  PdfEntry copyWith({
    PdfStatus? status,
    ExtractedDocument? document,
    bool clearDocument = false,
    String? errorMessage,
    int? retryCount,
    PdfProgress? progress,
  }) {
    return PdfEntry(
      filePath: filePath,
      fileName: fileName,
      status: status ?? this.status,
      document: clearDocument ? null : (document ?? this.document),
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
      progress: progress ?? this.progress,
    );
  }
}

/// Overall processing progress across all PDFs.
class OverallProgress {
  const OverallProgress({this.completed = 0, this.total = 0});

  final int completed;
  final int total;

  double get percent => total > 0 ? completed / total : 0.0;
}

class UnsupportedPdfError implements Exception {
  const UnsupportedPdfError(this.message);
  final String message;
  @override
  String toString() => 'UnsupportedPdfError: $message';
}

class PdfTimeoutError implements Exception {
  const PdfTimeoutError(this.filePath);
  final String filePath;
  @override
  String toString() =>
      'PdfTimeoutError: extraction exceeded timeout for $filePath';
}

// ── Page boundary tracking (Prompt 3) ────────────────────────────────

/// Marks where a PDF page begins in the global word/sentence stream.
class PageBoundary {
  const PageBoundary({
    required this.pageNumber,
    required this.startSentenceIndex,
    required this.startWordIndex,
    this.firstWords = '',
  });

  factory PageBoundary.fromJson(Map<String, Object?> json) {
    return PageBoundary(
      pageNumber: json['pageNumber'] as int? ?? 0,
      startSentenceIndex: json['startSentenceIndex'] as int? ?? 0,
      startWordIndex: json['startWordIndex'] as int? ?? 0,
      firstWords: json['firstWords'] as String? ?? '',
    );
  }

  final int pageNumber;
  final int startSentenceIndex;
  final int startWordIndex;

  /// First ~5 words as a preview label.
  final String firstWords;

  Map<String, Object?> toJson() => {
    'pageNumber': pageNumber,
    'startSentenceIndex': startSentenceIndex,
    'startWordIndex': startWordIndex,
    'firstWords': firstWords,
  };
}

/// User-defined reading range (start page/word → end page/word).
class ReadingRange {
  const ReadingRange({
    required this.startPage,
    this.startWordIndexOnPage = 0,
    this.startWordAnchor,
    required this.endPage,
    this.endWordIndexOnPage = 0,
    this.endWordAnchor,
    this.resolvedStartWordIndex = 0,
    this.resolvedEndWordIndex = 0,
  });

  factory ReadingRange.fromJson(Map<String, Object?> json) {
    return ReadingRange(
      startPage: json['startPage'] as int? ?? 0,
      startWordIndexOnPage: json['startWordIndexOnPage'] as int? ?? 0,
      startWordAnchor: json['startWordAnchor'] as String?,
      endPage: json['endPage'] as int? ?? 0,
      endWordIndexOnPage: json['endWordIndexOnPage'] as int? ?? 0,
      endWordAnchor: json['endWordAnchor'] as String?,
      resolvedStartWordIndex: json['resolvedStartWordIndex'] as int? ?? 0,
      resolvedEndWordIndex: json['resolvedEndWordIndex'] as int? ?? 0,
    );
  }

  final int startPage;
  final int startWordIndexOnPage;
  final String? startWordAnchor;
  final int endPage;
  final int endWordIndexOnPage;
  final String? endWordAnchor;
  final int resolvedStartWordIndex;
  final int resolvedEndWordIndex;

  ReadingRange copyWith({
    int? startPage,
    int? startWordIndexOnPage,
    String? startWordAnchor,
    int? endPage,
    int? endWordIndexOnPage,
    String? endWordAnchor,
    int? resolvedStartWordIndex,
    int? resolvedEndWordIndex,
  }) {
    return ReadingRange(
      startPage: startPage ?? this.startPage,
      startWordIndexOnPage: startWordIndexOnPage ?? this.startWordIndexOnPage,
      startWordAnchor: startWordAnchor ?? this.startWordAnchor,
      endPage: endPage ?? this.endPage,
      endWordIndexOnPage: endWordIndexOnPage ?? this.endWordIndexOnPage,
      endWordAnchor: endWordAnchor ?? this.endWordAnchor,
      resolvedStartWordIndex:
          resolvedStartWordIndex ?? this.resolvedStartWordIndex,
      resolvedEndWordIndex: resolvedEndWordIndex ?? this.resolvedEndWordIndex,
    );
  }

  Map<String, Object?> toJson() => {
    'startPage': startPage,
    'startWordIndexOnPage': startWordIndexOnPage,
    'startWordAnchor': startWordAnchor,
    'endPage': endPage,
    'endWordIndexOnPage': endWordIndexOnPage,
    'endWordAnchor': endWordAnchor,
    'resolvedStartWordIndex': resolvedStartWordIndex,
    'resolvedEndWordIndex': resolvedEndWordIndex,
  };
}

/// Resolves a ReadingRange to global word indices using page boundaries.
({int globalStart, int globalEnd}) resolveRange(
  ReadingRange range,
  List<PageBoundary> boundaries,
) {
  int resolvePageWord(int page, int wordOnPage, String? anchor) {
    // Find the boundary for the target page
    PageBoundary? boundary;
    for (final b in boundaries) {
      if (b.pageNumber == page) {
        boundary = b;
        break;
      }
    }
    if (boundary == null) {
      // Fall back: use the last boundary before this page
      for (final b in boundaries.reversed) {
        if (b.pageNumber <= page) {
          boundary = b;
          break;
        }
      }
    }
    return (boundary?.startWordIndex ?? 0) + wordOnPage;
  }

  final globalStart = resolvePageWord(
    range.startPage,
    range.startWordIndexOnPage,
    range.startWordAnchor,
  );
  final globalEnd = resolvePageWord(
    range.endPage,
    range.endWordIndexOnPage,
    range.endWordAnchor,
  );
  return (globalStart: globalStart, globalEnd: globalEnd);
}
