import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/pdf_extractor.dart';
import 'package:runthru/services/pdf_text_layout.dart';

import 'pdf_page_fixture.dart';

/// Synthetic pages in place of pdfium, which cannot run under `flutter test`.
class FakeSource implements PdfPageSource {
  FakeSource(this.pages, {this.outline = const []});

  final List<PdfRawPage> pages;
  final List<PdfOutlineTarget> outline;

  /// Page indices in the order they were read.
  final List<int> loads = <int>[];

  /// Pages whose read fails.
  final Set<int> broken = <int>{};
  bool outlineBroken = false;
  void Function(int pageIndex)? onLoad;

  @override
  int get pageCount => pages.length;

  @override
  Future<PdfRawPage> loadPage(int pageIndex) async {
    loads.add(pageIndex);
    onLoad?.call(pageIndex);
    if (broken.contains(pageIndex)) throw Exception('page $pageIndex');
    return pages[pageIndex];
  }

  @override
  Future<List<PdfOutlineTarget>> loadOutline() async {
    if (outlineBroken) throw Exception('outline');
    return outline;
  }
}

/// A typeset book with running heads, page numbers, chapter headings,
/// indented paragraphs and words hyphenated both inside pages and across
/// page breaks.
({List<PdfRawPage> pages, List<String> written, Typesetter typesetter}) book({
  int chapters = 3,
  int paragraphsPerChapter = 9,
  double bottom = 300,
}) {
  final t = Typesetter(
    indent: 12,
    bottom: bottom,
    hyphenation: const {
      'remembered': 5,
      'travelling': 6,
      'described': 3,
      'neighbour': 5,
      'lanterns': 3,
      'shutters': 4,
      'surveyor': 3,
      'northern': 5,
    },
    header: (i) => i.isEven ? 'A TALE OF TWO HARBOURS' : 'THE NIGHT PORTER',
    footer: (i) => '${i + 1}',
  );
  final prose = Prose(58);
  final written = <String>[];
  for (var chapter = 1; chapter <= chapters; chapter++) {
    t.heading('Chapter $chapter', size: 18);
    written.add('# Chapter $chapter');
    for (var i = 0; i < paragraphsPerChapter; i++) {
      final text = prose.paragraph(2 + (i + chapter) % 4);
      written.add(text);
      t.paragraph(text);
    }
  }
  return (pages: t.build(), written: written, typesetter: t);
}

