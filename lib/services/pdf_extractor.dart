import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:speedy_boy/services/models.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Per-file extraction timeout.
const Duration _extractionTimeout = Duration(seconds: 30);

/// Number of pages extracted in the "preview" phase.
const int previewPageCount = 3;

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

/// Top-level function for Isolate.run() — extracts text from PDF.
/// Must be top-level or static (Dart Isolate requirement).
/// Extracts page-by-page and records [PageBoundary] markers.
ExtractedDocument pdfExtract(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('File not found', filePath);
  }

  final bytes = file.readAsBytesSync();
  final document = PdfDocument(inputBytes: bytes);

  try {
    final totalPages = document.pages.count;
    final allSentences = <Sentence>[];
    final pageBoundaries = <PageBoundary>[];
    var globalWordIndex = 0;

    for (var i = 0; i < totalPages; i++) {
      final extractor = PdfTextExtractor(document);
      final text =
          extractor.extractText(startPageIndex: i, endPageIndex: i);
      final trimmed = text.trim();

      // Record page boundary before adding sentences.
      final startSentenceIndex = allSentences.length;
      final firstWords = trimmed.split(RegExp(r'\s+')).take(5).join(' ');
      pageBoundaries.add(PageBoundary(
        pageNumber: i,
        startSentenceIndex: startSentenceIndex,
        startWordIndex: globalWordIndex,
        firstWords: firstWords,
      ));

      if (trimmed.isNotEmpty) {
        final pageSentences = _textToSentences(trimmed);
        for (final s in pageSentences) {
          globalWordIndex += s.words.length;
        }
        allSentences.addAll(pageSentences);
      }
    }

    if (allSentences.isEmpty) {
      throw const UnsupportedPdfError(
        'Image-only PDF — no extractable text',
      );
    }

    return ExtractedDocument(
      sentences: allSentences,
      pageBoundaries: pageBoundaries,
      totalPages: totalPages,
    );
  } finally {
    document.dispose();
  }
}

/// Extracts text from a specific page range of a PDF.
/// [startPage] and [endPage] are 0-based inclusive indices.
/// Also records page boundaries for reading range support.
PageRangeResult _pdfExtractPages(_PageRangeRequest request) {
  final file = File(request.filePath);
  if (!file.existsSync()) {
    throw FileSystemException('File not found', request.filePath);
  }

  final bytes = file.readAsBytesSync();
  final document = PdfDocument(inputBytes: bytes);

  try {
    final totalPages = document.pages.count;
    final clampedEnd = request.endPage.clamp(0, totalPages - 1);
    final clampedStart = request.startPage.clamp(0, clampedEnd);

    final allSentences = <Sentence>[];
    final pageBoundaries = <PageBoundary>[];
    var globalWordIndex = 0;

    for (var i = clampedStart; i <= clampedEnd; i++) {
      final extractor = PdfTextExtractor(document);
      final text =
          extractor.extractText(startPageIndex: i, endPageIndex: i);
      final trimmed = text.trim();

      // Record page boundary before adding sentences
      final startSentenceIndex = allSentences.length;
      final firstWords = trimmed.split(RegExp(r'\s+')).take(5).join(' ');
      pageBoundaries.add(PageBoundary(
        pageNumber: i,
        startSentenceIndex: startSentenceIndex,
        startWordIndex: globalWordIndex,
        firstWords: firstWords,
      ));

      if (trimmed.isNotEmpty) {
        final pageSentences = _textToSentences(trimmed);
        for (final s in pageSentences) {
          globalWordIndex += s.words.length;
        }
        allSentences.addAll(pageSentences);
      }
    }

    if (allSentences.isEmpty && clampedStart == 0) {
      throw const UnsupportedPdfError(
        'Image-only PDF — no extractable text',
      );
    }

    return PageRangeResult(
      document: ExtractedDocument(
        sentences: allSentences,
        pageBoundaries: pageBoundaries,
        totalPages: totalPages,
      ),
      totalPages: totalPages,
      extractedStartPage: clampedStart,
      extractedEndPage: clampedEnd,
      pageBoundaries: pageBoundaries,
    );
  } finally {
    document.dispose();
  }
}

/// Returns the total page count of a PDF without extracting text.
int _pdfPageCount(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('File not found', filePath);
  }

  final bytes = file.readAsBytesSync();
  final document = PdfDocument(inputBytes: bytes);
  try {
    return document.pages.count;
  } finally {
    document.dispose();
  }
}

/// Runs PDF extraction in a separate Dart Isolate with a timeout.
Future<ExtractedDocument> extractPdfInIsolate(String filePath) async {
  return Isolate.run(() => pdfExtract(filePath)).timeout(
    _extractionTimeout,
    onTimeout: () => throw PdfTimeoutError(filePath),
  );
}

/// Extracts a page range in a separate Isolate with a timeout.
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
  return Isolate.run(() => _pdfExtractPages(request)).timeout(
    _extractionTimeout,
    onTimeout: () => throw PdfTimeoutError(filePath),
  );
}

/// Returns total page count in a separate Isolate.
Future<int> pdfPageCountInIsolate(String filePath) async {
  return Isolate.run(() => _pdfPageCount(filePath)).timeout(
    const Duration(seconds: 10),
    onTimeout: () => throw PdfTimeoutError(filePath),
  );
}

/// Splits raw text into a list of Sentence objects.
List<Sentence> _textToSentences(String text) {
  final sentencePattern = RegExp(
    r'(?<=[.!?])\s+',
  );
  final rawSentences = text.split(sentencePattern);
  final sentences = <Sentence>[];

  for (final raw in rawSentences) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;

    final words =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isNotEmpty) {
      sentences.add(Sentence(words: words));
    }
  }

  return sentences;
}
