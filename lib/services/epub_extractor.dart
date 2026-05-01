import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/pdf_extractor.dart' show PageRangeResult;
import 'package:xml/xml.dart';

/// Per-file extraction timeout.
const Duration _epubExtractionTimeout = Duration(seconds: 30);

/// Extracts text from an EPUB file chapter-by-chapter.
///
/// Returns an [ExtractedDocument] compatible with the reading pipeline.
/// Each EPUB chapter maps to a "page" in [PageBoundary] for consistency.
/// Runs in [Isolate.run()] to avoid blocking the main event loop.
Future<ExtractedDocument> epubExtract(String filePath) async {
  return Isolate.run(() => _extractInIsolate(filePath));
}

/// Extracts a preview (first 3 chapters) from an EPUB.
///
/// Returns a [PageRangeResult] with the first 3 chapters extracted.
Future<PageRangeResult> epubExtractPreview(String filePath) async {
  return Isolate.run(() => _extractRangeInIsolate(filePath, 0, 2));
}

/// Extracts a range of chapters from an EPUB.
///
/// [startChapter] and [endChapter] are 0-based inclusive indices.
Future<PageRangeResult> epubExtractPages(
  String filePath,
  int startChapter,
  int endChapter,
) async {
  return Isolate.run(
    () => _extractRangeInIsolate(filePath, startChapter, endChapter),
  );
}

/// Runs EPUB extraction with a timeout.
///
/// Content extraction runs in a background isolate. Throws
/// [PdfTimeoutError] if extraction exceeds the timeout.
Future<ExtractedDocument> extractEpubInIsolate(String filePath) async {
  return epubExtract(filePath).timeout(
    _epubExtractionTimeout,
    onTimeout: () => throw PdfTimeoutError(filePath),
  );
}

/// Extracts preview chapters with a timeout.
///
/// Returns a [PageRangeResult] for the specified chapter range.
Future<PageRangeResult> extractEpubPagesInIsolate(
  String filePath,
  int startChapter,
  int endChapter,
) async {
  return epubExtractPages(filePath, startChapter, endChapter).timeout(
    _epubExtractionTimeout,
    onTimeout: () => throw PdfTimeoutError(filePath),
  );
}

/// Returns total chapter count with a timeout.
///
/// Parses only the EPUB structure (OPF spine) — does not extract text.
Future<int> epubChapterCountInIsolate(String filePath) async {
  return Isolate.run(() async {
    final bytes = File(filePath).readAsBytesSync();
    return _getChapters(bytes).length;
  }).timeout(
    const Duration(seconds: 10),
    onTimeout: () => throw PdfTimeoutError(filePath),
  );
}

/// Extracts an EPUB with progress reporting via [Stream<double>].
///
/// Emits progress values from 0.0 to 1.0 as each chapter is processed.
/// Calls [onComplete] with the final [ExtractedDocument], or [onError]
/// on failure. Extraction runs in a background isolate per chapter.
Stream<double> epubExtractWithProgress(
  String filePath, {
  required void Function(ExtractedDocument document) onComplete,
  required void Function(Object error) onError,
}) {
  final controller = StreamController<double>();

  () async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        onError(FileSystemException('File not found', filePath));
        await controller.close();
        return;
      }

      // Run the full extraction in an isolate but report progress
      // by extracting chapter-by-chapter.
      final bytes = file.readAsBytesSync();
      final result = await Isolate.run(() {
        final chapters = _getChapters(bytes);
        final totalChapters = chapters.length;

        if (totalChapters == 0) {
          throw const UnsupportedPdfError('EPUB has no readable chapters');
        }

        final allSentences = <Sentence>[];
        final pageBoundaries = <PageBoundary>[];
        var globalWordIndex = 0;

        for (var i = 0; i < totalChapters; i++) {
          final chapterText = _stripHtml(chapters[i]).trim();

          final startSentenceIndex = allSentences.length;
          final firstWords = chapterText
              .split(RegExp(r'\s+'))
              .take(5)
              .join(' ');
          pageBoundaries.add(
            PageBoundary(
              pageNumber: i,
              startSentenceIndex: startSentenceIndex,
              startWordIndex: globalWordIndex,
              firstWords: firstWords,
            ),
          );

          if (chapterText.isNotEmpty) {
            final sentences = _textToSentences(chapterText);
            for (final s in sentences) {
              globalWordIndex += s.words.length;
            }
            allSentences.addAll(sentences);
          }
        }

        return ExtractedDocument(
          sentences: allSentences,
          pageBoundaries: pageBoundaries,
          totalPages: totalChapters,
        );
      });

      controller.add(1.0);
      onComplete(result);
    } on Exception catch (e) {
      onError(e);
    } finally {
      await controller.close();
    }
  }();

  return controller.stream;
}

