import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/pdf_text_layout.dart';

/// Per-file extraction timeout.
const Duration _extractionTimeout = Duration(seconds: 30);

/// Number of pages extracted in the "preview" phase.
const int previewPageCount = 3;

/// Maximum extra pages to probe when the initial preview pages yield no text.
/// Handles books whose front matter (cover, title, copyright, TOC) is
/// image-only — the real text often starts a few pages later.
const int _maxProbePages = 10;

/// Pages read on either side of an extracted range purely as layout
/// evidence; their text is not emitted. A running header that appears once
/// in a three-page preview repeats within the wider window, and the page
/// before a range shows whether the range opens mid-sentence.
const int _evidencePages = 2;

/// Pages analysed together when a whole document is extracted in one call.
/// Bounds how many pages of character boxes are held at once.
const int _documentChunkPages = 25;

/// Cooperative cancellation for page-range extraction.
///
/// pdfrx runs on the main isolate (FFI) and `loadText()` for a single page
/// cannot be interrupted, so cancellation is checked **between pages**: a
/// timed-out extraction stops burning the UI thread after at most one more
/// page instead of finishing the whole book in the background. (pdfrx
/// exposes no cancellation token for `loadText`, and `Isolate.kill` is not
/// applicable because FFI pins extraction to the main isolate.)
class ExtractionCancelToken {
  /// Whether the extraction should stop at the next page boundary.
  bool cancelled = false;
}

/// Message passed to the isolate for page-range extraction.
class _PageRangeRequest {
  const _PageRangeRequest({
    required this.filePath,
    required this.startPage,
    required this.endPage,
  });

  final String filePath;

  /// 0-based inclusive start page index.
  final int startPage;

  /// 0-based inclusive end page index (clamped to last page).
  final int endPage;
}

/// Result from page-range extraction including page metadata.
class PageRangeResult {
  const PageRangeResult({
    required this.document,
    required this.totalPages,
    required this.extractedStartPage,
    required this.extractedEndPage,
    this.pageBoundaries = const [],
  });

  final ExtractedDocument document;
  final int totalPages;

  /// 0-based inclusive start page actually extracted.
  final int extractedStartPage;

  /// 0-based inclusive end page actually extracted.
  final int extractedEndPage;

  /// Page boundary markers for reading range support.
  final List<PageBoundary> pageBoundaries;
}

/// Where the extractor reads raw pages from: pdfium in the app, synthetic
/// pages in tests (pdfium cannot run under `flutter test`).
abstract interface class PdfPageSource {
  /// Number of pages in the document.
  int get pageCount;

  /// The raw text and character boxes of the page at [pageIndex] (0-based).
  Future<PdfRawPage> loadPage(int pageIndex);

  /// The document's bookmarks, flattened in tree order.
  Future<List<PdfOutlineTarget>> loadOutline();
}

/// Extracts text from a PDF file.
/// Records [PageBoundary] markers for reading range support.
///
/// The text is rebuilt from pdfium's character boxes by
/// [analyzePdfLayout]: page furniture is removed, hyphenation rejoined, and
/// paragraphs, headings and the bookmark outline are recovered.
///
/// pdfrx uses FFI — must run on the main isolate. Classification logic
/// runs separately in [Isolate.run()] where applicable.
///
/// For PDFs with no text layer (image-only), returns an empty
/// [ExtractedDocument] instead of throwing, unless [throwOnEmpty] is true.
Future<ExtractedDocument> pdfExtract(
  String filePath, {
  bool throwOnEmpty = true,
}) {
  return _pdfExtractDocument(filePath, throwOnEmpty: throwOnEmpty);
}

Future<ExtractedDocument> _pdfExtractDocument(
  String filePath, {
  required bool throwOnEmpty,
  ExtractionCancelToken? cancelToken,
  void Function(double fraction)? onProgress,
}) async {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('File not found', filePath);
  }

  final document = await PdfDocument.openFile(filePath);
  try {
    return await extractPdfDocumentFrom(
      _PdfiumSource(document),
      throwOnEmpty: throwOnEmpty,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  } finally {
    await document.dispose();
  }
}

