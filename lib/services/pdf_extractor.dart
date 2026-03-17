import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:pdfrx/pdfrx.dart';
import 'package:speedy_boy/core/logger.dart';
import 'package:speedy_boy/services/models.dart';

/// Per-file extraction timeout.
const Duration _extractionTimeout = Duration(seconds: 30);

/// Number of pages extracted in the "preview" phase.
const int previewPageCount = 3;

/// Maximum extra pages to probe when the initial preview pages yield no text.
/// Handles books whose front matter (cover, title, copyright, TOC) is
/// image-only — the real text often starts a few pages later.
const int _maxProbePages = 10;

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

/// Extracts text from a PDF file page-by-page.
/// Records [PageBoundary] markers for reading range support.
/// pdfrx uses FFI — must run on the main isolate.
Future<ExtractedDocument> pdfExtract(String filePath) async {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('File not found', filePath);
  }

  final document = await PdfDocument.openFile(filePath);

  try {
    final totalPages = document.pages.length;
    final allSentences = <Sentence>[];
    final pageBoundaries = <PageBoundary>[];
    var globalWordIndex = 0;

    for (var i = 0; i < totalPages; i++) {
      final pageText = await document.pages[i].loadText();
      final trimmed = pageText?.fullText.trim() ?? '';

      // Record page boundary before adding sentences.
      final startSentenceIndex = allSentences.length;
      final firstWords = trimmed.split(RegExp(r'\s+')).take(5).join(' ');
      pageBoundaries.add(
        PageBoundary(
          pageNumber: i,
          startSentenceIndex: startSentenceIndex,
          startWordIndex: globalWordIndex,
          firstWords: firstWords,
        ),
      );

      if (trimmed.isNotEmpty) {
        final pageSentences = _textToSentences(trimmed);
        for (final s in pageSentences) {
          globalWordIndex += s.words.length;
        }
        allSentences.addAll(pageSentences);
      }
    }

    if (allSentences.isEmpty) {
      throw const UnsupportedPdfError('Image-only PDF — no extractable text');
    }

    return ExtractedDocument(
      sentences: allSentences,
      pageBoundaries: pageBoundaries,
      totalPages: totalPages,
    );
  } finally {
    await document.dispose();
  }
}

/// Extracts text from a specific page range of a PDF.
/// [startPage] and [endPage] are 0-based inclusive indices.
/// Also records page boundaries for reading range support.
Future<PageRangeResult> _pdfExtractPages(_PageRangeRequest request) async {
  final file = File(request.filePath);
  if (!file.existsSync()) {
    throw FileSystemException('File not found', request.filePath);
  }

  final document = await PdfDocument.openFile(request.filePath);

  try {
    final totalPages = document.pages.length;
    final clampedEnd = request.endPage.clamp(0, totalPages - 1);
    final clampedStart = request.startPage.clamp(0, clampedEnd);

    final allSentences = <Sentence>[];
    final pageBoundaries = <PageBoundary>[];
    var globalWordIndex = 0;

    // Effective end page — may be extended if front matter is blank.
    var effectiveEnd = clampedEnd;

    for (var i = clampedStart; i <= effectiveEnd; i++) {
      final pageText = await document.pages[i].loadText();
      final trimmed = pageText?.fullText.trim() ?? '';

      // Record page boundary before adding sentences
      final startSentenceIndex = allSentences.length;
      final firstWords = trimmed.split(RegExp(r'\s+')).take(5).join(' ');
      pageBoundaries.add(
        PageBoundary(
          pageNumber: i,
          startSentenceIndex: startSentenceIndex,
          startWordIndex: globalWordIndex,
          firstWords: firstWords,
        ),
      );

      if (trimmed.isNotEmpty) {
        final pageSentences = _textToSentences(trimmed);
        for (final s in pageSentences) {
          globalWordIndex += s.words.length;
        }
        allSentences.addAll(pageSentences);
      }

      // If we've exhausted the original range with no text and it was
      // a preview starting at page 0, probe up to _maxProbePages extra
      // pages before giving up. This handles books whose front matter
      // (cover, title, copyright, dedication) is image-only.
      if (i == clampedEnd &&
          allSentences.isEmpty &&
          clampedStart == 0 &&
          effectiveEnd == clampedEnd) {
        final probeLimit = math.min(
          clampedEnd + _maxProbePages,
          totalPages - 1,
        );
        if (probeLimit > clampedEnd) {
          appLog(
            'pdf_extractor',
            'No text in pages 0–$clampedEnd, probing up to page $probeLimit',
          );
          effectiveEnd = probeLimit;
        }
      }
    }

    if (allSentences.isEmpty && clampedStart == 0) {
      throw const UnsupportedPdfError('Image-only PDF — no extractable text');
    }

    return PageRangeResult(
      document: ExtractedDocument(
        sentences: allSentences,
        pageBoundaries: pageBoundaries,
        totalPages: totalPages,
      ),
      totalPages: totalPages,
      extractedStartPage: clampedStart,
      extractedEndPage: effectiveEnd,
      pageBoundaries: pageBoundaries,
    );
  } finally {
    await document.dispose();
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
/// pdfrx uses FFI — must run on the main isolate.
Future<ExtractedDocument> extractPdfInIsolate(String filePath) async {
  return pdfExtract(filePath).timeout(
    _extractionTimeout,
    onTimeout: () => throw PdfTimeoutError(filePath),
  );
}

/// Extracts a page range with a timeout.
/// pdfrx uses FFI — must run on the main isolate.
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
  return _pdfExtractPages(request).timeout(
    _extractionTimeout,
    onTimeout: () => throw PdfTimeoutError(filePath),
  );
}

/// Returns total page count with a timeout.
/// pdfrx uses FFI — must run on the main isolate.
Future<int> pdfPageCountInIsolate(String filePath) async {
  return _pdfPageCount(filePath).timeout(
    const Duration(seconds: 10),
    onTimeout: () => throw PdfTimeoutError(filePath),
  );
}

/// Splits raw text into a list of Sentence objects.
List<Sentence> _textToSentences(String text) {
  final sentencePattern = RegExp(r'(?<=[.!?])\s+');
  final rawSentences = text.split(sentencePattern);
  final sentences = <Sentence>[];

  for (final raw in rawSentences) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;

    final words = trimmed
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isNotEmpty) {
      sentences.add(Sentence(words: words));
    }
  }

  return sentences;
}