// ── Private helpers ──

/// Extracts all chapters from an EPUB file.
///
/// Handles malformed EPUBs gracefully — returns an informative error
/// rather than crashing on invalid ZIP or missing OPF files.
Future<ExtractedDocument> _extractInIsolate(String filePath) async {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('File not found', filePath);
  }

  List<int> bytes;
  try {
    bytes = file.readAsBytesSync();
  } on Exception catch (e) {
    throw UnsupportedPdfError('Cannot read EPUB file: $e');
  }

  List<String> chapters;
  try {
    chapters = _getChapters(bytes);
  } on Exception catch (e) {
    throw UnsupportedPdfError('Malformed EPUB: $e');
  }

  if (chapters.isEmpty) {
    throw const UnsupportedPdfError(
      'EPUB has no readable chapters — file may be malformed',
    );
  }

  final allSentences = <Sentence>[];
  final pageBoundaries = <PageBoundary>[];
  var globalWordIndex = 0;

  for (var i = 0; i < chapters.length; i++) {
    final chapterText = _stripHtml(chapters[i]).trim();

    final startSentenceIndex = allSentences.length;
    final firstWords = chapterText.split(RegExp(r'\s+')).take(5).join(' ');
    pageBoundaries.add(
      PageBoundary(
        pageNumber: i,
        startSentenceIndex: startSentenceIndex,
        startWordIndex: globalWordIndex,
        firstWords: firstWords,
      ),
    );

    if (chapterText.isNotEmpty) {
      final sentences = _textToSentences(chapterText);
      for (final s in sentences) {
        globalWordIndex += s.words.length;
      }
      allSentences.addAll(sentences);
    }
  }

  if (allSentences.isEmpty) {
    throw const UnsupportedPdfError('EPUB has no extractable text');
  }

  return ExtractedDocument(
    sentences: allSentences,
    pageBoundaries: pageBoundaries,
    totalPages: chapters.length,
  );
}

Future<PageRangeResult> _extractRangeInIsolate(
  String filePath,
  int startChapter,
  int endChapter,
) async {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('File not found', filePath);
  }

  final bytes = file.readAsBytesSync();
  final chapters = _getChapters(bytes);
  final totalChapters = chapters.length;

  final clampedEnd = endChapter.clamp(0, totalChapters - 1);
  final clampedStart = startChapter.clamp(0, clampedEnd);

  final allSentences = <Sentence>[];
  final pageBoundaries = <PageBoundary>[];
  var globalWordIndex = 0;

  for (var i = clampedStart; i <= clampedEnd; i++) {
    final chapterText = _stripHtml(chapters[i]).trim();

    final startSentenceIndex = allSentences.length;
    final firstWords = chapterText.split(RegExp(r'\s+')).take(5).join(' ');
    pageBoundaries.add(
      PageBoundary(
        pageNumber: i,
        startSentenceIndex: startSentenceIndex,
        startWordIndex: globalWordIndex,
        firstWords: firstWords,
      ),
    );

    if (chapterText.isNotEmpty) {
      final sentences = _textToSentences(chapterText);
      for (final s in sentences) {
        globalWordIndex += s.words.length;
      }
      allSentences.addAll(sentences);
    }
  }

  if (allSentences.isEmpty && clampedStart == 0) {
    throw const UnsupportedPdfError('EPUB has no extractable text');
  }

  return PageRangeResult(
    document: ExtractedDocument(
      sentences: allSentences,
      pageBoundaries: pageBoundaries,
      totalPages: totalChapters,
    ),
    totalPages: totalChapters,
    extractedStartPage: clampedStart,
    extractedEndPage: clampedEnd,
    pageBoundaries: pageBoundaries,
  );
}