/// Extracts text from a PDF with progress reporting.
///
/// Returns a [Stream] that emits progress values from 0.0 to 1.0 during
/// extraction. The final [ExtractedDocument] is returned via the
/// [onComplete] callback. Use this for UI progress indicators.
///
/// pdfrx uses FFI — must run on the main isolate.
Stream<double> pdfExtractWithProgress(
  String filePath, {
  required void Function(ExtractedDocument document) onComplete,
  required void Function(Object error) onError,
}) {
  final controller = StreamController<double>();

  () async {
    try {
      // Graceful on image-only PDFs: an empty document, not an error.
      final document = await _pdfExtractDocument(
        filePath,
        throwOnEmpty: false,
        onProgress: controller.add,
      );
      onComplete(document);
    } on Exception catch (e) {
      onError(e);
    } finally {
      await controller.close();
    }
  }();

  return controller.stream;
}

/// Extracts text from a specific page range of a PDF.
/// [startPage] and [endPage] are 0-based inclusive indices.
/// Also records page boundaries for reading range support.
Future<PageRangeResult> _pdfExtractPages(
  _PageRangeRequest request,
  ExtractionCancelToken cancelToken,
) async {
  final file = File(request.filePath);
  if (!file.existsSync()) {
    throw FileSystemException('File not found', request.filePath);
  }

  final document = await PdfDocument.openFile(request.filePath);
  try {
    return await extractPdfPagesFrom(
      _PdfiumSource(document),
      request.startPage,
      request.endPage,
      cancelToken: cancelToken,
      label: request.filePath,
    );
  } finally {
    await document.dispose();
  }
}

/// Page-range extraction over any [PdfPageSource]: the implementation
/// behind [extractPdfPagesInIsolate].
///
/// [startPage] and [endPage] are 0-based inclusive indices, clamped to the
/// document. One [PageBoundary] is recorded per extracted page; a page may
/// begin mid-sentence, in which case its boundary names the sentence that
/// contains its first word.
///
/// When a range starting at page 0 has no text, up to [_maxProbePages]
/// further pages are extracted before giving up, for books whose front
/// matter (cover, title, copyright, dedication) is image-only.
///
/// Throws [UnsupportedPdfError] when a range starting at page 0 still has
/// no text. [label] names the file in log lines.
Future<PageRangeResult> extractPdfPagesFrom(
  PdfPageSource source,
  int startPage,
  int endPage, {
  ExtractionCancelToken? cancelToken,
  String label = 'pdf',
}) async {
  final totalPages = source.pageCount;
  if (totalPages <= 0) {
    throw const UnsupportedPdfError('Image-only PDF — no extractable text');
  }
  final clampedEnd = endPage.clamp(0, totalPages - 1);
  final clampedStart = startPage.clamp(0, clampedEnd);
  final cache = <int, PdfRawPage>{};

  PageRangeResult cancelled() {
    // Abandoned by a timeout: return quietly (the result is discarded)
    // instead of working through the rest of the range on the UI thread.
    appLog('pdf_extractor', 'extraction cancelled in $label');
    return PageRangeResult(
      document: ExtractedDocument(sentences: const [], totalPages: totalPages),
      totalPages: totalPages,
      extractedStartPage: clampedStart,
      extractedEndPage: clampedStart - 1,
    );
  }

  if (cancelToken?.cancelled ?? false) return cancelled();
  final outline = await _outlineOf(source);

  // Effective end page — may be extended if front matter is blank.
  var effectiveEnd = clampedEnd;
  var document = await _extractRange(
    source,
    clampedStart,
    clampedEnd,
    cache: cache,
    outline: outline,
    cancelToken: cancelToken,
  );
  if (document == null) return cancelled();

  // If the original range has no text and it was a preview starting at
  // page 0, extract up to _maxProbePages extra pages before giving up.
  if (document.sentences.isEmpty && clampedStart == 0) {
    final probeLimit = math.min(clampedEnd + _maxProbePages, totalPages - 1);
    if (probeLimit > clampedEnd) {
      appLog(
        'pdf_extractor',
        'No text in pages 0–$clampedEnd, probing up to page $probeLimit',
      );
      effectiveEnd = probeLimit;
      document = await _extractRange(
        source,
        clampedStart,
        probeLimit,
        cache: cache,
        outline: outline,
        cancelToken: cancelToken,
      );
      if (document == null) return cancelled();
    }
  }

  if (document.sentences.isEmpty && clampedStart == 0) {
    throw const UnsupportedPdfError('Image-only PDF — no extractable text');
  }

  return PageRangeResult(
    document: document,
    totalPages: totalPages,
    extractedStartPage: clampedStart,
    extractedEndPage: effectiveEnd,
    pageBoundaries: document.pageBoundaries,
  );
}

