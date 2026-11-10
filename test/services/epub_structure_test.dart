import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/book_structure.dart';
import 'package:runthru/services/epub_extractor.dart';
import 'package:runthru/services/models.dart';

/// Builds an EPUB from explicit files. [spine] lists manifest ids in reading
/// order; every key of [files] ending in `.xhtml` / `.html` is a manifest
/// item whose id is its base name without extension.
List<int> _epub({
  required Map<String, String> files,
  required List<String> spine,
  String? navFile,
  String? ncxFile,
  String guide = '',
  String opfDir = 'OEBPS/',
}) {
  final archive = Archive();
  void add(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="${opfDir}content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');

  String idOf(String path) => path.split('/').last.split('.').first;
  final items = StringBuffer();
  for (final path in files.keys) {
    final isNav = path == navFile;
    final isNcx = path == ncxFile;
    items.writeln(
      '<item id="${idOf(path)}" href="$path" media-type="'
      '${isNcx ? 'application/x-dtbncx+xml' : 'application/xhtml+xml'}"'
      '${isNav ? ' properties="nav"' : ''}/>',
    );
  }
  final refs = [for (final id in spine) '<itemref idref="$id"/>'].join('\n');
  add('${opfDir}content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>T</dc:title></metadata>
  <manifest>
$items  </manifest>
  <spine${ncxFile == null ? '' : ' toc="${idOf(ncxFile)}"'}>
$refs
  </spine>
  $guide
</package>''');
  files.forEach((path, content) => add('$opfDir$path', content));
  return ZipEncoder().encode(archive);
}

String _page(String body, {String bodyAttributes = ''}) =>
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>x</title></head>'
    '<body$bodyAttributes>$body</body></html>';

Future<ExtractedDocument> _extract(List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('epub_structure_');
  addTearDown(() => dir.delete(recursive: true));
  final path = '${dir.path}/book.epub';
  await File(path).writeAsBytes(bytes);
  return epubExtract(path);
}

String _wordsAt(ExtractedDocument doc, int word, [int count = 3]) =>
    doc.allWords.skip(word).take(count).join(' ');

void main() {
  group('headings', () {
    test('keep their level and are never split on punctuation', () async {
      final doc = await _extract(
        _epub(
          files: {
            'c1.xhtml': _page(
              '<h1>The Book</h1>'
              '<h2 class="x">1. The Arrival. A Beginning</h2>'
              '<p>It rained. It poured.</p>',
            ),
          },
          spine: ['c1'],
        ),
      );
      expect(doc.sentences[0].heading, 1);
      expect(doc.sentences[0].words, ['The', 'Book']);
      expect(doc.sentences[1].heading, 2);
      expect(doc.sentences[1].words.join(' '), '1. The Arrival. A Beginning');
      expect(doc.sentences[1].startsParagraph, isTrue);
      expect(doc.sentences[2].isHeading, isFalse);
      expect(doc.sentences.length, 4);
    });

    test('a subtitle paragraph reads as part of the heading', () async {
      final doc = await _extract(
        _epub(
          files: {
            'c1.xhtml': _page(
              '<hgroup><h2>Frankenstein</h2>'
              '<p role="doc-subtitle">Or, The Modern Prometheus</p></hgroup>'
              '<p>Body text here.</p>',
            ),
          },
          spine: ['c1'],
        ),
      );
      expect(doc.sentences[0].heading, 2);
      expect(doc.sentences[1].heading, 6);
      expect(doc.sentences[1].words.join(' '), 'Or, The Modern Prometheus');
      expect(doc.sentences[2].isHeading, isFalse);
    });

    test(
      'private-use marker characters in the source cannot fake a heading',
      () async {
        final doc = await _extract(
          _epub(
            files: {'c1.xhtml': _page('<p>1Not a heading. Fine.</p>')},
            spine: ['c1'],
          ),
        );
        expect(doc.sentences.any((s) => s.isHeading), isFalse);
        expect(doc.allWords.join(' '), '1Not a heading. Fine.');
      },
    );
  });

  group('reference clutter inside sentences', () {
    test('footnote markers, backlinks and page numbers are removed', () async {
      final doc = await _extract(
        _epub(
          files: {
            'c1.xhtml': _page(
              '<p>A republic.<a href="n.xhtml#n1" id="r1" epub:type="noteref">1</a> '
              'Next<sup>2</sup> word and x<sup>2</sup> stays?'
              '<span class="pagenum"><a id="Page_12">[Pg 12]</a></span> More '
              '<span epub:type="pagebreak" title="13" id="p13"/>text '
              'here<sup><a href="#fn3">[3]</a></sup>.</p>'
              '<p>Note text. <a href="c1.xhtml#r1" epub:type="backlink">↩︎</a></p>',
            ),
          },
          spine: ['c1'],
        ),
      );
      final text = doc.allWords.join(' ');
      expect(text, contains('A republic. Next word and x stays?'));
      expect(text, contains('More text here.'));
      expect(text, isNot(contains('Pg')));
      expect(text, isNot(contains('↩')));
      expect(text, isNot(contains('[3]')));
    });

    test('a superscript that is real text is kept', () async {
      final doc = await _extract(
        _epub(
          files: {
            'c1.xhtml': _page(
              '<p>The 1<sup>st</sup> of May, M<sup>lle</sup> Dupont.</p>',
            ),
          },
          spine: ['c1'],
        ),
      );
      expect(doc.allWords.join(' '), 'The 1st of May, Mlle Dupont.');
    });
  });

  group('EPUB 3 navigation', () {
    late ExtractedDocument doc;

    setUp(() async {
      doc = await _extract(
        _epub(
          navFile: 'nav.xhtml',
          files: {
            'nav.xhtml': _page(
              '''
<nav epub:type="toc"><h2>Contents</h2><ol>
  <li><a href="front.xhtml">Title Page</a></li>
  <li><a href="text/c1.xhtml#one">Chapter One &amp; <i>Only</i></a>
    <ol><li><a href="text/c1.xhtml#one-b">A Sub-Section</a></li></ol>
  </li>
  <li><a href="text/c1.xhtml#two">Chapter Two</a></li>
  <li><a href="text/missing.xhtml">Ghost</a></li>
</ol></nav>
<nav epub:type="landmarks"><ol>
  <li><a epub:type="bodymatter" href="text/c1.xhtml#one">Start</a></li>
  <li><a epub:type="backmatter endnotes" href="notes.xhtml">Notes</a></li>
</ol></nav>
<nav epub:type="page-list"><ol><li><a href="text/c1.xhtml#p1">1</a></li></ol></nav>''',
            ),
            'front.xhtml': _page(
              '<section epub:type="titlepage"><h1>The Book</h1></section>',
              bodyAttributes: ' epub:type="frontmatter"',
            ),
            'text/c1.xhtml': _page(
              '<section id="one"><h2>Chapter One</h2><p>First words here.</p>'
              '<h3 id="one-b">A Sub-Section</h3><p>Deeper words.</p></section>'
              '<h2 id="two">Chapter Two</h2><p id="p1">Second words here.</p>',
              bodyAttributes: ' epub:type="bodymatter"',
            ),
            'notes.xhtml': _page(
              '<section epub:type="endnotes"><h2>Notes</h2><p>A note.</p></section>',
              bodyAttributes: ' epub:type="backmatter"',
            ),
          },
          spine: ['front', 'c1', 'notes'],
        ),
      );
    });

    test('the navigation document is not read as text', () {
      expect(doc.totalPages, 3);
      expect(doc.allWords.join(' '), isNot(contains('Ghost')));
    });

    test('entries land on the element their fragment names', () {
      final byTitle = {for (final e in doc.outline) e.title: e};
      expect(
        _wordsAt(doc, byTitle['Title Page']!.startWordIndex, 2),
        'The Book',
      );
      expect(
        _wordsAt(doc, byTitle['Chapter One & Only']!.startWordIndex, 2),
        'Chapter One',
      );
      expect(
        _wordsAt(doc, byTitle['A Sub-Section']!.startWordIndex, 2),
        'A Sub-Section',
      );
      expect(
        _wordsAt(doc, byTitle['Chapter Two']!.startWordIndex, 2),
        'Chapter Two',
      );
      expect(byTitle.containsKey('Ghost'), isFalse);
      // Sentence indices agree with word indices.
      for (final e in doc.outline) {
        var w = 0;
        for (var s = 0; s < e.startSentenceIndex; s++) {
          w += doc.sentences[s].words.length;
        }
        expect(w, lessThanOrEqualTo(e.startWordIndex));
        if (e.startSentenceIndex < doc.sentences.length) {
          expect(
            e.startWordIndex,
            lessThan(w + doc.sentences[e.startSentenceIndex].words.length),
          );
        }
      }
    });

    test('nesting depth and types come through', () {
      final byTitle = {for (final e in doc.outline) e.title: e};
      expect(byTitle['Chapter One & Only']!.depth, 0);
      expect(byTitle['A Sub-Section']!.depth, 1);
      expect(byTitle['Chapter Two']!.depth, 0);
      expect(byTitle['Title Page']!.type, contains('titlepage'));
      expect(byTitle['Title Page']!.type, contains('frontmatter'));
      expect(byTitle['Chapter One & Only']!.type, contains('bodymatter'));
      // The notes file has no contents row: its type still marks its start.
      final notes = doc.outline.where(
        (e) => (e.type ?? '').contains('endnotes'),
      );
      expect(notes, hasLength(1));
      expect(_wordsAt(doc, notes.single.startWordIndex, 1), 'Notes');
      expect(notes.single.type, contains('backmatter'));
    });

    test('the outline is in reading order', () {
      final words = [for (final e in doc.outline) e.startWordIndex];
      expect(words, [...words]..sort());
    });

    test('the reader starts at chapter one and stops before the notes', () {
      final st = analyzeBookStructure(doc);
      final byTitle = {for (final e in doc.outline) e.title: e};
      expect(st.bodyStart, byTitle['Chapter One & Only']!.startWordIndex);
      expect(st.sections.last.kind, SectionKind.back);
      expect(st.chapters.map((s) => s.label), ['Chapter One', 'Chapter Two']);
      expect(st.chapters.first.title, '& Only');
      expect(st.subHeadings.single.text, 'A Sub-Section');
    });
  });

  group('EPUB 2 navigation', () {
    test('NCX nav points, nesting and the guide are read', () async {
      final doc = await _extract(
        _epub(
          ncxFile: 'toc.ncx',
          guide:
              '<guide><reference type="title-page" href="t.xhtml"/>'
              '<reference type="text" title="Start" href="c.xhtml#ch1"/></guide>',
          files: {
            'toc.ncx': '''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<docTitle><text>Ignored Doc Title</text></docTitle>
<navMap>
  <navPoint id="a" playOrder="1"><navLabel><text>The Book</text></navLabel><content src="t.xhtml"/></navPoint>
  <navPoint id="b" playOrder="2"><navLabel><text>CHAPTER 1. Loomings.</text></navLabel><content src="c.xhtml#ch1"/>
    <navPoint id="c" playOrder="3"><navLabel><text>An Aside</text></navLabel><content src="c.xhtml#aside"/></navPoint>
  </navPoint>
  <navPoint id="d" playOrder="4"><navLabel><text>CHAPTER 2. The Carpet-Bag.</text></navLabel><content src="c.xhtml#ch2"/></navPoint>
</navMap></ncx>''',
            't.xhtml': _page('<h1>The Book</h1><p>By Someone</p>'),
            'c.xhtml': _page(
              '<h2 id="ch1">CHAPTER 1. Loomings.</h2><p>Call me Ishmael. Some years ago.</p>'
              '<h3><a id="aside"></a>An Aside</h3><p>Aside text follows here.</p>'
              '<div id="ch2"><h2>CHAPTER 2. The Carpet-Bag.</h2></div><p>I stuffed a shirt.</p>',
            ),
          },
          spine: ['t', 'c'],
        ),
      );
      final byTitle = {for (final e in doc.outline) e.title: e};
      expect(byTitle.keys, isNot(contains('Ignored Doc Title')));
      expect(
        _wordsAt(doc, byTitle['CHAPTER 1. Loomings.']!.startWordIndex),
        'CHAPTER 1. Loomings.',
      );
      expect(_wordsAt(doc, byTitle['An Aside']!.startWordIndex, 2), 'An Aside');
      expect(byTitle['An Aside']!.depth, 1);
      // The fragment is on a wrapper <div>: the entry points at its heading.
      expect(
        _wordsAt(doc, byTitle['CHAPTER 2. The Carpet-Bag.']!.startWordIndex, 2),
        'CHAPTER 2.',
      );
      expect(byTitle['The Book']!.type, contains('titlepage'));
      expect(byTitle['CHAPTER 1. Loomings.']!.type, contains('bodymatter'));

      final st = analyzeBookStructure(doc);
      expect(st.bodyStart, byTitle['CHAPTER 1. Loomings.']!.startWordIndex);
      expect(st.chapters.first.label, 'Chapter 1');
      expect(st.chapters.first.title, 'Loomings');
    });
  });

  group('Project Gutenberg boilerplate', () {
    test('the licence at the end of the last chapter file is marked there', () async {
      final doc = await _extract(
        _epub(
          files: {
            'h.xhtml': _page(
              '<section class="pg-boilerplate pgheader" id="pg-header">'
              '<h2>The Project Gutenberg eBook of Test</h2><p>Use it freely.</p>'
              '<div>*** START OF THE PROJECT GUTENBERG EBOOK TEST ***</div></section>',
            ),
            'c.xhtml': _page(
              '<h2>CHAPTER 1</h2><p>The story happens here in full.</p>'
              '<h2>CHAPTER 2</h2><p>And it ends well for all.</p>'
              '<section class="pg-boilerplate pgheader" id="pg-footer">'
              '<div>*** END OF THE PROJECT GUTENBERG EBOOK TEST ***</div>'
              '<h2>THE FULL PROJECT GUTENBERG LICENSE</h2><p>Terms.</p></section>',
            ),
          },
          spine: ['h', 'c'],
        ),
      );
      final footer = doc.outline.singleWhere(
        (e) => (e.type ?? '').contains('pg-footer'),
      );
      expect(_wordsAt(doc, footer.startWordIndex, 3), '*** END OF');
      final header = doc.outline.singleWhere(
        (e) => (e.type ?? '').contains('pg-header'),
      );
      expect(header.startWordIndex, 0);

      final st = analyzeBookStructure(doc);
      expect(_wordsAt(doc, st.bodyStart, 2), 'CHAPTER 1');
      expect(st.bodyEnd, footer.startWordIndex);
      expect(st.chapters.length, 2);
    });
  });

  group('chunked extraction', () {
    test('ranges merge into the same outline as a full extraction', () async {
      final bytes = _epub(
        navFile: 'nav.xhtml',
        files: {
          'nav.xhtml': _page(
            '<nav epub:type="toc"><ol>'
            '<li><a href="a.xhtml">Preface</a></li>'
            '<li><a href="b.xhtml#x">Chapter 1</a></li>'
            '<li><a href="c.xhtml">Chapter 2</a></li>'
            '</ol></nav>',
          ),
          'a.xhtml': _page('<h2>Preface</h2><p>Some words before.</p>'),
          'b.xhtml': _page(
            '<p>Lead in.</p><h2 id="x">Chapter 1</h2><p>One text.</p>',
          ),
          'c.xhtml': _page('<h2>Chapter 2</h2><p>Two text.</p>'),
        },
        spine: ['a', 'b', 'c'],
      );
      final dir = await Directory.systemTemp.createTemp('epub_chunks_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/book.epub';
      await File(path).writeAsBytes(bytes);

      final full = await epubExtract(path);
      final first = await epubExtractPages(path, 0, 0);
      final rest = await epubExtractPages(path, 1, 2);
      final merged = first.document.merge(rest.document);

      expect(merged.allWords, full.allWords);
      expect(
        [for (final e in merged.outline) '${e.title}@${e.startWordIndex}'],
        [for (final e in full.outline) '${e.title}@${e.startWordIndex}'],
      );
      expect(
        [for (final b in merged.pageBoundaries) b.startWordIndex],
        [for (final b in full.pageBoundaries) b.startWordIndex],
      );
      expect(
        merged.sentences.map((s) => s.heading),
        full.sentences.map((s) => s.heading),
      );
    });
  });

  group('robustness', () {
    test('broken navigation does not stop the book from opening', () async {
      final doc = await _extract(
        _epub(
          navFile: 'nav.xhtml',
          files: {
            'nav.xhtml':
                '<html><nav epub:type="toc"><ol><li><a href="%E0%A4%A.xhtml">Bad &nbsp; link',
            'c.xhtml': _page('<p>Still readable text.</p>'),
          },
          spine: ['c'],
        ),
      );
      expect(doc.allWords.join(' '), 'Still readable text.');
    });

    test('a book with no navigation has an empty outline', () async {
      final doc = await _extract(
        _epub(files: {'c.xhtml': _page('<p>Plain book.</p>')}, spine: ['c']),
      );
      expect(doc.outline, isEmpty);
      expect(analyzeBookStructure(doc).hasChapters, isFalse);
    });

    test('a telling file name types a file that says nothing itself', () async {
      final doc = await _extract(
        _epub(
          files: {
            'copyright.xhtml': _page('<p>Copyright 2020 Someone.</p>'),
            'chapter-1.xhtml': _page('<h2>One</h2><p>Text.</p>'),
          },
          spine: ['copyright', 'chapter-1'],
        ),
      );
      expect(doc.outline.single.type, 'copyright-page');
      expect(doc.outline.single.startWordIndex, 0);
    });
  });
}