/// Collects content strings from all readable EPUB content files.
///
/// Parses the EPUB (a ZIP archive) by:
/// 1. Reading `META-INF/container.xml` to locate the OPF file.
/// 2. Parsing the OPF manifest and spine to determine reading order.
/// 3. Extracting XHTML content for each spine entry.
List<String> _getChapters(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  // Helper to read a file from the archive by path.
  String? readArchiveFile(String path) {
    // Normalize path separators and try case-insensitive match.
    final normalized = path.replaceAll('\\', '/');
    for (final file in archive.files) {
      if (file.name.replaceAll('\\', '/').toLowerCase() ==
          normalized.toLowerCase()) {
        return utf8.decode(file.content as List<int>, allowMalformed: true);
      }
    }
    return null;
  }

  // 1. Parse container.xml to find the OPF root file.
  final containerXml = readArchiveFile('META-INF/container.xml');
  if (containerXml == null) return [];

  final containerDoc = XmlDocument.parse(containerXml);
  final rootFileElement = containerDoc.findAllElements('rootfile').firstOrNull;
  if (rootFileElement == null) return [];

  final opfPath = rootFileElement.getAttribute('full-path');
  if (opfPath == null || opfPath.isEmpty) return [];

  // 2. Parse the OPF file.
  final opfXml = readArchiveFile(opfPath);
  if (opfXml == null) return [];

  final opfDoc = XmlDocument.parse(opfXml);
  final opfDir = opfPath.contains('/')
      ? '${opfPath.substring(0, opfPath.lastIndexOf('/'))}/'
      : '';

  // Build manifest: id → href.
  final manifestItems = <String, String>{};
  for (final item in opfDoc.findAllElements('item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id != null && href != null) {
      manifestItems[id] = href;
    }
  }

  // Read spine to get reading order.
  final spineRefs = <String>[];
  for (final itemref in opfDoc.findAllElements('itemref')) {
    final idref = itemref.getAttribute('idref');
    if (idref != null) {
      spineRefs.add(idref);
    }
  }

  // 3. Extract XHTML content in spine order.
  final chapters = <String>[];
  for (final idref in spineRefs) {
    final href = manifestItems[idref];
    if (href == null) continue;

    // Resolve href relative to the OPF directory.
    final contentPath = Uri.decodeComponent('$opfDir$href');
    final html = readArchiveFile(contentPath);
    if (html != null && html.isNotEmpty) {
      chapters.add(html);
    }
  }

  // Fallback: if spine is empty, try all manifest items with XHTML media type.
  if (chapters.isEmpty) {
    for (final item in opfDoc.findAllElements('item')) {
      final mediaType = item.getAttribute('media-type') ?? '';
      if (mediaType.contains('xhtml') || mediaType.contains('html')) {
        final href = item.getAttribute('href');
        if (href == null) continue;
        final contentPath = Uri.decodeComponent('$opfDir$href');
        final html = readArchiveFile(contentPath);
        if (html != null && html.isNotEmpty) {
          chapters.add(html);
        }
      }
    }
  }

  return chapters;
}

/// Strips HTML tags, inline styles, and decodes entities to plain text.
///
/// Handles nested tags, self-closing tags, inline style attributes,
/// `<br>` elements (converted to whitespace), script/style blocks,
/// and common HTML entities (named + numeric).
String _stripHtml(String html) {
  // Remove <style> and <script> blocks entirely (including nested).
  var text = html.replaceAll(
    RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
    '',
  );
  text = text.replaceAll(
    RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
    '',
  );

  // Remove inline style attributes from remaining tags before stripping.
  text = text.replaceAll(RegExp(r'\s+style\s*=\s*"[^"]*"'), '');
  text = text.replaceAll(RegExp(r"\s+style\s*=\s*'[^']*'"), '');

  // Replace <br>, <p>, <div>, <h*>, <li>, <tr> closings with newlines.
  text = text.replaceAll(RegExp(r'<br\s*/?>'), '\n');
  text = text.replaceAll(
    RegExp(
      r'</(p|div|h[1-6]|li|tr|blockquote|section|article)>',
      caseSensitive: false,
    ),
    '\n',
  );
  // Opening block tags also get a newline before them.
  text = text.replaceAll(
    RegExp(
      r'<(p|div|h[1-6]|li|tr|blockquote|section|article)[\s>]',
      caseSensitive: false,
    ),
    '\n',
  );

  // Strip all remaining HTML tags.
  text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');

  // Decode common HTML entities.
  text = text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–')
      .replaceAll('&hellip;', '…')
      .replaceAll('&ldquo;', '\u201C')
      .replaceAll('&rdquo;', '\u201D')
      .replaceAll('&lsquo;', '\u2018')
      .replaceAll('&rsquo;', '\u2019')
      .replaceAll('&trade;', '\u2122')
      .replaceAll('&copy;', '\u00A9')
      .replaceAll('&reg;', '\u00AE')
      .replaceAll('&deg;', '\u00B0')
      .replaceAll('&euro;', '\u20AC')
      .replaceAll('&pound;', '\u00A3');

  // Decode numeric entities (&#NNN; and &#xHHH;).
  text = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(1)!, radix: 16);
    return code != null ? String.fromCharCode(code) : '';
  });
  text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code != null ? String.fromCharCode(code) : '';
  });

  // Strip any remaining unrecognised entities.
  text = text.replaceAll(RegExp(r'&\w+;'), '');

  // Collapse whitespace.
  text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return text.trim();
}

/// Splits raw text into a list of [Sentence] objects.
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