/// Whole-document extraction over any [PdfPageSource]: the implementation
/// behind [pdfExtract] and [pdfExtractWithProgress].
///
/// The document is extracted in ranges of [_documentChunkPages] pages that
/// are merged as they complete, exactly as the preprocessing queue merges
/// its chunks. [onProgress] receives the share of pages read so far.
///
/// Throws [UnsupportedPdfError] for a document with no text when
/// [throwOnEmpty] is true.
Future<ExtractedDocument> extractPdfDocumentFrom(
  PdfPageSource source, {
  bool throwOnEmpty = true,
  ExtractionCancelToken? cancelToken,
  void Function(double fraction)? onProgress,
}) async {
  final totalPages = source.pageCount;
  var document = ExtractedDocument(sentences: const [], totalPages: totalPages);
  final cache = <int, PdfRawPage>{};
  final outline = totalPages > 0
      ? await _outlineOf(source)
      : const <PdfOutlineTarget>[];

  for (var start = 0; start < totalPages; start += _documentChunkPages) {
    final end = math.min(start + _documentChunkPages, totalPages) - 1;
    final chunk = await _extractRange(
      source,
      start,
      end,
      cache: cache,
      outline: outline,
      cancelToken: cancelToken,
      onPage: onProgress == null
          ? null
          : (pageIndex) => onProgress((pageIndex + 1) / totalPages),
    );
    if (chunk == null) {
      // Abandoned by a timeout; the partial result is discarded.
      appLog('pdf_extractor', 'extraction cancelled at page $start');
      return document;
    }
    document = document.merge(chunk);
    // Keep only what the next range needs as evidence.
    cache.removeWhere((pageIndex, _) => pageIndex <= end - _evidencePages);
  }

  if (document.sentences.isEmpty && throwOnEmpty) {
    throw const UnsupportedPdfError('Image-only PDF — no extractable text');
  }
  return document;
}

/// Rebuilds the text of a window of pages on a background isolate.
///
/// pdfium has to be read on the main isolate, but the analysis of what it
/// returned is pure Dart over plain data: tens of milliseconds for a
/// 25-page range on a desktop, several times that on a phone. Run where
/// the pages are read, that is a dropped-frame hitch in whatever is on
/// screen (the reader, if a range was in flight when reading started).
///
/// Its own function so the closure sent to the isolate can only capture
/// these arguments, never the pdfium document of the caller's scope.
Future<PdfLayoutResult> _analyzeOffTheUiIsolate(
  List<PdfRawPage> window,
  int firstPage,
  int lastPage,
  List<PdfOutlineTarget> outline,
) {
  return Isolate.run(
    () => analyzePdfLayout(
      window,
      firstPage: firstPage,
      lastPage: lastPage,
      outline: outline,
    ),
    debugName: 'pdf-layout',
  );
}

