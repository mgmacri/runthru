import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/epub_extractor.dart';
import 'package:runthru/services/models.dart';

/// Helper to create a minimal valid EPUB file in memory.
///
/// The EPUB is a ZIP archive containing:
/// - META-INF/container.xml (points to content.opf)
/// - content.opf (OPF manifest + spine)
/// - chapter1.xhtml, chapter2.xhtml, etc.
List<int> _createTestEpub({
  List<String> chapterContents = const [
    '<html><body><p>Chapter one. This is the first chapter of the test book.</p></body></html>',
    '<html><body><p>Chapter two. This is the second chapter with more text.</p></body></html>',
  ],
  Map<int, String> itemAttributes = const {},
  Map<int, String> itemrefAttributes = const {},
}) {
  final archive = Archive();

  // META-INF/container.xml
  const containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

  archive.addFile(
    ArchiveFile(
      'META-INF/container.xml',
      utf8.encode(containerXml).length,
      utf8.encode(containerXml),
    ),
  );

  // Build manifest items and spine entries.
  final manifestItems = StringBuffer();
  final spineItems = StringBuffer();

  for (var i = 0; i < chapterContents.length; i++) {
    final id = 'chapter${i + 1}';
    final href = 'chapter${i + 1}.xhtml';
    manifestItems.writeln(
      '    <item id="$id" href="$href" media-type="application/xhtml+xml"'
      '${itemAttributes[i] ?? ''}/>',
    );
    spineItems.writeln(
      '    <itemref idref="$id"${itemrefAttributes[i] ?? ''}/>',
    );
  }

  // content.opf
  final opfXml =
      '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Test EPUB</dc:title>
  </metadata>
  <manifest>
$manifestItems  </manifest>
  <spine>
$spineItems  </spine>
</package>''';

  archive.addFile(
    ArchiveFile('content.opf', utf8.encode(opfXml).length, utf8.encode(opfXml)),
  );

  // Chapter files.
  for (var i = 0; i < chapterContents.length; i++) {
    final content = chapterContents[i];
    archive.addFile(
      ArchiveFile(
        'chapter${i + 1}.xhtml',
        utf8.encode(content).length,
        utf8.encode(content),
      ),
    );
  }

  return ZipEncoder().encode(archive);
}

void main() {
  group('epubExtract', () {
    test('extracts valid EPUB with chapters', () async {
      final bytes = _createTestEpub();
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/test.epub';
      await File(epubPath).writeAsBytes(bytes);

      final doc = await epubExtract(epubPath);

      expect(doc.sentences, isNotEmpty);
      expect(doc.totalPages, 2); // 2 chapters
      expect(doc.pageBoundaries.length, 2);
      expect(doc.totalWords, greaterThan(0));

      await tempDir.delete(recursive: true);
    });

    test('chapter boundaries are correctly detected', () async {
      final bytes = _createTestEpub(
        chapterContents: [
          '<html><body><p>First chapter text here.</p></body></html>',
          '<html><body><p>Second chapter text here.</p></body></html>',
          '<html><body><p>Third chapter text here.</p></body></html>',
        ],
      );
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/test.epub';
      await File(epubPath).writeAsBytes(bytes);

      final doc = await epubExtract(epubPath);

      expect(doc.totalPages, 3);
      expect(doc.pageBoundaries.length, 3);
      expect(doc.pageBoundaries[0].pageNumber, 0);
      expect(doc.pageBoundaries[1].pageNumber, 1);
      expect(doc.pageBoundaries[2].pageNumber, 2);

      // Each chapter boundary should have increasing word indices.
      for (var i = 1; i < doc.pageBoundaries.length; i++) {
        expect(
          doc.pageBoundaries[i].startWordIndex,
          greaterThanOrEqualTo(doc.pageBoundaries[i - 1].startWordIndex),
        );
      }

      await tempDir.delete(recursive: true);
    });

    test('handles EPUB with empty chapters', () async {
      final bytes = _createTestEpub(
        chapterContents: [
          '<html><body></body></html>',
          '<html><body><p>Only this chapter has text.</p></body></html>',
        ],
      );
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/test.epub';
      await File(epubPath).writeAsBytes(bytes);

      final doc = await epubExtract(epubPath);

      expect(doc.sentences, isNotEmpty);
      expect(doc.totalPages, 2);

      await tempDir.delete(recursive: true);
    });

    test('throws for non-existent file', () async {
      expect(
        () => epubExtract('/non/existent/file.epub'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('throws for malformed file (not a ZIP)', () async {
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/bad.epub';
      await File(epubPath).writeAsString('not a zip file');

      try {
        await expectLater(
          epubExtract(epubPath),
          throwsA(isA<UnsupportedPdfError>()),
        );
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } on FileSystemException {
          // Windows file-locking may prevent cleanup; ignore.
        }
      }
    });

    test('handles EPUB with no text content', () async {
      final bytes = _createTestEpub(
        chapterContents: [
          '<html><body></body></html>',
          '<html><body>   </body></html>',
        ],
      );
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/test.epub';
      await File(epubPath).writeAsBytes(bytes);

      try {
        // Should throw UnsupportedPdfError for no extractable text.
        await expectLater(
          epubExtract(epubPath),
          throwsA(isA<UnsupportedPdfError>()),
        );
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } on FileSystemException {
          // Windows file-locking may prevent cleanup; ignore.
        }
      }
    });
  });

  group('epubExtractWithProgress', () {
    test('reports progress and completes', () async {
      final bytes = _createTestEpub();
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/test.epub';
      await File(epubPath).writeAsBytes(bytes);

      ExtractedDocument? completedDoc;
      Object? reportedError;

      final stream = epubExtractWithProgress(
        epubPath,
        onComplete: (doc) => completedDoc = doc,
        onError: (e) => reportedError = e,
      );

      final progressValues = <double>[];
      await for (final progress in stream) {
        progressValues.add(progress);
        expect(progress, greaterThanOrEqualTo(0.0));
        expect(progress, lessThanOrEqualTo(1.0));
      }

      expect(reportedError, isNull);
      expect(completedDoc, isNotNull);
      expect(completedDoc!.sentences, isNotEmpty);
      expect(progressValues, contains(1.0));

      await tempDir.delete(recursive: true);
    });

    test('reports error for non-existent file', () async {
      Object? reportedError;

      final stream = epubExtractWithProgress(
        '/non/existent/file.epub',
        onComplete: (_) {},
        onError: (e) => reportedError = e,
      );

      await stream.toList();
      expect(reportedError, isNotNull);
    });
  });

  group('HTML stripping', () {
    test('extracts text with entities decoded', () async {
      final bytes = _createTestEpub(
        chapterContents: [
          '<html><body><p>Hello &amp; welcome &mdash; enjoy the &ldquo;book&rdquo;.</p></body></html>',
        ],
      );
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/test.epub';
      await File(epubPath).writeAsBytes(bytes);

      final doc = await epubExtract(epubPath);
      final allText = doc.allWords.join(' ');

      expect(allText, contains('&'));
      expect(allText, contains('—'));
      expect(allText, contains('\u201C'));
      expect(allText, contains('\u201D'));

      await tempDir.delete(recursive: true);
    });

    test('a sentence running across spine files stays one paragraph', () async {
      final bytes = _createTestEpub(
        chapterContents: [
          '<html><body><h1>Chapter One</h1><p>Waves like this began small before building and</p></body></html>',
          '<html><body><p>crashing over the earth. A new thought.</p></body></html>',
          '<html><body><p>Next file starts a sentence.</p></body></html>',
        ],
      );
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/test.epub';
      await File(epubPath).writeAsBytes(bytes);

      final doc = await epubExtract(epubPath);
      final starts = [
        for (final s in doc.sentences)
          if (s.startsParagraph) s.words.first,
      ];
      // "crashing" continues the previous paragraph; "Next" begins one.
      expect(starts, ['Chapter', 'Waves', 'Next']);

      await tempDir.delete(recursive: true);
    });

    test('epubTitle reads the package title', () async {
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/file_name.epub';
      await File(epubPath).writeAsBytes(_createTestEpub());
      expect(await epubTitle(epubPath), 'Test EPUB');
      expect(await epubTitle('${tempDir.path}/missing.epub'), isNull);
      await tempDir.delete(recursive: true);
    });

    test('skips the nav document and non-linear spine items', () async {
      final bytes = _createTestEpub(
        chapterContents: [
          '<html><body><nav><ol><li>Chapter One</li></ol></nav></body></html>',
          '<html><body><p>Cover blurb.</p></body></html>',
          '<html><body><p>The real first sentence.</p></body></html>',
        ],
        itemAttributes: {0: ' properties="nav"'},
        itemrefAttributes: {1: ' linear="no"'},
      );
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/test.epub';
      await File(epubPath).writeAsBytes(bytes);

      final doc = await epubExtract(epubPath);
      expect(doc.allWords.join(' '), 'The real first sentence.');
      expect(await epubChapterCountInIsolate(epubPath), 1);

      await tempDir.delete(recursive: true);
    });

    test('block tags with attributes leave no markup behind', () async {
      final bytes = _createTestEpub(
        chapterContents: [
          '<html xmlns:epub="http://www.idpf.org/2007/ops"><head>'
              '<title>Head Title</title></head>'
              '<body epub:type="bodymatter">'
              '<section id="chapter-one" class="level1" epub:type="chapter">'
              '<h1 class="chap">Chapter One</h1>'
              '<p class="first" id="p1">The ferry reached the island.</p>'
              '<div\nclass="multi-line">Still here.</div>'
              '<ol><li id="toc-li-2"><a href="ch002.xhtml">Two</a></li></ol>'
              '</section></body></html>',
        ],
      );
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/test.epub';
      await File(epubPath).writeAsBytes(bytes);

      final doc = await epubExtract(epubPath);
      final allText = doc.allWords.join(' ');

      expect(
        allText,
        'Chapter One The ferry reached the island. Still here. Two',
      );
      for (final leak in ['class=', 'id=', 'epub:type', '">', 'Head']) {
        expect(allText, isNot(contains(leak)), reason: leak);
      }

      await tempDir.delete(recursive: true);
    });

    test('strips inline styles', () async {
      final bytes = _createTestEpub(
        chapterContents: [
          '<html><body><p style="color: red; font-size: 16px;">Styled text here.</p></body></html>',
        ],
      );
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/test.epub';
      await File(epubPath).writeAsBytes(bytes);

      final doc = await epubExtract(epubPath);
      final allText = doc.allWords.join(' ');

      expect(allText, contains('Styled'));
      expect(allText, isNot(contains('color:')));
      expect(allText, isNot(contains('style=')));

      await tempDir.delete(recursive: true);
    });

    test('converts br tags to whitespace', () async {
      final bytes = _createTestEpub(
        chapterContents: [
          '<html><body><p>Line one.<br/>Line two.<br>Line three.</p></body></html>',
        ],
      );
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/test.epub';
      await File(epubPath).writeAsBytes(bytes);

      final doc = await epubExtract(epubPath);

      expect(doc.sentences, isNotEmpty);
      expect(doc.totalWords, greaterThan(0));

      await tempDir.delete(recursive: true);
    });
  });

  group('epubChapterCountInIsolate', () {
    test('returns correct chapter count', () async {
      final bytes = _createTestEpub(
        chapterContents: [
          '<html><body><p>Chapter 1.</p></body></html>',
          '<html><body><p>Chapter 2.</p></body></html>',
          '<html><body><p>Chapter 3.</p></body></html>',
        ],
      );
      final tempDir = await Directory.systemTemp.createTemp('epub_test_');
      final epubPath = '${tempDir.path}/test.epub';
      await File(epubPath).writeAsBytes(bytes);

      final count = await epubChapterCountInIsolate(epubPath);
      expect(count, 3);

      await tempDir.delete(recursive: true);
    });
  });
}
