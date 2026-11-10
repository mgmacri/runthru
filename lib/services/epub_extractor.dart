import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:runthru/core/text_segmentation.dart';
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
            _appendChapter(allSentences, sentences);
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
      _appendChapter(allSentences, sentences);
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
      _appendChapter(allSentences, sentences);
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

  // Build manifest: id → href. The EPUB 3 navigation document (the table
  // of contents, `properties="nav"`) is not body text: reading it flashes
  // "Chapter One … Table of Contents" before the book starts.
  final manifestItems = <String, String>{};
  final navIds = <String>{};
  for (final item in opfDoc.findAllElements('item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id != null && href != null) {
      manifestItems[id] = href;
      final properties = (item.getAttribute('properties') ?? '').split(' ');
      if (properties.contains('nav')) navIds.add(id);
    }
  }

  // Read spine to get reading order. Skip the nav document and items the
  // publisher marked `linear="no"` (auxiliary content outside reading order).
  final spineRefs = <String>[];
  for (final itemref in opfDoc.findAllElements('itemref')) {
    final idref = itemref.getAttribute('idref');
    if (idref == null || navIds.contains(idref)) continue;
    if (itemref.getAttribute('linear')?.toLowerCase() == 'no') continue;
    spineRefs.add(idref);
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

  // Drop <head> so the document <title> is not read as body text.
  text = text.replaceAll(
    RegExp(r'<head[\s>][\s\S]*?</head>', caseSensitive: false),
    '',
  );

  // Remove inline style attributes from remaining tags before stripping.
  text = text.replaceAll(RegExp(r'\s+style\s*=\s*"[^"]*"'), '');
  text = text.replaceAll(RegExp(r"\s+style\s*=\s*'[^']*'"), '');

  // The source file's own line wrapping is not structure: collapse it so
  // only block elements below create paragraph breaks.
  text = text.replaceAll(RegExp(r'\s+'), ' ');

  // <br> is a line break inside a paragraph (plain whitespace for reading);
  // block closings end a paragraph (a blank line).
  text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(
    RegExp(
      r'</(p|div|h[1-6]|li|tr|blockquote|section|article)>',
      caseSensitive: false,
    ),
    '\n\n',
  );
  // Opening block tags become a newline. Consume the whole tag, attributes
  // included: matching only `<p ` used to leave `class="x">` behind, and the
  // generic strip below could no longer see it as a tag.
  text = text.replaceAll(
    RegExp(
      r'<(p|div|h[1-6]|li|tr|blockquote|section|article)(\s[^>]*)?>',
      caseSensitive: false,
    ),
    '\n\n',
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

  // Collapse whitespace, keeping paragraph breaks as single blank lines.
  text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
  text = text.replaceAll(RegExp(r' *\n *'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return text.trim();
}

/// Appends one spine file's sentences.
///
/// Scanned-book EPUBs split files by print page, so a sentence can run
/// across a file boundary ("…before building and" | "crashing over…").
/// When the new file opens lowercase and the previous text did not end a
/// sentence, the opening sentence continues the previous paragraph rather
/// than starting a new one.
void _appendChapter(List<Sentence> all, List<Sentence> chapter) {
  if (all.isNotEmpty && chapter.isNotEmpty) {
    final previous = all.last.words.isEmpty ? '' : all.last.words.last;
    final first = chapter.first;
    final opener = first.words.isEmpty ? '' : first.words.first;
    if (opener.isNotEmpty &&
        _startsLowercase.hasMatch(opener) &&
        !_endsSentence.hasMatch(previous)) {
      chapter = [Sentence(words: first.words), ...chapter.skip(1)];
    }
  }
  all.addAll(chapter);
}

final RegExp _startsLowercase = RegExp(r'^[\p{Ll}]', unicode: true);
final RegExp _endsSentence = RegExp('[.!?\u2026][\u201D\u2019"\')\\]]*\$');

/// Splits stripped chapter text into sentences with paragraph starts.
List<Sentence> _textToSentences(String text) => textToSentences(text);

/// The EPUB's own title (`dc:title` in its package file), or null.
///
/// Reads only `container.xml` and the OPF, never chapter content, in a
/// background isolate. Used for library and reader titles instead of the
/// file name ("The Lighthouse Keeper's Ledger", not "lighthouse.epub").
Future<String?> epubTitle(String filePath) async {
  try {
    return await Isolate.run(() {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
      String? read(String path) {
        final want = path.replaceAll('\\', '/').toLowerCase();
        for (final f in archive.files) {
          if (f.name.replaceAll('\\', '/').toLowerCase() == want) {
            return utf8.decode(f.content as List<int>, allowMalformed: true);
          }
        }
        return null;
      }

      final container = read('META-INF/container.xml');
      if (container == null) return null;
      final opfPath = XmlDocument.parse(
        container,
      ).findAllElements('rootfile').firstOrNull?.getAttribute('full-path');
      if (opfPath == null) return null;
      final opf = read(opfPath);
      if (opf == null) return null;
      final title = XmlDocument.parse(opf)
          .findAllElements('*')
          .where((e) => e.name.local == 'title')
          .map((e) => e.innerText.replaceAll(RegExp(r'\s+'), ' ').trim())
          .firstWhere((t) => t.isNotEmpty, orElse: () => '');
      return title.isEmpty ? null : title;
    }).timeout(const Duration(seconds: 5));
  } on Object {
    return null;
  }
}