/// The one implementation every entry point shares: reads pages
/// [start]..[end] plus [_evidencePages] either side, and rebuilds the text
/// of [start]..[end] from their layout.
///
/// Returns null when [cancelToken] is cancelled; cancellation is checked
/// before every page read. Pages already in [cache] are not read again.
Future<ExtractedDocument?> _extractRange(
  PdfPageSource source,
  int start,
  int end, {
  required Map<int, PdfRawPage> cache,
  required List<PdfOutlineTarget> outline,
  ExtractionCancelToken? cancelToken,
  void Function(int pageIndex)? onPage,
}) async {
  final totalPages = source.pageCount;
  final from = math.max(0, start - _evidencePages);
  final to = math.min(totalPages - 1, end + _evidencePages);

  final window = <PdfRawPage>[];
  for (var i = from; i <= to; i++) {
    if (cancelToken?.cancelled ?? false) return null;
    var page = cache[i];
    if (page == null) {
      if (i >= start && i <= end) {
        page = await source.loadPage(i);
      } else {
        // Evidence is a help, not a requirement.
        try {
          page = await source.loadPage(i);
        } on Exception catch (e) {
          appLog('pdf_extractor', 'evidence page $i unavailable: $e');
          page = PdfRawPage.empty(pageIndex: i);
        }
      }
      cache[i] = page;
    }
    window.add(page);
    if (i >= start && i <= end) onPage?.call(i);
  }
  if (cancelToken?.cancelled ?? false) return null;

  final layout =
      await _analyzeOffTheUiIsolate(window, start, end, <PdfOutlineTarget>[
        for (final target in outline)
          if (target.pageIndex >= start && target.pageIndex <= end) target,
      ]);
  // The timeout may have fired while the pages were being analysed.
  if (cancelToken?.cancelled ?? false) return null;
  return ExtractedDocument(
    sentences: layout.sentences,
    pageBoundaries: <PageBoundary>[
      for (final page in layout.pageStarts)
        PageBoundary(
          pageNumber: page.pageIndex,
          startSentenceIndex: page.startSentenceIndex,
          startWordIndex: page.startWordIndex,
          firstWords: page.firstWords,
        ),
    ],
    totalPages: totalPages,
    outline: layout.outline,
    continuesPrevious: layout.continuesPrevious,
  );
}

/// The bookmarks of [source], or none when they cannot be read: a broken
/// outline must not cost the reader the book.
Future<List<PdfOutlineTarget>> _outlineOf(PdfPageSource source) async {
  try {
    return await source.loadOutline();
  } on Exception catch (e) {
    appLog('pdf_extractor', 'outline unavailable: $e');
    return const <PdfOutlineTarget>[];
  }
}

/// [PdfPageSource] over an open pdfium document.
class _PdfiumSource implements PdfPageSource {
  _PdfiumSource(this._document);

  final PdfDocument _document;

  @override
  int get pageCount => _document.pages.length;

  @override
  Future<PdfRawPage> loadPage(int pageIndex) async {
    final page = _document.pages[pageIndex];
    final raw = await page.loadText();
    if (raw == null) {
      return PdfRawPage.empty(
        pageIndex: pageIndex,
        width: page.width,
        height: page.height,
      );
    }
    return PdfRawPage(
      pageIndex: pageIndex,
      width: page.width,
      height: page.height,
      text: raw.fullText,
      charBoxes: _charBoxes(raw, page),
    );
  }

  /// One box per UTF-16 code unit of the page text, in the page's displayed
  /// orientation.
  Float64List _charBoxes(PdfPageRawText raw, PdfPage page) {
    final text = raw.fullText;
    final rects = raw.charRects;
    final units = text.length;
    final rotation = page.rotation.index;
    final boxes = Float64List(units * kPdfCharBoxStride);

    void put(int unit, PdfRect rect) {
      // pdfium reports boxes in the unrotated page's coordinates.
      final r = rotation == 0 ? rect : rect.rotate(rotation, page);
      final o = unit * kPdfCharBoxStride;
      boxes[o] = r.left;
      boxes[o + 1] = r.top;
      boxes[o + 2] = r.right;
      boxes[o + 3] = r.bottom;
    }

    if (rects.length == units) {
      for (var i = 0; i < units; i++) {
        put(i, rects[i]);
      }
      return boxes;
    }
    // pdfium counts characters, Dart counts UTF-16 code units: a character
    // outside the Basic Multilingual Plane is one box but two units.
    if (rects.length == text.runes.length) {
      var unit = 0;
      var index = 0;
      for (final rune in text.runes) {
        final rect = rects[index++];
        put(unit++, rect);
        if (rune > 0xFFFF) put(unit++, rect);
      }
      return boxes;
    }
    // Boxes that cannot be matched to the text are worse than none.
    return Float64List(0);
  }