/// Headings as "# text", paragraphs as their sentences joined.
List<String> paragraphsOf(ExtractedDocument document) {
  final out = <String>[];
  for (final s in document.sentences) {
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

void expectSameDocument(ExtractedDocument actual, ExtractedDocument expected) {
  expect(
    [for (final s in actual.sentences) s.words.join(' ')],
    [for (final s in expected.sentences) s.words.join(' ')],
  );
  expect(
    [for (final s in actual.sentences) (s.startsParagraph, s.heading)],
    [for (final s in expected.sentences) (s.startsParagraph, s.heading)],
  );
  expect(
    [
      for (final b in actual.pageBoundaries)
        (b.pageNumber, b.startWordIndex, b.startSentenceIndex, b.firstWords),
    ],
    [
      for (final b in expected.pageBoundaries)
        (b.pageNumber, b.startWordIndex, b.startSentenceIndex, b.firstWords),
    ],
  );
  expect(
    [
      for (final e in actual.outline)
        (e.title, e.startWordIndex, e.startSentenceIndex, e.depth),
    ],
    [
      for (final e in expected.outline)
        (e.title, e.startWordIndex, e.startSentenceIndex, e.depth),
    ],
  );
}

void main() {
  group('extractPdfPagesFrom', () {
    test('rebuilds the text of the range and records one boundary per '
        'page', () async {
      final b = book();
      final source = FakeSource(b.pages);
      final result = await extractPdfPagesFrom(source, 0, b.pages.length - 1);

      expect(paragraphsOf(result.document), b.written);
      expect(result.totalPages, b.pages.length);
      expect(result.extractedStartPage, 0);
      expect(result.extractedEndPage, b.pages.length - 1);
      expect(result.document.totalPages, b.pages.length);
      expect(result.document.version, kExtractionVersion);
      expect(result.document.continuesPrevious, isFalse);
      expect(result.pageBoundaries, same(result.document.pageBoundaries));

      final words = result.document.allWords;
      expect(result.pageBoundaries.map((p) => p.pageNumber), [
        for (var i = 0; i < b.pages.length; i++) i,
      ]);
      for (final boundary in result.pageBoundaries) {
        final first = b.typesetter.firstWordOfPage[boundary.pageNumber]!;
        expect(words[boundary.startWordIndex], first);
        expect(boundary.firstWords.split(' ').first, first);
      }
    });

    test('reads two pages either side as evidence and emits none of '
        'them', () async {
      final b = book();
      final source = FakeSource(b.pages);
      final result = await extractPdfPagesFrom(source, 3, 5);

      expect(source.loads, [1, 2, 3, 4, 5, 6, 7]);
      expect(result.pageBoundaries.map((p) => p.pageNumber), [3, 4, 5]);
      expect(result.pageBoundaries.first.startWordIndex, 0);
      expect(result.pageBoundaries.first.startSentenceIndex, 0);
      // The running heads of the three pages are identified from the
      // window: neither they nor the page numbers are in the text.
      final text = result.document.allWords.join(' ');
      expect(text, isNot(contains('HARBOURS')));
      expect(text, isNot(contains('NIGHT PORTER')));
    });

    test('clamps the range to the document', () async {
      final b = book();
      final last = b.pages.length - 1;
      final source = FakeSource(b.pages);

      final tail = await extractPdfPagesFrom(source, last - 1, 999);
      expect(tail.extractedStartPage, last - 1);
      expect(tail.extractedEndPage, last);
      expect(tail.pageBoundaries.map((p) => p.pageNumber), [last - 1, last]);

      final beyond = await extractPdfPagesFrom(source, 999, 1000);
      expect(beyond.extractedStartPage, last);
      expect(beyond.extractedEndPage, last);
    });

    test('ranges merged in order equal the document extracted in one '
        'piece, wherever the ranges are cut', () async {
      final b = book();
      final pages = b.pages;
      final whole = await extractPdfPagesFrom(
        FakeSource(pages),
        0,
        pages.length - 1,
      );

      // Every page its own range: every page break becomes a range edge,
      // including the ones that fall inside a sentence or inside a word.
      for (final step in [1, 2, 3]) {
        final source = FakeSource(pages);
        ExtractedDocument? merged;
        var continued = 0;
        for (var start = 0; start < pages.length; start += step) {
          final part = await extractPdfPagesFrom(
            source,
            start,
            start + step - 1,
          );
          if (part.document.continuesPrevious) continued++;
          merged = merged == null ? part.document : merged.merge(part.document);
        }
        expect(continued, greaterThan(0), reason: 'step $step');
        expectSameDocument(merged!, whole.document);
        expect(paragraphsOf(merged), b.written, reason: 'step $step');
        expect(
          merged.allWords.any((w) => w.contains(kSplitWordMarker)),
          isFalse,
        );
      }
    });

    test('a word cut by the end of a range waits for its other half', () async {
      final b = book();
      final pages = b.pages;
      final cut = pages.indexWhere(
        (p) => RegExp(r'[a-z]-\r\n').hasMatch(p.text),
      );
      expect(cut, greaterThanOrEqualTo(0), reason: 'fixture precondition');

      final source = FakeSource(pages);
      final head = await extractPdfPagesFrom(source, 0, cut);
      final tail = await extractPdfPagesFrom(source, cut + 1, pages.length - 1);
      expect(head.document.allWords.last, endsWith(kSplitWordMarker));
      expect(tail.document.continuesPrevious, isTrue);

      final merged = head.document.merge(tail.document);
      expect(paragraphsOf(merged), b.written);
      final boundary = merged.pageBoundaries[cut + 1];
      expect(
        merged.allWords[boundary.startWordIndex],
        b.typesetter.firstWordOfPage[cut + 1],
      );
    });

    test('keeps looking when the front matter has no text', () async {
      final b = book();
      // Five image-only pages (cover, title, …) before the text.
      final pages = <PdfRawPage>[
        for (var i = 0; i < 5; i++) PdfRawPage.empty(pageIndex: i),
        ...b.pages
            .take(12)
            .map(
              (p) => PdfRawPage(
                pageIndex: p.pageIndex + 5,
                width: p.width,
                height: p.height,
                text: p.text,
                charBoxes: p.charBoxes,
              ),
            ),
      ];
      final source = FakeSource(pages);
      final result = await extractPdfPagesFrom(source, 0, previewPageCount - 1);

      expect(result.extractedStartPage, 0);
      expect(result.extractedEndPage, 12, reason: 'preview end + 10');
      expect(result.document.sentences, isNotEmpty);
      expect(result.pageBoundaries.map((p) => p.pageNumber), [
        for (var i = 0; i <= 12; i++) i,
      ]);
      // The blank pages start where the text starts.
      expect(result.pageBoundaries.take(6).map((p) => p.startWordIndex), [
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      // Nothing is read twice while probing.
      expect(source.loads.toSet().length, source.loads.length);
    });

    test('gives up on a document with no text at all', () async {
      final source = FakeSource([
        for (var i = 0; i < 20; i++) PdfRawPage.empty(pageIndex: i),
      ]);
      await expectLater(
        extractPdfPagesFrom(source, 0, previewPageCount - 1),
        throwsA(isA<UnsupportedPdfError>()),
      );
      // Probed ten pages past the preview (plus evidence), not the book.
      expect(source.loads.reduce((a, b) => a > b ? a : b), lessThan(15));

      await expectLater(
        extractPdfPagesFrom(FakeSource(const []), 0, 2),
        throwsA(isA<UnsupportedPdfError>()),
      );
    });

    test('a later range without text is simply empty', () async {
      final b = book();
      final pages = <PdfRawPage>[
        ...b.pages.take(4),
        for (var i = 4; i < 9; i++) PdfRawPage.empty(pageIndex: i),
      ];
      final result = await extractPdfPagesFrom(FakeSource(pages), 6, 8);
      expect(result.document.sentences, isEmpty);
      expect(result.extractedEndPage, 8);
      expect(result.pageBoundaries.map((p) => p.pageNumber), [6, 7, 8]);
      expect(result.pageBoundaries.every((p) => p.firstWords.isEmpty), isTrue);
    });

    test('stops reading at the next page once cancelled', () async {
      final b = book();
      final source = FakeSource(b.pages);
      final token = ExtractionCancelToken();
      source.onLoad = (_) {
        if (source.loads.length == 2) token.cancelled = true;
      };
      final result = await extractPdfPagesFrom(
        source,
        0,
        b.pages.length - 1,
        cancelToken: token,
      );
      expect(source.loads.length, 2);
      expect(result.document.sentences, isEmpty);
      expect(result.extractedEndPage, lessThan(result.extractedStartPage));

      final before = FakeSource(b.pages);
      await extractPdfPagesFrom(
        before,
        0,
        2,
        cancelToken: ExtractionCancelToken()..cancelled = true,
      );
      expect(before.loads, isEmpty);
    });

    test('an unreadable evidence page is not fatal; an unreadable page of '
        'the range is', () async {
      final b = book();
      final source = FakeSource(b.pages)..broken.add(6);
      final result = await extractPdfPagesFrom(source, 3, 5);
      expect(result.pageBoundaries.map((p) => p.pageNumber), [3, 4, 5]);
      expect(result.document.sentences, isNotEmpty);

      final inside = FakeSource(b.pages)..broken.add(4);
      await expectLater(
        extractPdfPagesFrom(inside, 3, 5),
        throwsA(isA<Exception>()),
      );
    });

    test('bookmarks become outline entries of the range they point '
        'into', () async {
      final b = book();
      final pages = b.pages;
      // Where the typesetter put each chapter heading.
      final chapterPage = <int, int>{};
      for (final page in pages) {
        final match = RegExp(r'Chapter (\d)\r\n').firstMatch(page.text);
        if (match != null) {
          chapterPage[int.parse(match.group(1)!)] = page.pageIndex;
        }
      }
      expect(chapterPage.keys, [1, 2, 3]);
      final outline = <PdfOutlineTarget>[
        const PdfOutlineTarget(title: 'A Tale of Two Harbours', pageIndex: 0),
        for (final entry in chapterPage.entries)
          PdfOutlineTarget(
            title: 'Chapter ${entry.key}',
            pageIndex: entry.value,
            depth: 1,
          ),
      ];

      final whole = await extractPdfPagesFrom(
        FakeSource(pages, outline: outline),
        0,
        pages.length - 1,
      );
      expect(whole.document.outline.map((e) => e.title), [
        'A Tale of Two Harbours',
        'Chapter 1',
        'Chapter 2',
        'Chapter 3',
      ]);
      for (final entry in whole.document.outline.skip(1)) {
        final sentence = whole.document.sentences[entry.startSentenceIndex];
        expect(sentence.isHeading, isTrue);
        expect(sentence.words.join(' '), entry.title);
        expect(entry.depth, 1);
      }

      // A range sees only its own bookmarks; merged, they line up with the
      // one-piece extraction.
      final source = FakeSource(pages, outline: outline);
      final cut = chapterPage[2]!;
      final head = await extractPdfPagesFrom(source, 0, cut - 1);
      final tail = await extractPdfPagesFrom(source, cut, pages.length - 1);
      expect(head.document.outline.map((e) => e.title), [
        'A Tale of Two Harbours',
        'Chapter 1',
      ]);
      expect(tail.document.outline.map((e) => e.title), [
        'Chapter 2',
        'Chapter 3',
      ]);
      expectSameDocument(head.document.merge(tail.document), whole.document);

      // A broken outline costs the bookmarks, not the book.
      final noOutline = FakeSource(pages, outline: outline)
        ..outlineBroken = true;
      final result = await extractPdfPagesFrom(noOutline, 0, 2);
      expect(result.document.outline, isEmpty);
      expect(result.document.sentences, isNotEmpty);
    });
  });

  group('extractPdfDocumentFrom', () {
    test('extracts a long document in ranges and merges them into the '
        'same text', () async {
      // More than two ranges of 25 pages.
      final b = book(chapters: 6, paragraphsPerChapter: 22, bottom: 380);
      expect(b.pages.length, greaterThan(55));
      final source = FakeSource(b.pages);
      final progress = <double>[];
      final document = await extractPdfDocumentFrom(
        source,
        onProgress: progress.add,
      );

      expect(paragraphsOf(document), b.written);
      expect(document.totalPages, b.pages.length);
      expect(document.pageBoundaries.length, b.pages.length);
      expect(
        document.allWords.any((w) => w.contains(kSplitWordMarker)),
        isFalse,
      );
      for (final boundary in document.pageBoundaries) {
        expect(
          document.allWords[boundary.startWordIndex],
          b.typesetter.firstWordOfPage[boundary.pageNumber],
        );
      }

      // Every page read exactly once, evidence included.
      expect(source.loads.length, b.pages.length);
      expect(source.loads.toSet().length, b.pages.length);

      // Progress: one step per page, rising to 1.
      expect(progress.length, b.pages.length);
      expect(progress.last, 1.0);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThan(progress[i - 1]));
      }

      // The same text as the queue's path: a preview, then ranges.
      final queued = FakeSource(b.pages);
      final preview = await extractPdfPagesFrom(
        queued,
        0,
        previewPageCount - 1,
      );
      var merged = preview.document;
      var cursor = preview.extractedEndPage + 1;
      while (cursor < b.pages.length) {
        final part = await extractPdfPagesFrom(queued, cursor, cursor + 24);
        merged = merged.merge(part.document);
        cursor = part.extractedEndPage + 1;
      }
      expectSameDocument(merged, document);
    });

    test('a document without text throws, or comes back empty when asked '
        'not to', () async {
      List<PdfRawPage> blank() => [
        for (var i = 0; i < 4; i++) PdfRawPage.empty(pageIndex: i),
      ];
      await expectLater(
        extractPdfDocumentFrom(FakeSource(blank())),
        throwsA(isA<UnsupportedPdfError>()),
      );
      final empty = await extractPdfDocumentFrom(
        FakeSource(blank()),
        throwOnEmpty: false,
      );
      expect(empty.sentences, isEmpty);
      expect(empty.totalPages, 4);
      expect(empty.pageBoundaries.map((p) => p.pageNumber), [0, 1, 2, 3]);

      final none = await extractPdfDocumentFrom(
        FakeSource(const []),
        throwOnEmpty: false,
      );
      expect(none.sentences, isEmpty);
      expect(none.pageBoundaries, isEmpty);
    });

    test('stops reading at the next page once cancelled', () async {
      final b = book(chapters: 6, paragraphsPerChapter: 22, bottom: 380);
      final source = FakeSource(b.pages);
      final token = ExtractionCancelToken();
      source.onLoad = (_) {
        if (source.loads.length == 30) token.cancelled = true;
      };
      final document = await extractPdfDocumentFrom(source, cancelToken: token);
      expect(source.loads.length, 30);
      // What was finished before the cancel is returned; nothing more.
      expect(document.pageBoundaries.length, 25);
    });
  });

  group('pdfExtract', () {
    test('throws FileSystemException for non-existent file', () async {
      expect(
        () => pdfExtract('/non/existent/file.pdf'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('throws FileSystemException for empty path', () async {
      expect(() => pdfExtract(''), throwsA(isA<FileSystemException>()));
    });

    test('throwOnEmpty parameter is accepted by pdfExtract', () {
      // Validate the parameter exists on the function signature.
      // Actual PDF extraction requires pdfrx FFI (getCacheDirectory),
      // which isn't available in unit tests.
      expect(
        () => pdfExtract('/non/existent/file.pdf', throwOnEmpty: false),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('pdfExtractWithProgress', () {
    test('reports error for non-existent file', () async {
      Object? reportedError;
      ExtractedDocument? reportedDoc;

      final stream = pdfExtractWithProgress(
        '/non/existent/file.pdf',
        onComplete: (doc) => reportedDoc = doc,
        onError: (e) => reportedError = e,
      );

      // Drain the stream.
      await stream.toList();

      expect(reportedError, isNotNull);
      expect(reportedError, isA<FileSystemException>());
      expect(reportedDoc, isNull);
    });

    test('stream closes after error', () async {
      final stream = pdfExtractWithProgress(
        '/non/existent/file.pdf',
        onComplete: (_) {},
        onError: (_) {},
      );

      final values = await stream.toList();
      // Stream should terminate (toList completes).
      expect(values, isA<List<double>>());
    });
  });

  group('extractPdfInIsolate', () {
    test('throws FileSystemException for non-existent file', () async {
      expect(
        () => extractPdfInIsolate('/non/existent/file.pdf'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('pdfPageCountInIsolate', () {
    test('throws for non-existent file', () async {
      expect(
        () => pdfPageCountInIsolate('/non/existent/file.pdf'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('Sentence model', () {
    test('has correct word list', () {
      const sentence = Sentence(words: ['Hello', 'world']);
      expect(sentence.words, ['Hello', 'world']);
    });

    test('serializes to JSON and back', () {
      const original = Sentence(words: ['The', 'quick', 'brown', 'fox']);
      final json = original.toJson();
      final restored = Sentence.fromJson(json);
      expect(restored.words, original.words);
    });

    test('empty sentence has empty word list', () {
      const sentence = Sentence(words: []);
      expect(sentence.words, isEmpty);
    });
  });

  group('ExtractedDocument model', () {
    test('tracks total words', () {
      const doc = ExtractedDocument(
        sentences: [
          Sentence(words: ['Hello', 'world']),
          Sentence(words: ['This', 'is', 'a', 'test']),
        ],
      );
      expect(doc.totalWords, 6);
      expect(doc.allWords, ['Hello', 'world', 'This', 'is', 'a', 'test']);
    });

    test('empty ExtractedDocument has zero words', () {
      const doc = ExtractedDocument(sentences: []);
      expect(doc.totalWords, 0);
      expect(doc.allWords, isEmpty);
    });

    test('hasPageBoundaries is false when empty', () {
      const doc = ExtractedDocument(sentences: []);
      expect(doc.hasPageBoundaries, isFalse);
    });

    test('hasPageBoundaries is true when present', () {
      const doc = ExtractedDocument(
        sentences: [
          Sentence(words: ['word']),
        ],
        pageBoundaries: [
          PageBoundary(
            pageNumber: 0,
            startSentenceIndex: 0,
            startWordIndex: 0,
            firstWords: 'word',
          ),
        ],
        totalPages: 1,
      );
      expect(doc.hasPageBoundaries, isTrue);
    });

    test('merge combines two documents', () {
      const doc1 = ExtractedDocument(
        sentences: [
          Sentence(words: ['Hello']),
        ],
        pageBoundaries: [
          PageBoundary(
            pageNumber: 0,
            startSentenceIndex: 0,
            startWordIndex: 0,
            firstWords: 'Hello',
          ),
        ],
        totalPages: 1,
      );
      const doc2 = ExtractedDocument(
        sentences: [
          Sentence(words: ['World']),
        ],
        pageBoundaries: [
          PageBoundary(
            pageNumber: 1,
            startSentenceIndex: 1,
            startWordIndex: 1,
            firstWords: 'World',
          ),
        ],
        totalPages: 2,
      );
      final merged = doc1.merge(doc2);
      expect(merged.sentences.length, 2);
      expect(merged.pageBoundaries.length, 2);
      expect(merged.totalPages, 2);
      expect(merged.totalWords, 2);
    });

    test('JSON round-trip preserves all fields', () {
      const doc = ExtractedDocument(
        sentences: [
          Sentence(words: ['Hello', 'world']),
          Sentence(words: ['Test']),
        ],
        pageBoundaries: [
          PageBoundary(
            pageNumber: 0,
            startSentenceIndex: 0,
            startWordIndex: 0,
            firstWords: 'Hello world',
          ),
        ],
        totalPages: 5,
      );

      final json = doc.toJson();
      final restored = ExtractedDocument.fromJson(json);

      expect(restored.sentences.length, doc.sentences.length);
      expect(restored.totalPages, doc.totalPages);
      expect(restored.pageBoundaries.length, doc.pageBoundaries.length);
      expect(restored.pageBoundaries[0].pageNumber, 0);
      expect(restored.pageBoundaries[0].firstWords, 'Hello world');
      expect(restored.totalWords, doc.totalWords);
    });
  });

  group('PageRangeResult', () {
    test('has correct structure', () {
      const result = PageRangeResult(
        document: ExtractedDocument(sentences: []),
        totalPages: 5,
        extractedStartPage: 0,
        extractedEndPage: 2,
        pageBoundaries: [],
      );
      expect(result.totalPages, 5);
      expect(result.extractedStartPage, 0);
      expect(result.extractedEndPage, 2);
    });
  });

  group('PdfProgress', () {
    test('fraction is 0.0 when totalPages is 0', () {
      const progress = PdfProgress();
      expect(progress.fraction, 0.0);
    });

    test('fraction computes correctly', () {
      const progress = PdfProgress(lastCompletedPage: 3, totalPages: 10);
      expect(progress.fraction, 0.3);
    });

    test('fraction is 1.0 when all pages complete', () {
      const progress = PdfProgress(lastCompletedPage: 5, totalPages: 5);
      expect(progress.fraction, 1.0);
    });

    test('copyWith creates modified copy', () {
      const progress = PdfProgress(
        lastCompletedPage: 2,
        totalPages: 10,
        phase: ExtractionPhase.preview,
      );
      final updated = progress.copyWith(
        lastCompletedPage: 5,
        phase: ExtractionPhase.done,
      );
      expect(updated.lastCompletedPage, 5);
      expect(updated.totalPages, 10);
      expect(updated.phase, ExtractionPhase.done);
    });
  });

  group('Error types', () {
    test('UnsupportedPdfError carries message', () {
      const error = UnsupportedPdfError('Image-only PDF');
      expect(error.message, 'Image-only PDF');
      expect(error.toString(), contains('Image-only PDF'));
    });

    test('PdfTimeoutError carries file path', () {
      const error = PdfTimeoutError('/path/to/large.pdf');
      expect(error.filePath, '/path/to/large.pdf');
      expect(error.toString(), contains('/path/to/large.pdf'));
    });
  });
}
