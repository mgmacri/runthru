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
    return _openBook(bytes).spine.length;
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

      final bytes = file.readAsBytesSync();
      final result = await Isolate.run(() {
        final book = _openBook(bytes);
        if (book.spine.isEmpty) {
          throw const UnsupportedPdfError('EPUB has no readable chapters');
        }
        return _extractSpineRange(book, 0, book.spine.length - 1);
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

  _EpubBook book;
  try {
    book = _openBook(bytes);
  } on Exception catch (e) {
    throw UnsupportedPdfError('Malformed EPUB: $e');
  }

  if (book.spine.isEmpty) {
    throw const UnsupportedPdfError(
      'EPUB has no readable chapters — file may be malformed',
    );
  }

  final document = _extractSpineRange(book, 0, book.spine.length - 1);
  if (document.sentences.isEmpty) {
    throw const UnsupportedPdfError('EPUB has no extractable text');
  }
  return document;
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

  final book = _openBook(file.readAsBytesSync());
  final totalChapters = book.spine.length;

  final clampedEnd = endChapter.clamp(0, totalChapters - 1);
  final clampedStart = startChapter.clamp(0, clampedEnd);

  final document = _extractSpineRange(book, clampedStart, clampedEnd);

  if (document.sentences.isEmpty && clampedStart == 0) {
    throw const UnsupportedPdfError('EPUB has no extractable text');
  }

  return PageRangeResult(
    document: document,
    totalPages: totalChapters,
    extractedStartPage: clampedStart,
    extractedEndPage: clampedEnd,
    pageBoundaries: document.pageBoundaries,
  );
}

/// Extracts spine files [start]..[end] (inclusive) of [book].
///
/// Each spine file is one "page" ([PageBoundary]). Headings keep their
/// level, and every table-of-contents or landmark entry that points into
/// the range becomes an [OutlineEntry] at the word it points to (the
/// fragment's element, not just the file), so several chapters in one file
/// are found individually. Word and sentence indices are relative to the
/// range; [ExtractedDocument.merge] offsets them.
ExtractedDocument _extractSpineRange(_EpubBook book, int start, int end) {
  final allSentences = <Sentence>[];
  final pageBoundaries = <PageBoundary>[];
  final outline = <OutlineEntry>[];
  final sentenceOfMark = <int, int>{};
  var globalWordIndex = 0;

  for (var i = start; i <= end && i < book.spine.length; i++) {
    final file = book.spine[i];
    final entries = book.entriesFor(file.path);

    final cleaned = file.html.replaceAll(kReservedMarkChars, '');
    final marked = _insertAnchors(cleaned, entries);
    final chapterText = _stripHtml(marked).trim();
    final resolved = _resolveAnchors(_textToSentences(chapterText));
    final sentences = resolved.sentences;

    final fileSentenceStart = allSentences.length;
    final fileWordStart = globalWordIndex;
    final firstWords = sentences.expand((s) => s.words).take(5).join(' ');
    pageBoundaries.add(
      PageBoundary(
        pageNumber: i,
        startSentenceIndex: fileSentenceStart,
        startWordIndex: fileWordStart,
        firstWords: firstWords,
      ),
    );

    for (final s in sentences) {
      globalWordIndex += s.words.length;
    }
    _appendChapter(allSentences, sentences);

    // What the file says it is (`epub:type`, a Gutenberg boilerplate id, a
    // telling file name), for entries that carry no type of their own.
    final fileType = _fileType(file);
    // Titled entries (contents rows) in order; untitled marks (landmarks,
    // guide references, the file's own type) merged by word position.
    final titled = <OutlineEntry>[];
    final marks = <int, String>{};
    if (fileType != null) marks[0] = fileType;
    for (var k = 0; k < entries.length; k++) {
      final entry = entries[k];
      final word = resolved.anchorWord[k] ?? 0;
      final sentence = resolved.anchorSentence[k] ?? 0;
      if (entry.title.isEmpty) {
        final type = _joinTypes(marks[word], entry.type);
        if (type != null) marks[word] = type;
        sentenceOfMark[fileWordStart + word] = fileSentenceStart + sentence;
        continue;
      }
      titled.add(
        OutlineEntry(
          title: entry.title,
          startWordIndex: fileWordStart + word,
          startSentenceIndex: fileSentenceStart + sentence,
          depth: entry.depth,
          type: entry.type,
        ),
      );
    }
    sentenceOfMark[fileWordStart] ??= fileSentenceStart;
    for (final entry in titled) {
      // A mark at the same word describes this entry (the first one there).
      final word = entry.startWordIndex - fileWordStart;
      final type = _joinTypes(entry.type, marks.remove(word));
      outline.add(
        type == entry.type
            ? entry
            : OutlineEntry(
                title: entry.title,
                startWordIndex: entry.startWordIndex,
                startSentenceIndex: entry.startSentenceIndex,
                depth: entry.depth,
                type: type,
              ),
      );
    }
    for (final mark in marks.entries) {
      final word = fileWordStart + mark.key;
      outline.add(
        OutlineEntry(
          title: '',
          startWordIndex: word,
          startSentenceIndex: sentenceOfMark[word] ?? fileSentenceStart,
          type: mark.value,
        ),
      );
    }
  }

  // Entries of one file can arrive out of order (landmarks after contents).
  final order = <OutlineEntry, int>{
    for (var i = 0; i < outline.length; i++) outline[i]: i,
  };
  final ordered = List<OutlineEntry>.of(outline)
    ..sort((a, b) {
      final byWord = a.startWordIndex.compareTo(b.startWordIndex);
      if (byWord != 0) return byWord;
      // An untitled mark sorts before the titled entries at its word.
      if (a.title.isEmpty != b.title.isEmpty) return a.title.isEmpty ? -1 : 1;
      return order[a]!.compareTo(order[b]!);
    });

  return ExtractedDocument(
    sentences: allSentences,
    pageBoundaries: pageBoundaries,
    totalPages: book.spine.length,
    outline: ordered,
  );
}

/// One readable file of the book, in reading order.
class _SpineFile {
  const _SpineFile({
    required this.path,
    required this.idref,
    required this.html,
  });

  /// Archive path, normalised (see [_normalisePath]).
  final String path;

  /// The spine `idref` (manifest id) of the file.
  final String idref;

  /// Raw XHTML.
  final String html;
}

/// One entry of the book's own navigation: a table-of-contents row, a
/// landmark, or a guide reference.
class _NavEntry {
  const _NavEntry({
    required this.path,
    required this.title,
    this.fragment,
    this.depth = 0,
    this.type,
  });

  /// Normalised archive path of the target file.
  final String path;

  /// Element id inside the file, when the entry points into it.
  final String? fragment;

  /// Label ("Chapter I"); empty for landmarks, which only carry a [type].
  final String title;

  /// Nesting depth in the table of contents.
  final int depth;

  /// Structural type (`bodymatter`, `toc`, `copyright-page`…), if stated.
  final String? type;
}

/// An opened EPUB: readable files in order, and its navigation.
class _EpubBook {
  _EpubBook({required this.spine, required List<_NavEntry> nav}) {
    for (final entry in nav) {
      (_byPath[entry.path] ??= <_NavEntry>[]).add(entry);
    }
  }

  final List<_SpineFile> spine;
  final Map<String, List<_NavEntry>> _byPath = {};

  /// Navigation entries that point into the file at [path].
  List<_NavEntry> entriesFor(String path) => _byPath[path] ?? const [];
}

/// Resolves [href] (relative to [baseDir], which ends in `/` or is empty)
/// to a normalised archive path and an optional fragment.
({String path, String? fragment}) _resolveHref(String baseDir, String href) {
  var target = href.trim();
  String? fragment;
  final hash = target.indexOf('#');
  if (hash >= 0) {
    fragment = target.substring(hash + 1);
    target = target.substring(0, hash);
    if (fragment.isEmpty) fragment = null;
  }
  try {
    target = Uri.decodeComponent(target);
    if (fragment != null) fragment = Uri.decodeComponent(fragment);
  } on ArgumentError {
    // Malformed percent-encoding: use the href as written.
  }
  return (path: _normalisePath('$baseDir$target'), fragment: fragment);
}

/// Lower-cases, uses `/`, and resolves `.` and `..` segments, so the same
/// file is the same key however a reference spells it.
String _normalisePath(String path) {
  final out = <String>[];
  for (final part in path.replaceAll('\\', '/').split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(part);
  }
  return out.join('/').toLowerCase();
}

String _dirOf(String path) =>
    path.contains('/') ? '${path.substring(0, path.lastIndexOf('/'))}/' : '';

/// Opens an EPUB (a ZIP archive):
/// 1. `META-INF/container.xml` locates the package (OPF) file.
/// 2. The OPF manifest and spine give the reading order.
/// 3. The navigation document (EPUB 3), the NCX (EPUB 2) and the guide give
///    the table of contents and landmarks.
_EpubBook _openBook(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  final byPath = <String, ArchiveFile>{};
  for (final file in archive.files) {
    byPath[_normalisePath(file.name)] = file;
  }
  String? readArchiveFile(String normalisedPath) {
    final file = byPath[normalisedPath];
    if (file == null) return null;
    return utf8.decode(file.content as List<int>, allowMalformed: true);
  }

  _EpubBook empty() => _EpubBook(spine: const [], nav: const []);

  // 1. Parse container.xml to find the OPF root file.
  final containerXml = readArchiveFile('meta-inf/container.xml');
  if (containerXml == null) return empty();

  final containerDoc = XmlDocument.parse(containerXml);
  final rootFileElement = containerDoc.findAllElements('rootfile').firstOrNull;
  if (rootFileElement == null) return empty();

  final opfPath = rootFileElement.getAttribute('full-path');
  if (opfPath == null || opfPath.isEmpty) return empty();

  // 2. Parse the OPF file.
  final opfXml = readArchiveFile(_normalisePath(opfPath));
  if (opfXml == null) return empty();

  final opfDoc = XmlDocument.parse(opfXml);
  final opfDir = _dirOf(opfPath.replaceAll('\\', '/'));

  // Build manifest: id → href. The EPUB 3 navigation document (the table
  // of contents, `properties="nav"`) is not body text: reading it flashes
  // "Chapter One … Table of Contents" before the book starts.
  final manifestItems = <String, String>{};
  final navIds = <String>{};
  String? ncxId;
  for (final item in opfDoc.findAllElements('item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id != null && href != null) {
      manifestItems[id] = href;
      final properties = (item.getAttribute('properties') ?? '').split(' ');
      if (properties.contains('nav')) navIds.add(id);
      if (item.getAttribute('media-type') == 'application/x-dtbncx+xml') {
        ncxId ??= id;
      }
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
  final spineToc = opfDoc
      .findAllElements('spine')
      .firstOrNull
      ?.getAttribute('toc');
  if (spineToc != null && manifestItems.containsKey(spineToc)) {
    ncxId = spineToc;
  }

  // 3. Read XHTML content in spine order.
  final spine = <_SpineFile>[];
  for (final idref in spineRefs) {
    final href = manifestItems[idref];
    if (href == null) continue;

    // Resolve href relative to the OPF directory.
    final target = _resolveHref(opfDir, href);
    final html = readArchiveFile(target.path);
    if (html != null && html.isNotEmpty) {
      spine.add(_SpineFile(path: target.path, idref: idref, html: html));
    }
  }

  // Fallback: if spine is empty, try all manifest items with XHTML media type.
  if (spine.isEmpty) {
    for (final item in opfDoc.findAllElements('item')) {
      final mediaType = item.getAttribute('media-type') ?? '';
      if (mediaType.contains('xhtml') || mediaType.contains('html')) {
        final id = item.getAttribute('id') ?? '';
        if (navIds.contains(id)) continue;
        final href = item.getAttribute('href');
        if (href == null) continue;
        final target = _resolveHref(opfDir, href);
        final html = readArchiveFile(target.path);
        if (html != null && html.isNotEmpty) {
          spine.add(_SpineFile(path: target.path, idref: id, html: html));
        }
      }
    }
  }

  // 4. Navigation: contents and landmarks. Never fatal: a book with broken
  // navigation still reads, it just has no chapter list of its own.
  final nav = <_NavEntry>[];
  try {
    for (final id in navIds) {
      final href = manifestItems[id];
      if (href == null) continue;
      final target = _resolveHref(opfDir, href);
      final html = readArchiveFile(target.path);
      if (html != null) {
        nav.addAll(_parseNavDocument(html, _dirOf(target.path)));
      }
    }
    final hasContents = nav.any((e) => e.title.isNotEmpty);
    final ncxHref = ncxId == null ? null : manifestItems[ncxId];
    if (!hasContents && ncxHref != null) {
      final target = _resolveHref(opfDir, ncxHref);
      final xml = readArchiveFile(target.path);
      if (xml != null) nav.addAll(_parseNcx(xml, _dirOf(target.path)));
    }
    for (final reference in opfDoc.findAllElements('reference')) {
      final href = reference.getAttribute('href');
      final type = _guideType(reference.getAttribute('type'));
      if (href == null || type == null) continue;
      final target = _resolveHref(opfDir, href);
      nav.add(
        _NavEntry(
          path: target.path,
          fragment: target.fragment,
          title: '',
          type: type,
        ),
      );
    }
  } on Exception {
    // Keep whatever was read before the failure.
  }

  // Project Gutenberg wraps its header and licence in elements with fixed
  // ids, sometimes in files of their own and sometimes at the end of the
  // last chapter's file. Mark the elements, not the files.
  for (final file in spine) {
    for (final match in _pgBoilerplateId.allMatches(file.html)) {
      final id = match.group(1)!;
      nav.add(
        _NavEntry(
          path: file.path,
          fragment: id,
          title: '',
          type: id == 'pg-header'
              ? 'pg-header frontmatter'
              : 'pg-footer backmatter',
        ),
      );
    }
  }

  return _EpubBook(spine: spine, nav: nav);
}

/// Reads the EPUB 3 navigation document: the `toc` nav (nesting depth from
/// its lists) and the `landmarks` nav (types such as `bodymatter`).
///
/// Tokenised with regular expressions rather than an XML parser: real books
/// ship navigation documents with HTML entities and stray markup that a
/// strict parser rejects.
List<_NavEntry> _parseNavDocument(String html, String baseDir) {
  final entries = <_NavEntry>[];
  for (final nav in _navBlock.allMatches(html)) {
    final types = _epubTypes(nav.group(1) ?? '');
    final isLandmarks = types.contains('landmarks');
    final isContents = types.contains('toc') || types.isEmpty;
    if (!isLandmarks && !isContents) continue; // page-list and the like
    var depth = -1;
    for (final token in _navToken.allMatches(nav.group(2) ?? '')) {
      final text = token.group(0)!;
      if (text.startsWith('</')) {
        depth--;
        continue;
      }
      if (token.group(1) == null) {
        depth++; // <ol> or <ul>
        continue;
      }
      final attributes = token.group(1)!;
      final href = _attribute(attributes, 'href');
      if (href == null || href.isEmpty) continue;
      final target = _resolveHref(baseDir, href);
      if (isLandmarks) {
        final type = _structuralType(_epubTypes(attributes));
        if (type == null) continue;
        entries.add(
          _NavEntry(
            path: target.path,
            fragment: target.fragment,
            title: '',
            type: type,
          ),
        );
      } else {
        final title = _plainLabel(token.group(2) ?? '');
        if (title.isEmpty) continue;
        entries.add(
          _NavEntry(
            path: target.path,
            fragment: target.fragment,
            title: title,
            depth: depth < 0 ? 0 : depth,
          ),
        );
      }
    }
  }
  return entries;
}

/// Reads an EPUB 2 NCX `navMap`: nested `navPoint`s with a label and a
/// `content src`.
List<_NavEntry> _parseNcx(String xml, String baseDir) {
  final entries = <_NavEntry>[];
  final map = _ncxNavMap.firstMatch(xml)?.group(1);
  if (map == null) return entries;
  var depth = -1;
  String? label;
  for (final token in _ncxToken.allMatches(map)) {
    final text = token.group(0)!;
    if (text.startsWith('</')) {
      depth--;
    } else if (token.group(1) != null) {
      label ??= _plainLabel(token.group(1)!);
    } else if (token.group(2) != null) {
      final target = _resolveHref(baseDir, _decodeEntities(token.group(2)!));
      final title = label ?? '';
      label = null;
      if (title.isEmpty) continue;
      entries.add(
        _NavEntry(
          path: target.path,
          fragment: target.fragment,
          title: title,
          depth: depth < 0 ? 0 : depth,
        ),
      );
    } else {
      depth++; // <navPoint>
      label = null;
    }
  }
  return entries;
}

final RegExp _navBlock = RegExp(
  r'<nav\b([^>]*)>([\s\S]*?)</nav>',
  caseSensitive: false,
);
final RegExp _navToken = RegExp(
  r'<(?:ol|ul)\b[^>]*>|</(?:ol|ul)>|<a\b([^>]*)>([\s\S]*?)</a>',
  caseSensitive: false,
);
final RegExp _ncxNavMap = RegExp(
  r'<(?:\w+:)?navMap\b[^>]*>([\s\S]*?)</(?:\w+:)?navMap>',
  caseSensitive: false,
);
final RegExp _ncxToken = RegExp(
  r'<(?:\w+:)?navPoint\b[^>]*>|</(?:\w+:)?navPoint>'
  r'|<(?:\w+:)?text\b[^>]*>([\s\S]*?)</(?:\w+:)?text>'
  '|<(?:\\w+:)?content\\b[^>]*\\bsrc\\s*=\\s*["\']([^"\']*)["\']',
  caseSensitive: false,
);

/// The value of [name] in a tag's attribute text, or null.
String? _attribute(String attributes, String name) {
  final match = RegExp(
    '(?:^|\\s)${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')',
    caseSensitive: false,
  ).firstMatch(attributes);
  if (match == null) return null;
  return _decodeEntities(match.group(1) ?? match.group(2) ?? '');
}

/// The `epub:type` tokens of a tag's attribute text, lower-cased, with
/// vocabulary prefixes (`z3998:`, `se:`) removed.
Set<String> _epubTypes(String attributes) {
  final raw = _attribute(attributes, 'epub:type');
  if (raw == null) return const {};
  return {
    for (final token in raw.toLowerCase().split(RegExp(r'\s+')))
      if (token.isNotEmpty) token.substring(token.lastIndexOf(':') + 1),
  };
}

/// Structural types the reader understands. Anything else (`fiction`,
/// `signature`, publisher vocabularies) is dropped.
const Set<String> _knownTypes = {
  'frontmatter',
  'bodymatter',
  'backmatter',
  'cover',
  'titlepage',
  'halftitlepage',
  'copyright-page',
  'imprint',
  'colophon',
  'dedication',
  'epigraph',
  'toc',
  'loi',
  'lot',
  'foreword',
  'preface',
  'introduction',
  'prologue',
  'preamble',
  'chapter',
  'part',
  'volume',
  'division',
  'epilogue',
  'conclusion',
  'afterword',
  'appendix',
  'acknowledgments',
  'contributors',
  'other-credits',
  'endnotes',
  'bibliography',
  'glossary',
  'index',
  'about-author',
  'also-by',
  'pg-header',
  'pg-footer',
};

/// Other spellings of the known types (EPUB 2 guide values, older
/// vocabulary terms).
const Map<String, String> _typeAlias = {
  'title-page': 'titlepage',
  'half-title-page': 'halftitlepage',
  'halftitle': 'halftitlepage',
  'copyright': 'copyright-page',
  'acknowledgements': 'acknowledgments',
  'acknowledgement': 'acknowledgments',
  'acknowledgment': 'acknowledgments',
  'text': 'bodymatter',
  'start': 'bodymatter',
  'notes': 'endnotes',
  'rearnotes': 'endnotes',
  'footnotes': 'endnotes',
  'contents': 'toc',
  'subchapter': 'division',
};

/// The known structural types among [types], space-joined, or null.
String? _structuralType(Iterable<String> types) {
  final known = <String>{};
  for (final type in types) {
    final canonical = _typeAlias[type] ?? type;
    if (_knownTypes.contains(canonical)) known.add(canonical);
  }
  return known.isEmpty ? null : known.join(' ');
}

/// A guide reference type (`text`, `title-page`, `toc`…) as a known type.
String? _guideType(String? type) {
  if (type == null) return null;
  return _structuralType([type.toLowerCase().trim()]);
}

/// Joins two space-separated type lists, dropping duplicates.
String? _joinTypes(String? a, String? b) {
  final all = <String>{
    if (a != null) ...a.split(' '),
    if (b != null) ...b.split(' '),
  }..remove('');
  return all.isEmpty ? null : all.join(' ');
}

/// What a spine file says it is: `epub:type` on its `<body>` and first
/// `<section>`, or failing those a telling file name (`copyright.xhtml`,
/// `titlepage.xhtml`).
String? _fileType(_SpineFile file) {
  final types = <String>{};
  final body = _bodyTag.firstMatch(file.html);
  if (body != null) types.addAll(_epubTypes(body.group(1) ?? ''));
  final section = _sectionTag.firstMatch(file.html);
  if (section != null) types.addAll(_epubTypes(section.group(1) ?? ''));

  final stated = _structuralType(types);
  if (stated != null) return stated;

  final name = file.path.substring(file.path.lastIndexOf('/') + 1);
  final match = _tellingFileName.firstMatch(name);
  if (match == null) return null;
  final word = match.group(1)!.toLowerCase();
  return _structuralType([word.replaceAll('_', '-')]) ??
      _structuralType([word.replaceAll(RegExp('[-_]'), '')]);
}

final RegExp _bodyTag = RegExp(r'<body\b([^>]*)>', caseSensitive: false);
final RegExp _sectionTag = RegExp(r'<section\b([^>]*)>', caseSensitive: false);
final RegExp _pgBoilerplateId = RegExp(
  'id\\s*=\\s*["\'](pg-header|pg-footer)["\']',
);
final RegExp _tellingFileName = RegExp(
  r'^(cover|title[-_]?page|half[-_]?title[-_]?page|copyright(?:[-_]page)?'
  r'|imprint|colophon|dedication|epigraph|toc|contents|foreword|preface'
  r'|acknowledge?ments?|bibliography|glossary|index|endnotes|about[-_]author'
  r'|also[-_]by)(?:[-_.\d]|$)',
  caseSensitive: false,
);

/// A navigation label as plain text: tags removed, entities decoded,
/// whitespace collapsed.
String _plainLabel(String html) => _decodeEntities(
  html.replaceAll(RegExp(r'<[^>]+>'), ''),
).replaceAll(RegExp(r'\s+'), ' ').trim();

/// Start and end of an anchor mark: `\uE002<entry index>\uE003`.
const String _anchorOpen = '\uE002';
const String _anchorClose = '\uE003';
final RegExp _anchorMark = RegExp('$_anchorOpen(\\d+)$_anchorClose');

/// Marks where each navigation entry points inside [html].
///
/// An entry with a fragment gets a mark just after the opening tag of the
/// element with that id, so the mark rides on the element's first word
/// through tag stripping. Entries without a fragment (or whose element is
/// missing) point at the start of the file and need no mark.
String _insertAnchors(String html, List<_NavEntry> entries) {
  final inserts = <int, StringBuffer>{};
  for (var k = 0; k < entries.length; k++) {
    final fragment = entries[k].fragment;
    if (fragment == null) continue;
    final tag = RegExp(
      '<[a-zA-Z][^>]*\\s(?:id|name|xml:id)\\s*=\\s*["\']'
      '${RegExp.escape(fragment)}["\'][^>]*>',
    ).firstMatch(html);
    if (tag == null) continue;
    (inserts[tag.end] ??= StringBuffer()).write('$_anchorOpen$k$_anchorClose');
  }
  if (inserts.isEmpty) return html;
  final offsets = inserts.keys.toList()..sort();
  final out = StringBuffer();
  var cursor = 0;
  for (final offset in offsets) {
    out
      ..write(html.substring(cursor, offset))
      ..write(inserts[offset]);
    cursor = offset;
  }
  out.write(html.substring(cursor));
  return out.toString();
}

/// Removes anchor marks from segmented text and reports the word and
/// sentence each one landed on (relative to the file). A mark that stood
/// alone (its element held no text of its own) points at the next word.
({
  List<Sentence> sentences,
  Map<int, int> anchorWord,
  Map<int, int> anchorSentence,
})
_resolveAnchors(List<Sentence> raw) {
  final anchorWord = <int, int>{};
  final anchorSentence = <int, int>{};
  final out = <Sentence>[];
  final pending = <int>[];
  var wordCount = 0;

  void settle(int word) {
    for (final k in pending) {
      anchorWord[k] = word;
      anchorSentence[k] = out.length;
    }
    pending.clear();
  }

  for (final sentence in raw) {
    if (!sentence.words.any((w) => w.contains(_anchorOpen))) {
      settle(wordCount);
      out.add(sentence);
      wordCount += sentence.words.length;
      continue;
    }
    final words = <String>[];
    for (final word in sentence.words) {
      for (final mark in _anchorMark.allMatches(word)) {
        pending.add(int.parse(mark.group(1)!));
      }
      final clean = word
          .replaceAll(_anchorMark, '')
          .replaceAll(_anchorOpen, '')
          .replaceAll(_anchorClose, '');
      if (clean.isEmpty) continue;
      settle(wordCount + words.length);
      words.add(clean);
    }
    if (words.isEmpty) continue;
    out.add(
      Sentence(
        words: words,
        startsParagraph: sentence.startsParagraph,
        heading: sentence.heading,
      ),
    );
    wordCount += words.length;
  }
  // Marks after the last word point at the end of the file.
  settle(wordCount);
  return (
    sentences: out,
    anchorWord: anchorWord,
    anchorSentence: anchorSentence,
  );
}

/// Strips HTML tags, inline styles, and decodes entities to plain text.
///
/// Handles nested tags, self-closing tags, inline style attributes,
/// `<br>` elements (converted to whitespace), script/style blocks,
/// and common HTML entities (named + numeric).
///
/// Headings (`<h1>`–`<h6>`) and subtitles come out as paragraphs opened by
/// [headingMark], so they stay whole and keep their level. Reference
/// clutter that interrupts a sentence when read word by word is dropped:
/// footnote markers ("republic.¹"), print page numbers ("[Pg 12]").
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

  // Footnote references and print page markers sit inside sentences.
  // Anchor marks inside a removed element are kept.
  text = text.replaceAllMapped(_noteRef, _keepAnchors);
  text = text.replaceAllMapped(_pageMarker, _keepAnchors);
  text = text.replaceAllMapped(_pageBreak, _keepAnchors);
  text = text.replaceAllMapped(_superscript, (m) {
    final inner = (m.group(1) ?? '').replaceAll(RegExp(r'<[^>]+>'), '');
    final plain = inner.replaceAll(_anchorMark, '').trim();
    return _noteMarkerText.hasMatch(plain) ? _keepAnchors(m) : m.group(0)!;
  });

  // Remove inline style attributes from remaining tags before stripping.
  text = text.replaceAll(RegExp(r'\s+style\s*=\s*"[^"]*"'), '');
  text = text.replaceAll(RegExp(r"\s+style\s*=\s*'[^']*'"), '');

  // The source file's own line wrapping is not structure: collapse it so
  // only block elements below create paragraph breaks.
  text = text.replaceAll(RegExp(r'\s+'), ' ');

  // Headings keep their level; a subtitle paragraph is the lowest level, so
  // it reads as part of the heading it follows.
  text = text.replaceAllMapped(
    RegExp(r'<h([1-6])(\s[^>]*)?>', caseSensitive: false),
    (m) => '\n\n${headingMark(int.parse(m.group(1)!))}',
  );
  text = text.replaceAllMapped(
    _subtitleParagraph,
    (m) => '\n\n${headingMark(6)}',
  );

  // <br> is a line break inside a paragraph (plain whitespace for reading);
  // block closings end a paragraph (a blank line).
  text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(
    RegExp(
      r'</(p|div|h[1-6]|li|ul|ol|tr|td|th|table|caption|dd|dt|dl|blockquote|section|article|aside|header|footer|nav|main|figure|figcaption|pre|hr|hgroup)>',
      caseSensitive: false,
    ),
    '\n\n',
  );
  // Opening block tags become a newline. Consume the whole tag, attributes
  // included: matching only `<p ` used to leave `class="x">` behind, and the
  // generic strip below could no longer see it as a tag.
  text = text.replaceAll(
    RegExp(
      r'<(p|div|li|ul|ol|tr|td|th|table|caption|dd|dt|dl|blockquote|section|article|aside|header|footer|nav|main|figure|figcaption|pre|hr|hgroup)(\s[^>]*)?>',
      caseSensitive: false,
    ),
    '\n\n',
  );

  // Remaining tags are inline (<em>, <a>, <span>): they vanish without
  // adding a space, so "<em>Titanic</em>," stays "Titanic,".
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');

  text = _decodeEntities(text);

  text = tidyInlineSpacing(text);

  // Collapse whitespace, keeping paragraph breaks as single blank lines.
  text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
  text = text.replaceAll(RegExp(r' *\n *'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return text.trim();
}

/// Replaces a removed element with the anchor marks it contained.
String _keepAnchors(Match m) =>
    _anchorMark.allMatches(m.group(0)!).map((a) => a.group(0)!).join();

/// `<a epub:type="noteref">1</a>`: a footnote reference, and the
/// `backlink` arrow that returns from the note.
final RegExp _noteRef = RegExp(
  '<a\\b[^>]*epub:type\\s*=\\s*["\'][^"\']*(?:noteref|backlink)'
  '[^"\']*["\'][^>]*>'
  r'[\s\S]*?</a>',
  caseSensitive: false,
);

/// `<span class="pagenum">[Pg 12]</span>`: a print page number.
final RegExp _pageMarker = RegExp(
  '<(span|a|div|p)\\b[^>]*class\\s*=\\s*["\'][^"\']*'
  r'\b(?:pagenum|pageno|page-number|pagebreak|x-ebookmaker-pageno)\b'
  '[^"\']*["\'][^>]*>'
  r'[\s\S]{0,200}?</\1>',
  caseSensitive: false,
);

/// `<span epub:type="pagebreak" title="12"/>` (with or without content).
final RegExp _pageBreak = RegExp(
  '<(\\w+)\\b[^>]*epub:type\\s*=\\s*["\'][^"\']*pagebreak[^"\']*["\'][^>]*'
  r'(?:/>|>[\s\S]{0,80}?</\1>)',
  caseSensitive: false,
);

/// Any superscript; only note markers among them are removed.
final RegExp _superscript = RegExp(
  r'<sup\b[^>]*>([\s\S]{0,120}?)</sup>',
  caseSensitive: false,
);

/// The text of a note marker: "1", "[12]", "(3)", "*", "†", "a".
final RegExp _noteMarkerText = RegExp(
  r'^[\[(]?\s*(?:\d{1,4}|[*†‡§¶]+|[a-z])\s*[\])]?$',
);

/// `<p epub:type="subtitle">` / `<p role="doc-subtitle">`.
final RegExp _subtitleParagraph = RegExp(
  '<p\\b[^>]*(?:role\\s*=\\s*["\']doc-subtitle["\']'
  '|epub:type\\s*=\\s*["\'][^"\']*subtitle[^"\']*["\'])[^>]*>',
  caseSensitive: false,
);

/// Decodes the common named entities and all numeric ones; unknown named
/// entities are dropped.
String _decodeEntities(String input) {
  var text = input
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
  return text.replaceAll(RegExp(r'&\w+;'), '');
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
        !first.isHeading &&
        !all.last.isHeading &&
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

/// What an EPUB says about itself in its package file.
class EpubInfo {
  /// Creates EPUB package info.
  const EpubInfo({this.title, this.author});

  /// `dc:title`, or null when the package gives none.
  final String? title;

  /// The first `dc:creator`, or null when the package gives none.
  final String? author;
}

/// The EPUB's own title and author (`dc:title`, `dc:creator`), or null when
/// the file cannot be read as an EPUB.
///
/// Reads only `container.xml` and the OPF, never chapter content, in a
/// background isolate. Used for library and reader titles instead of the
/// file name ("The Lighthouse Keeper's Ledger", not "lighthouse.epub").
Future<EpubInfo?> epubInfo(String filePath) async {
  try {
    return await Isolate.run(() {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      // The file is read where its zip directory points, not whole: the
      // package metadata is two small entries, and every library row asks
      // for it. Reading whole books (tens of megabytes with their images)
      // for a title made opening a large library slow and memory-hungry.
      final input = InputFileStream(filePath);
      try {
        final archive = ZipDecoder().decodeStream(input);
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
        final package = XmlDocument.parse(opf);
        String? first(String name) {
          final value = package
              .findAllElements('*')
              .where((e) => e.name.local == name)
              .map((e) => e.innerText.replaceAll(RegExp(r'\s+'), ' ').trim())
              .firstWhere((t) => t.isNotEmpty, orElse: () => '');
          return value.isEmpty ? null : value;
        }

        return EpubInfo(title: first('title'), author: first('creator'));
      } finally {
        input.closeSync();
      }
    }).timeout(const Duration(seconds: 5));
  } on Object {
    return null;
  }
}

/// The EPUB's own title (`dc:title` in its package file), or null.
Future<String?> epubTitle(String filePath) async =>
    (await epubInfo(filePath))?.title;