  @override
  Future<List<PdfOutlineTarget>> loadOutline() async {
    final targets = <PdfOutlineTarget>[];
    final pages = _document.pages;

    void walk(List<PdfOutlineNode> nodes, int depth) {
      for (final node in nodes) {
        final dest = node.dest;
        if (dest != null &&
            dest.pageNumber >= 1 &&
            dest.pageNumber <= pages.length) {
          final page = pages[dest.pageNumber - 1];
          final at = _destinationPoint(dest, page);
          targets.add(
            PdfOutlineTarget(
              title: node.title,
              pageIndex: dest.pageNumber - 1,
              depth: depth,
              top: at?.y,
              left: at?.x,
            ),
          );
        }
        // A node without a destination (a web link, a bare group) still
        // has children worth keeping.
        walk(node.children, depth + 1);
      }
    }

    walk(await _document.loadOutline(), 0);
    return targets;
  }

  /// Where on its page a bookmark points, when it says: the top-left of an
  /// `xyz` or `fitr` destination, the top of a `fith`.
  PdfPoint? _destinationPoint(PdfDest dest, PdfPage page) {
    final params = dest.params;
    if (params == null) return null;
    double? at(int i) => i < params.length ? params[i] : null;
    final double? left;
    final double? top;
    switch (dest.command) {
      case PdfDestCommand.xyz:
        left = at(0);
        top = at(1);
      case PdfDestCommand.fitR:
        left = at(0);
        top = at(3);
      case PdfDestCommand.fitH:
      case PdfDestCommand.fitBH:
        left = null;
        top = at(0);
      case PdfDestCommand.unknown:
      case PdfDestCommand.fit:
      case PdfDestCommand.fitV:
      case PdfDestCommand.fitB:
      case PdfDestCommand.fitBV:
        return null;
    }
    if (top == null) return null;
    final point = PdfPoint(left ?? 0, top);
    final rotation = page.rotation.index;
    return rotation == 0 ? point : point.rotate(rotation, page);
  }
}

/// Returns the total page count of a PDF without extracting text.
Future<int> _pdfPageCount(String filePath) async {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('File not found', filePath);
  }

  final document = await PdfDocument.openFile(filePath);
  try {
    return document.pages.length;
  } finally {
    await document.dispose();
  }
}

/// Runs PDF extraction with a timeout.
///
/// pdfrx uses FFI — must run on the main isolate. Despite the name
/// (`InIsolate`), this runs on the main isolate due to FFI constraints.
/// The name is kept for API compatibility.
Future<ExtractedDocument> extractPdfInIsolate(String filePath) async {
  final cancelToken = ExtractionCancelToken();
  return _pdfExtractDocument(
    filePath,
    throwOnEmpty: true,
    cancelToken: cancelToken,
  ).timeout(
    _extractionTimeout,
    onTimeout: () {
      // Stop the abandoned extraction at the next page instead of letting
      // it read the rest of the book on the main isolate.
      cancelToken.cancelled = true;
      throw PdfTimeoutError(filePath);
    },
  );
}

/// Extracts a page range with a timeout.
///
/// pdfrx uses FFI — must run on the main isolate. [startPage] and
/// [endPage] are 0-based inclusive indices.
Future<PageRangeResult> extractPdfPagesInIsolate(
  String filePath,
  int startPage,
  int endPage,
) async {
  final request = _PageRangeRequest(
    filePath: filePath,
    startPage: startPage,
    endPage: endPage,
  );
  final cancelToken = ExtractionCancelToken();
  return _pdfExtractPages(request, cancelToken).timeout(
    _extractionTimeout,
    onTimeout: () {
      // Cancel cleanly: the abandoned loop stops at the next page boundary
      // instead of burning the main isolate while the retry runs (BK-7).
      cancelToken.cancelled = true;
      throw PdfTimeoutError(filePath);
    },
  );
}

/// Returns total page count with a timeout.
///
/// pdfrx uses FFI — must run on the main isolate.
Future<int> pdfPageCountInIsolate(String filePath) async {
  return _pdfPageCount(filePath).timeout(
    const Duration(seconds: 10),
    onTimeout: () => throw PdfTimeoutError(filePath),
  );
}
