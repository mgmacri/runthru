import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/pdf_text_layout.dart';

import 'pdf_page_fixture.dart';

PdfLayoutResult analyze(
  List<PdfRawPage> pages, {
  int? firstPage,
  int? lastPage,
  List<PdfOutlineTarget> outline = const [],
}) => analyzePdfLayout(
  pages,
  firstPage: firstPage,
  lastPage: lastPage,
  outline: outline,
);

/// A character by its code, so control and invisible characters are never
/// typed into a test string.
String ch(int code) => String.fromCharCode(code);

String textOf(PdfLayoutResult result) =>
    result.sentences.expand((s) => s.words).join(' ');

List<String> wordsOf(PdfLayoutResult result) =>
    result.sentences.expand((s) => s.words).toList();

List<String> headingsOf(PdfLayoutResult result) => <String>[
  for (final s in result.sentences)
    if (s.isHeading) 'h${s.heading} ${s.words.join(' ')}',
];

/// Three lines of running text that establish the body size, the line
/// pitch and the column on a page. The last one is a short last line.
const List<String> kFiller = <String>[
  'The harbour master counted the lanterns along the river',
  'before the rain came in, and the night porter watched him',
  r'from the steps of the old customs house without a word.$',
];
const String kFillerText =
    'The harbour master counted the lanterns along the river before the '
    'rain came in, and the night porter watched him from the steps of the '
    'old customs house without a word.';

void main() {
  group('lines', () {
    test('ligatures are spelled out; control, zero-width and replacement '
        'characters are dropped', () {
      final page = PageBuilder(0)
        ..line('The ﬁrst ofﬁce on the ﬂoor was oﬀ limits.', y: 500)
        ..line(
          'A stray${ch(0x18)} mark, a zero${ch(0x200B)}width gap and a bad${ch(0xFFFD)} glyph.',
          y: 488,
        );
      expect(
        textOf(analyze([page.build()])),
        'The first office on the floor was off limits. '
        'A stray mark, a zerowidth gap and a bad glyph.',
      );
    });

    test('the app\'s own marker characters never come in from a PDF', () {
      // U+E000 opens a heading paragraph in text prepared for the shared
      // segmenter; U+E002 and U+E003 bracket EPUB anchors.
      final page = PageBuilder(0)
        ..line(
          '${ch(0xE000)}2 lanterns hung over the quay, and ${ch(0xE002)}7'
          '${ch(0xE003)} more in the yard.',
          y: 500,
        );
      final result = analyze([page.build()]);
      expect(
        textOf(result),
        '2 lanterns hung over the quay, and 7 more in the yard.',
      );
      // Not taken for a marked heading, and its digit is still there.
      expect(headingsOf(result), isEmpty);
      for (final word in wordsOf(result)) {
        expect(word.runes.any((r) => r >= 0xE000 && r <= 0xE00F), isFalse);
      }
    });

    test('carriage returns and repeated spaces never reach a word', () {
      final page = PageBuilder(0)
        ..line('Two  spaces   and a${ch(0xA0)}hard space.', y: 500);
      final words = wordsOf(analyze([page.build()]));
      expect(words, ['Two', 'spaces', 'and', 'a', 'hard', 'space.']);
      expect(words.any((w) => w.contains('\r') || w.contains('\n')), isFalse);
    });

    test('a soft hyphen at a line end means the word continues', () {
      final page = PageBuilder(0)
        ..line('It was an extra${ch(0xAD)}', y: 500)
        ..line('ordinary thing to say.', y: 488);
      expect(
        textOf(analyze([page.build()])),
        'It was an extraordinary thing to say.',
      );
    });

    test('rows that pdfium ran together are split where the glyphs '
        'return to the margin', () {
      // One raw line holding two rows, with a space and no line break
      // between them (seen on pages whose content is stored sideways).
      final page = PageBuilder(0);
      block(page, kFiller);
      page
        ..words(
          'The ferry captain repaired the shutters of the corner'.split(' '),
          y: 452,
          justifyTo: kRight,
          endLine: false,
        )
        ..run(' ', x: kRight, y: 452)
        ..line('house.', y: 440)
        ..words(
          'An old surveyor measured three maps of the northern'.split(' '),
          x: kLeft + 12,
          y: 428,
          justifyTo: kRight,
        )
        ..line('road.', y: 416);
      final paragraphs = paragraphTexts(analyze([page.build()]));
      expect(paragraphs, [
        kFillerText,
        'The ferry captain repaired the shutters of the corner house.',
        'An old surveyor measured three maps of the northern road.',
      ]);
    });
  });

  group('words broken at a line end', () {
    PdfLayoutResult set(List<String> rows) {
      final page = PageBuilder(0);
      block(page, rows);
      return analyze([page.build()]);
    }

    test('are rejoined when the document uses the whole word elsewhere', () {
      final result = set([
        'Nobody had been reading the notices on the board for a',
        'month, and so nobody noticed that someone was still read~',
        r'ing them aloud to the empty room every single evening.$',
      ]);
      expect(
        textOf(result),
        'Nobody had been reading the notices on the board for a month, and '
        'so nobody noticed that someone was still reading them aloud to the '
        'empty room every single evening.',
      );
      expect(textOf(result).contains(kStx), isFalse);
    });

    test('keep the hyphen when the document writes the word with one', () {
      final result = set([
        'A well-to-do family had taken the house at the end of the',
        'lane, and people said that they were every bit as well-to~',
        r'do as the family who had lived there before the war.$',
      ]);
      expect(textOf(result), contains('every bit as well-to-do as the'));
    });

    test('are joined without a hyphen when the document has no opinion', () {
      final result = set([
        'In the attic he found his grandfather’s battered kaleido~',
        r'scope and held it up to the window for a long while.$',
      ]);
      expect(textOf(result), contains('battered kaleidoscope and held'));
    });

    test('a compound broken between two of its words keeps its hyphen, '
        'one broken inside a word does not gain one', () {
      final result = set([
        'English is spoken on the island and to the north of it,',
        'so the school bought a second-hand set of the English~',
        'to-German dictionaries, and the mate signed on as an un~',
        r'der-mate for the winter.$',
      ]);
      final text = textOf(result);
      expect(text, contains('the English-to-German dictionaries,'));
      expect(text, contains('as an under-mate for'));
    });

    test('a word that only begins like a prefix is one word', () {
      final result = set([
        'When the others had gone she sat down beside him and ex~',
        'plained, with great patience, that the far bank was great~',
        'er than it looked and that he was not nearly as self~',
        r'possessed as he liked to pretend.$',
      ]);
      final text = textOf(result);
      expect(text, contains('him and explained, with great'));
      expect(text, contains('was greater than it'));
      expect(text, contains('as self-possessed as he'));
    });

    test('a hyphen left at the line end is treated the same way', () {
      final result = set([
        'She spent the whole afternoon wandering through the con-',
        'servatory, where an elderly collector was showing an Anglo-',
        r'Saxon brooch to anyone who would stop and look.$',
      ]);
      final text = textOf(result);
      expect(text, contains('through the conservatory, where'));
      expect(text, contains('an Anglo-Saxon brooch'));
      expect(result.sentences.where((s) => s.startsParagraph).length, 1);
    });

    test('a hyphen standing in for a dash does not swallow the paragraph '
        'after it', () {
      final result = set([
        'A sudden rage came over him as he said this, and his face',
        r'darkened; but presently he calmed himself and proceeded-$',
        '>‘I intended to reason with you, and nothing more than that,',
        r'for this passion does neither of us any good.’$',
      ]);
      expect(paragraphTexts(result), [
        'A sudden rage came over him as he said this, and his face '
            'darkened; but presently he calmed himself and proceeded-',
        '‘I intended to reason with you, and nothing more than that, for '
            'this passion does neither of us any good.’',
      ]);
    });

    test('a suspended hyphen keeps its hyphen and its space', () {
      final result = set([
        'In the back room the society kept a great many pre-',
        r'and post-war ledgers that nobody had opened in years.$',
      ]);
      expect(textOf(result), contains('great many pre- and post-war ledgers'));
    });

    test('a dash at a line end or a line start joins without a space', () {
      final result = set([
        'It had nothing to do with what people call temperament—',
        'it was a gift for hope, and he never once spoke about it',
        '—not to his brother, not even to the woman he married.',
        r'He simply kept it.$',
      ]);
      final text = textOf(result);
      expect(text, contains('temperament—it was a gift'));
      expect(text, contains('about it—not to his brother'));
    });

    test('closing punctuation that wrapped joins the word before it', () {
      final page = PageBuilder(0);
      block(page, [
        'He had to polish it from morning until night until at last',
        'it began to affect his nose, and then his whole face—',
      ]);
      page.line('—’', y: 476);
      block(page, [
        r'>‘Things went from bad to worse,’ suggested Miss Baker.$',
      ], y: 464);
      final paragraphs = paragraphTexts(analyze([page.build()]));
      expect(paragraphs.first, endsWith('his whole face——’'));
      expect(paragraphs.length, 2);
    });
  });

  group('page furniture', () {
    Typesetter book({
      String? Function(int)? header,
      String? Function(int)? footer,
      bool footerFirst = false,
      double? footerSize,
    }) => Typesetter(
      indent: 12,
      bottom: 380,
      header: header,
      footer: footer,
      footerFirst: footerFirst,
      footerSize: footerSize,
    );

    List<String> fill(Typesetter t, {int paragraphs = 14, int seed = 3}) {
      final prose = Prose(seed);
      final written = <String>[];
      for (var i = 0; i < paragraphs; i++) {
        final text = prose.paragraph(3 + i % 3);
        written.add(text);
        t.paragraph(text);
      }
      return written;
    }

    test('running heads that alternate by page, and page numbers at the '
        'foot, are removed without touching the text', () {
      final t = book(
        header: (i) => i.isEven ? 'THE LONG ROAD' : 'CHAPTER TWO',
        footer: (i) => '${i + 1}',
      );
      final written = fill(t);
      final pages = t.build();
      expect(pages.length, greaterThanOrEqualTo(6));

      final result = analyze(pages);
      expect(paragraphTexts(result), written);
      expect(result.pageStarts.length, pages.length);
    });

    test('a running head that carries the page number is recognised as '
        'the number moves', () {
      final t = book(
        header: (i) => i.isEven
            ? '${i + 4} A TALE OF TWO HARBOURS'
            : 'CHAPTER I. THE LANTERNS ${i + 4}',
      );
      final written = fill(t);
      final result = analyze(t.build());
      expect(paragraphTexts(result), written);
      expect(textOf(result), isNot(contains('HARBOURS')));
      expect(textOf(result), isNot(contains('LANTERNS')));
    });

    test('a footer that the file draws first is found at the foot of the '
        'page, not trusted to be last', () {
      final t = book(
        footer: (i) => i.isEven ? 'Free books at Example Press' : 'A Long Road',
        footerFirst: true,
        footerSize: 6,
      );
      final written = fill(t);
      final pages = t.build();
      // The fixture really does list the footer first.
      expect(pages[2].text, startsWith('Free books at Example Press'));

      final result = analyze(pages);
      expect(paragraphTexts(result), written);
      for (final start in result.pageStarts) {
        expect(start.firstWords, isNot(contains('Example Press')));
        expect(start.firstWords, isNot(contains('A Long Road')));
      }
    });

    test('a line that is all there is on its pages is text, not furniture', () {
      // Three slides, each nothing but the same line near the top.
      final pages = [
        for (var i = 0; i < 3; i++)
          (PageBuilder(i)..line('Plans for the harbour', y: 560)).build(),
      ];
      final result = analyze(pages);
      expect(
        textOf(result),
        'Plans for the harbour Plans for the harbour Plans for the harbour',
      );
    });

    test('a running head on a page without text goes with the others', () {
      // Pages 0, 1 and 3 have text under the head; page 2 has only the head
      // (a blank page before a new chapter).
      final pages = <PdfRawPage>[];
      for (var i = 0; i < 4; i++) {
        final page = PageBuilder(i)..line('THE LONG ROAD', y: 570, size: 8);
        if (i != 2) block(page, kFiller);
        pages.add(page.build());
      }
      final result = analyze(pages);
      expect(textOf(result), isNot(contains('LONG ROAD')));
      expect(textOf(result), '$kFillerText $kFillerText $kFillerText');
    });

    test('a head found beside text on too few of its pages stays', () {
      // The same line on four pages, with text under it on only one: it is
      // mostly a title standing alone.
      final pages = <PdfRawPage>[];
      for (var i = 0; i < 4; i++) {
        final page = PageBuilder(i)..line('Plans for the harbour', y: 570);
        if (i == 0) block(page, kFiller);
        pages.add(page.build());
      }
      final result = analyze(pages);
      expect('Plans for the harbour'.allMatches(textOf(result)), hasLength(4));
    });

    test('a short range relies on the pages around it as evidence', () {
      final t = book(header: (i) => i.isEven ? 'THE LONG ROAD' : 'CHAPTER TWO');
      fill(t);
      final pages = t.build();

      // Pages 0-2 with 3 and 4 as evidence: "CHAPTER TWO" is on 1 and 3.
      final withEvidence = analyze(
        pages.sublist(0, 5),
        firstPage: 0,
        lastPage: 2,
      );
      expect(textOf(withEvidence), isNot(contains('CHAPTER TWO')));
      expect(textOf(withEvidence), isNot(contains('THE LONG ROAD')));
      expect(withEvidence.pageStarts.map((p) => p.pageIndex), [0, 1, 2]);

      // Alone, the three pages show "CHAPTER TWO" once: it stays. A
      // leftover header is the price of never deleting a line on a hunch.
      final alone = analyze(pages.sublist(0, 3));
      expect(textOf(alone), contains('CHAPTER TWO'));
      expect(textOf(alone), isNot(contains('THE LONG ROAD')));
    });

    test('evidence pages are read but never emitted', () {
      final t = book(header: (i) => 'THE LONG ROAD');
      fill(t);
      final pages = t.build();
      final middle = analyze(pages.sublist(0, 5), firstPage: 2, lastPage: 3);
      final all = analyze(pages.sublist(0, 5));
      expect(middle.pageStarts.map((p) => p.pageIndex), [2, 3]);
      final from = all.pageStarts[2].startWordIndex;
      final to = all.pageStarts[4].startWordIndex;
      expect(wordsOf(middle), wordsOf(all).sublist(from, to));
    });

    test('page numbers are recognised in their usual dress', () {
      final shapes = ['12', '– 13 –', 'Page 14', '15 of 300', '[16]', 'xvii'];
      final pages = <PdfRawPage>[];
      for (var i = 0; i < shapes.length; i++) {
        final page = PageBuilder(i);
        block(page, kFiller);
        page.line(shapes[i], x: 190, y: 40);
        pages.add(page.build());
      }
      final result = analyze(pages);
      expect(
        paragraphTexts(result),
        List<String>.filled(shapes.length, kFillerText),
      );
    });

    test('a number with a full stop, or set as a title, is text even when '
        'it stands alone at the edge of the page', () {
      final foot = PageBuilder(0);
      block(foot, kFiller);
      foot.line('1984.', x: 190, y: 40);
      expect(textOf(analyze([foot.build()])), endsWith('a word. 1984.'));

      final title = PageBuilder(0)..line('1984', x: 150, y: 540, size: 30);
      block(title, kFiller, y: 480);
      expect(headingsOf(analyze([title.build()])), ['h1 1984']);
    });

    test('a chapter numeral is not mistaken for the page number when the '
        'page shows its number elsewhere', () {
      final pages = <PdfRawPage>[];
      for (var i = 0; i < 3; i++) {
        final page = PageBuilder(i);
        if (i == 1) page.line('II', x: 190, y: 540);
        block(page, kFiller, y: 500);
        page.line('${i + 12}', x: 190, y: 40);
        pages.add(page.build());
      }
      final result = analyze(pages);
      expect(headingsOf(result), ['h3 II']);
      expect(textOf(result), isNot(matches(RegExp(r'\b1[234]\b'))));
    });

    test('a lone page number at the top of a page is removed too', () {
      final page = PageBuilder(0)..line('ii', y: 560);
      final result = analyze([page.build()]);
      expect(result.sentences, isEmpty);
      expect(result.pageStarts.single.firstWords, '');
    });

    test('a number that ends a sentence, or that sits in the text, is not '
        'a page number', () {
      // Text running to the foot of the page; its last line is a number.
      final rows = <String>[
        for (var i = 0; i < 12; i++) ...kFiller.take(2),
        'They agreed that it must have happened in the autumn of',
      ];
      final sentence = PageBuilder(0);
      final y = block(sentence, rows, y: 348);
      sentence.line('1984.', y: y);
      expect(y, lessThan(90), reason: 'the last line is in the bottom zone');
      expect(textOf(analyze([sentence.build()])), endsWith('autumn of 1984.'));

      // The same number without the stop, still part of the paragraph.
      final bare = PageBuilder(0);
      bare.line('1984', y: block(bare, rows, y: 348));
      expect(textOf(analyze([bare.build()])), endsWith('autumn of 1984'));
    });

    test('a line that opens several pages but leads straight into the '
        'text is not furniture', () {
      // A speaker's name at the head of three pages of a play.
      final pages = <PdfRawPage>[];
      for (var i = 0; i < 3; i++) {
        final page = PageBuilder(i)..line('HAMLET.', y: 540);
        block(page, kFiller, y: 528);
        pages.add(page.build());
      }
      final words = wordsOf(analyze(pages));
      expect(words.where((w) => w == 'HAMLET.').length, 3);
    });

    test('chapter headings at the top of their pages are not a running '
        'head, although only their number changes', () {
      final pages = <PdfRawPage>[];
      for (var i = 0; i < 4; i++) {
        final page = PageBuilder(i)..line('Chapter ${i + 1}', y: 540, size: 18);
        block(page, kFiller, y: 500);
        pages.add(page.build());
      }
      expect(headingsOf(analyze(pages)), [
        'h1 Chapter 1',
        'h1 Chapter 2',
        'h1 Chapter 3',
        'h1 Chapter 4',
      ]);
    });

    test('at most two lines are removed from one zone', () {
      // Three lines repeat at the head of every page. Only the outermost
      // two can be furniture; the third stays although it repeats too.
      final pages = <PdfRawPage>[];
      for (var i = 0; i < 4; i++) {
        final page = PageBuilder(i)
          ..line('SOCIETY PROCEEDINGS', y: 572)
          ..line('VOLUME NINE', y: 560)
          ..line('AUTUMN SESSION', y: 530);
        block(page, kFiller, y: 500);
        pages.add(page.build());
      }
      final text = textOf(analyze(pages));
      expect(text, isNot(contains('SOCIETY PROCEEDINGS')));
      expect(text, isNot(contains('VOLUME NINE')));
      expect('AUTUMN SESSION'.allMatches(text).length, 4);
    });

    test('a head that runs straight into more lines is left alone', () {
      // Nothing sets the top two lines apart from the third, so nothing
      // says where furniture ends and text begins: all of it stays.
      final pages = <PdfRawPage>[];
      for (var i = 0; i < 4; i++) {
        final page = PageBuilder(i)
          ..line('SOCIETY PROCEEDINGS', y: 572)
          ..line('VOLUME NINE', y: 560)
          ..line('AUTUMN SESSION', y: 548);
        block(page, kFiller, y: 500);
        pages.add(page.build());
      }
      final text = textOf(analyze(pages));
      expect('SOCIETY PROCEEDINGS'.allMatches(text).length, 4);
      expect('VOLUME NINE'.allMatches(text).length, 4);
      expect('AUTUMN SESSION'.allMatches(text).length, 4);
    });
  });

  group('text that does not run horizontally', () {
    test('a watermark up the margin is dropped', () {
      final page = PageBuilder(0);
      block(page, kFiller);
      page.vertical(
        'arXiv:1706.03762v7 [cs.CL] 2 Aug 2023',
        x: 16,
        y: 150,
        size: 14,
      );
      final result = analyze([page.build()]);
      expect(paragraphTexts(result), [kFillerText]);
    });

    test('short vertical labels in a figure are dropped as well', () {
      final page = PageBuilder(0);
      block(page, kFiller);
      page
        ..vertical('of', x: 120, y: 300)
        ..vertical('the', x: 132, y: 300)
        ..vertical('making', x: 144, y: 300);
      expect(paragraphTexts(analyze([page.build()])), [kFillerText]);
    });

    test('a page set mostly sideways keeps its text', () {
      // A vertical script, or a table printed along the page: this is the
      // page's text, not decoration, and must not vanish.
      final page = PageBuilder(0)
        ..vertical('first column of the table', x: 100, y: 100)
        ..vertical('second column of the table', x: 120, y: 100)
        ..line('Table 3', x: 50, y: 500);
      final text = textOf(analyze([page.build()]));
      expect(text, contains('first column of the table'));
      expect(text, contains('second column of the table'));
      expect(text, contains('Table 3'));
    });
  });

  group('drop caps', () {
    PageBuilder opening(void Function(PageBuilder page) capAndFirstRow) {
      final page = PageBuilder(0)..line('Chapter 1', y: 520, size: 18);
      capAndFirstRow(page);
      return page;
    }

    test('a drop cap on its own line rejoins its word', () {
      final page = opening((page) {
        page.line('I', y: 466, size: 27);
        page.words(
          'n my younger and more vulnerable years my father'.split(' '),
          x: 66,
          y: 478,
          justifyTo: kRight,
        );
      });
      page.words(
        'gave me some advice that I have been turning over'.split(' '),
        x: 66,
        y: 466,
        justifyTo: kRight,
      );
      block(page, [
        'in my mind ever since, and which I pass on to you here.',
        r'It was not much.$',
        '>He did not say any more, but the two of us have always',
        'been unusually communicative in a reserved sort of way.',
      ], y: 454);

      final result = analyze([page.build()]);
      expect(headingsOf(result), ['h1 Chapter 1']);
      expect(paragraphTexts(result).sublist(1), [
        'In my younger and more vulnerable years my father gave me some '
            'advice that I have been turning over in my mind ever since, and '
            'which I pass on to you here. It was not much.',
        'He did not say any more, but the two of us have always been '
            'unusually communicative in a reserved sort of way.',
      ]);
    });

    test('a drop cap that is a word by itself stays one', () {
      final page = opening((page) {
        page.line('I', y: 466, size: 27);
        page.words(
          'am by birth a Genevese, and my family is one of'.split(' '),
          x: 66,
          y: 478,
          justifyTo: kRight,
        );
      });
      page.words(
        'the most distinguished of that republic, as I am'.split(' '),
        x: 66,
        y: 466,
        justifyTo: kRight,
      );
      block(page, [r'told by those who should know such things.$'], y: 454);

      final result = analyze([page.build()]);
      expect(textOf(result), contains('I am by birth a Genevese,'));
    });

    test('a drop cap inside its line does not make the line a heading, '
        'nor the lines beside it a new paragraph', () {
      final page = opening((page) {
        // pdfium often reports the large letter and the first row as one
        // line: the letter hangs below the row's baseline.
        page.run('A', x: 50, y: 466, size: 27);
        page.words(
          'bout half way between the town and the river'.split(' '),
          x: 66,
          y: 478,
          justifyTo: kRight,
        );
      });
      page.words(
        'Mouth the road joins the railway and runs beside'.split(' '),
        x: 66,
        y: 466,
        justifyTo: kRight,
      );
      block(page, [r'it for a quarter of a mile.$'], y: 454);

      final result = analyze([page.build()]);
      expect(headingsOf(result), ['h1 Chapter 1']);
      expect(paragraphTexts(result).last, startsWith('About half way between'));
      expect(paragraphTexts(result).last, endsWith('a quarter of a mile.'));
      expect(result.sentences.where((s) => s.startsParagraph).length, 2);
    });

    test('a raised initial does not make its line a heading', () {
      final page = PageBuilder(0);
      block(page, kFiller);
      page
        ..run('O', x: 50, y: 440, size: 25)
        ..words(
          'nce there was a lamp at the end of the quay'.split(' '),
          x: 64,
          y: 440,
          justifyTo: kRight,
        );
      block(page, [r'that nobody remembered lighting.$'], y: 428);
      final result = analyze([page.build()]);
      expect(headingsOf(result), isEmpty);
      expect(textOf(result), contains('Once there was a lamp'));
    });
  });

  group('headings', () {
    test('are recognised by size, and the size sets the level', () {
      final t = Typesetter()
        ..heading('The Long Road', size: 18)
        ..paragraph(Prose(1).paragraph(3))
        ..heading('A Night Crossing', size: 14)
        ..paragraph(Prose(2).paragraph(3))
        ..heading('The far bank', size: 12)
        ..paragraph(Prose(3).paragraph(3));
      final result = analyze(t.build());
      expect(headingsOf(result), [
        'h1 The Long Road',
        'h2 A Night Crossing',
        'h3 The far bank',
      ]);
      for (final s in result.sentences.where((s) => s.isHeading)) {
        expect(s.startsParagraph, isTrue);
      }
    });

    test('a heading is one sentence, whatever punctuation it holds', () {
      final t = Typesetter()
        ..heading('1. The Arrival. Mr. Wren?', size: 18)
        ..paragraph(Prose(4).paragraph(2));
      final result = analyze(t.build());
      expect(result.sentences.first.words, [
        '1.',
        'The',
        'Arrival.',
        'Mr.',
        'Wren?',
      ]);
      expect(result.sentences.first.heading, 1);
    });

    test('a title wrapped over two lines is one heading; a label and a '
        'title of different sizes are two', () {
      final wrapped = PageBuilder(0)
        ..line('Adventures in the', y: 480, size: 20)
        ..line('Northern Marshes', y: 454, size: 20);
      block(wrapped, kFiller, y: 420);
      expect(headingsOf(analyze([wrapped.build()])), [
        'h1 Adventures in the Northern Marshes',
      ]);

      final stacked = PageBuilder(0)
        ..line('CHAPTER IV', y: 480, size: 12)
        ..line('The Northern Marshes', y: 456, size: 20);
      block(stacked, kFiller, y: 420);
      expect(headingsOf(analyze([stacked.build()])), [
        'h3 CHAPTER IV',
        'h1 The Northern Marshes',
      ]);
    });

    test('a large title hyphenated across lines is rejoined', () {
      final page = PageBuilder(0)
        ..run('The Complete Proceed', x: 50, y: 480, size: 20)
        ..hyphenMark(50 + 20 * advance(20), 480, 20)
        ..line('ings of the Society', y: 454, size: 20);
      block(page, [
        ...kFiller.take(2),
        r'The proceedings were read aloud.$',
      ], y: 420);
      expect(headingsOf(analyze([page.build()])), [
        'h1 The Complete Proceedings of the Society',
      ]);
    });

    test('several lines of large type that read as a sentence are text', () {
      final page = PageBuilder(0)
        ..line('Provided proper attribution is given, the', y: 520, size: 12)
        ..line('society grants permission to reproduce the', y: 504, size: 12)
        ..line('tables in this paper for scholarly works.', y: 488, size: 12);
      block(page, kFiller, y: 440);
      block(page, kFiller, y: 392);
      final result = analyze([page.build()]);
      expect(headingsOf(result), isEmpty);
      expect(textOf(result), startsWith('Provided proper attribution'));
    });

    test('the short last line of a paragraph is not a heading', () {
      // Lines with no capital, digit or ascender to measure: a naive
      // measure reads the dot of an i or the tail of a Q as large type.
      for (final last in [r'it.$', r'Quite so.$', r'year it is?”$', r'pé.’$']) {
        final page = PageBuilder(0);
        block(page, [...kFiller.take(2), last]);
        block(page, kFiller, y: 452);
        final result = analyze([page.build()]);
        expect(headingsOf(result), isEmpty, reason: last);
      }
    });

    test('are recognised by their wording when they stand apart', () {
      final cases = <String, int>{
        'CHAPTER II': 3,
        'Chapter Seven': 3,
        'Part 2: The Voyage': 3,
        'Epilogue': 3,
        'IV': 3,
        'THE LAST DAY': 3,
        '3.2 Scaled Attention': 4,
        '3.2.1 Dot Products': 5,
      };
      cases.forEach((line, level) {
        final page = PageBuilder(0);
        block(page, kFiller);
        page.line(line, y: 440);
        block(page, kFiller, y: 416);
        expect(headingsOf(analyze([page.build()])), [
          'h$level $line',
        ], reason: line);
      });
    });

    test('the same wording inside the flow of the text is text', () {
      // No space around it: the line is part of the paragraph.
      final inFlow = PageBuilder(0);
      block(inFlow, [...kFiller.take(2), r'CHAPTER II$', ...kFiller]);
      expect(headingsOf(analyze([inFlow.build()])), isEmpty);

      // Set apart, but a sentence: "Part 2 was worse than the first."
      for (final line in [
        'Part 2 was worse than the first.',
        '“NO!”',
        'IN THE MEANTIME,',
      ]) {
        final page = PageBuilder(0);
        block(page, kFiller);
        page.line(line, y: 440);
        block(page, kFiller, y: 416);
        final result = analyze([page.build()]);
        expect(headingsOf(result), isEmpty, reason: line);
        expect(textOf(result), contains(line));
      }
    });
  });

  group('contents pages', () {
    PageBuilder contents() {
      final page = PageBuilder(0)..line('Contents', y: 520, size: 18);
      var y = 480.0;
      for (final row in [
        'The Outset . . . . . . . . . . . . . . . . . . 1',
        'CHAPTER I.',
        '  Down the River . . . . . . . . . . . . . . . 4',
        'CHAPTER II.',
        '  The Long Road ................................ 9',
        'Preface to the Second Edition … … … … … … … … xi',
        'Index 212',
      ]) {
        final indent = row.length - row.trimLeft().length;
        page.line(row.trim(), x: kLeft + indent * 6, y: y);
        y -= kPitch;
      }
      return page;
    }

    test('dot leaders collapse and each entry is one paragraph', () {
      final result = analyze([contents().build()]);
      expect(paragraphTexts(result), [
        '# Contents',
        'The Outset 1',
        'CHAPTER I. Down the River 4',
        'CHAPTER II. The Long Road 9',
        'Preface to the Second Edition xi',
        'Index 212',
      ]);
    });

    test('an entry is one sentence and never a heading', () {
      final result = analyze([contents().build()]);
      expect(headingsOf(result), ['h1 Contents']);
      expect(result.sentences.length, 6);
      for (final s in result.sentences) {
        expect(s.startsParagraph, isTrue);
        expect(s.words.any((w) => RegExp(r'^[.…·]+$').hasMatch(w)), isFalse);
      }
    });

    test('an ellipsis in prose is not a contents row', () {
      final page = PageBuilder(0);
      block(page, [
        'He waited by the gate for an hour. . . . Nothing came of',
        r'it, and he went home.$',
      ]);
      final result = analyze([page.build()]);
      expect(result.sentences.where((s) => s.startsParagraph).length, 1);
      expect(textOf(result), contains('for an hour… Nothing came'));
    });
  });

  group('paragraphs', () {
    List<String> write(Typesetter t, {int count = 7, int seed = 11}) {
      final prose = Prose(seed);
      final written = <String>[];
      for (var i = 0; i < count; i++) {
        final text = prose.paragraph(2 + i % 3);
        written.add(text);
        t.paragraph(text);
      }
      return written;
    }

    test('are found by their first-line indent', () {
      final t = Typesetter(indent: 12);
      final written = write(t);
      expect(paragraphTexts(analyze(t.build())), written);
    });

    test('are found by the space between them', () {
      final t = Typesetter(paragraphGap: 7);
      final written = write(t);
      expect(paragraphTexts(analyze(t.build())), written);
    });

    test('are found in ragged-right text too', () {
      final t = Typesetter(indent: 12, justify: false);
      final written = write(t);
      expect(paragraphTexts(analyze(t.build())), written);
    });

    test('margins that alternate by page do not look like indents', () {
      final t = Typesetter(
        indent: 12,
        bottom: 380,
        leftFor: (i) => i.isEven ? 50 : 70,
      );
      final written = write(t, count: 12);
      final pages = t.build();
      expect(pages.length, greaterThan(2));
      expect(paragraphTexts(analyze(pages)), written);
    });

    test('a short last line that ends a sentence closes its paragraph '
        'when nothing else marks the break', () {
      final page = PageBuilder(0);
      block(page, [
        ...kFiller,
        'The station clerk remembered every letter from the coast',
        r'long after the others had gone.$',
      ]);
      expect(paragraphTexts(analyze([page.build()])), [
        kFillerText,
        'The station clerk remembered every letter from the coast long '
            'after the others had gone.',
      ]);
    });

    test('a list item that wraps under a hanging indent is one paragraph', () {
      // Continuation rows sit further in than the bullet row; being
      // indented does not make them paragraphs.
      final page = PageBuilder(0);
      block(page, kFiller);
      block(
        page,
        ['• The encoder holds layers in which all of the keys,'],
        x: 62,
        y: 440,
      );
      block(
        page,
        [
          'values and queries come from the previous layer, and',
          r'Each position can attend to every other one.$',
        ],
        x: 72,
        y: 428,
      );
      final paragraphs = paragraphTexts(analyze([page.build()]));
      expect(paragraphs, [
        kFillerText,
        '• The encoder holds layers in which all of the keys, values and '
            'queries come from the previous layer, and Each position can '
            'attend to every other one.',
      ]);
    });

    test('lines of verse stay separate', () {
      final page = PageBuilder(0);
      block(page, kFiller);
      var y = 440.0;
      for (final verse in [
        'How doth the little crocodile',
        'Improve his shining tail',
        'And pour the waters of the Nile',
        'On every golden scale',
      ]) {
        page.line(verse, x: 80, y: y);
        y -= kPitch;
      }
      block(page, kFiller, y: y - 8);
      expect(paragraphTexts(analyze([page.build()])), [
        kFillerText,
        'How doth the little crocodile',
        'Improve his shining tail',
        'And pour the waters of the Nile',
        'On every golden scale',
        kFillerText,
      ]);
    });

    test('a row of asterisks stands alone between two paragraphs', () {
      final page = PageBuilder(0);
      block(page, kFiller);
      page.line('* * *', x: 180, y: 452);
      block(page, kFiller, y: 428);
      final result = analyze([page.build()]);
      expect(paragraphTexts(result), [kFillerText, '* * *', kFillerText]);

      // A printer's flower (U+2766) does the same job.
      final flower = ch(0x2766);
      final ornate = PageBuilder(0);
      block(ornate, kFiller);
      ornate.line(flower, x: 195, y: 452);
      block(ornate, kFiller, y: 428);
      expect(paragraphTexts(analyze([ornate.build()])), [
        kFillerText,
        flower,
        kFillerText,
      ]);
    });

    test('rows of a list each begin a paragraph', () {
      final page = PageBuilder(0)..line('Contents', y: 520, size: 18);
      var y = 480.0;
      for (final row in [
        'CHAPTER I. Down the Rabbit-Hole',
        'CHAPTER II. The Pool of Tears',
        'CHAPTER III. A Caucus-Race and a Long Tale',
      ]) {
        page.line(row, x: 80, y: y);
        y -= kPitch;
      }
      expect(paragraphTexts(analyze([page.build()])), [
        '# Contents',
        'CHAPTER I. Down the Rabbit-Hole',
        'CHAPTER II. The Pool of Tears',
        'CHAPTER III. A Caucus-Race and a Long Tale',
      ]);
    });
  });

  group('two columns', () {
    test('a paragraph runs from the foot of one column to the head of '
        'the next, and columns are not shredded into lines', () {
      final page = PageBuilder(0);
      block(
        page,
        [
          '>The ferry left before the sun',
          'was up and nobody on the quay',
          r'had thought to wake the boy.$',
          '>He ran along the wall until he',
          'reached the steps, and there he',
        ],
        x: 30,
        right: 190,
      );
      block(
        page,
        [
          'stopped to watch the lanterns',
          r'go out one after another.$',
          '>By noon the town had heard',
          r'the story twice over.$',
        ],
        x: 210,
        right: 370,
      );
      expect(paragraphTexts(analyze([page.build()])), [
        'The ferry left before the sun was up and nobody on the quay had '
            'thought to wake the boy.',
        'He ran along the wall until he reached the steps, and there he '
            'stopped to watch the lanterns go out one after another.',
        'By noon the town had heard the story twice over.',
      ]);
    });
  });

  group('page starts', () {
    test('one per page, at the first word on the page, mid-sentence or '
        'not', () {
      final t = Typesetter(indent: 12, bottom: 380, footer: (i) => '${i + 1}');
      final prose = Prose(21);
      for (var i = 0; i < 12; i++) {
        t.paragraph(prose.paragraph(3));
      }
      final pages = t.build();
      final result = analyze(pages);
      final words = wordsOf(result);

      expect(result.pageStarts.map((p) => p.pageIndex), [
        for (final p in pages) p.pageIndex,
      ]);
      var midSentence = 0;
      for (final start in result.pageStarts) {
        final expected = t.firstWordOfPage[start.pageIndex]!;
        expect(words[start.startWordIndex], expected);
        expect(start.firstWords.split(' ').first, expected);
        expect(start.firstWords.split(' ').length, lessThanOrEqualTo(5));

        // The sentence index names the sentence holding that word.
        var before = 0;
        for (var s = 0; s < start.startSentenceIndex; s++) {
          before += result.sentences[s].words.length;
        }
        final sentence = result.sentences[start.startSentenceIndex];
        expect(start.startWordIndex, greaterThanOrEqualTo(before));
        expect(start.startWordIndex, lessThan(before + sentence.words.length));
        if (start.startWordIndex > before) midSentence++;
      }
      expect(
        midSentence,
        greaterThan(0),
        reason: 'the fixture breaks pages mid-sentence',
      );
    });

    test('a word hyphenated across the page break is one word, and the '
        'page starts at it', () {
      final first = PageBuilder(0);
      block(first, [
        'The lighthouse keeper had read every book on the shelf,',
        'but the letters from the mainland were beyond his under-',
      ]);
      final second = PageBuilder(1);
      block(second, [
        r'standing, and so he kept them in a tin box by the door.$',
      ]);
      final result = analyze([first.build(), second.build()]);
      final words = wordsOf(result);
      expect(textOf(result), contains('beyond his understanding, and so he'));
      expect(result.sentences.length, 1);
      final start = result.pageStarts[1];
      expect(words[start.startWordIndex], 'understanding,');
      expect(start.startSentenceIndex, 0);
      expect(start.firstWords, 'understanding, and so he kept');
    });

    test('a page without text starts where the next text starts', () {
      final t = Typesetter(indent: 12)..paragraph(Prose(5).paragraph(3));
      t.blankPage();
      t.paragraph(Prose(6).paragraph(3));
      t.pageBreak();
      t.blankPage();
      final result = analyze(t.build());
      final starts = result.pageStarts;
      expect(starts.length, 4);
      expect(starts[1].firstWords, '');
      expect(starts[1].startWordIndex, starts[2].startWordIndex);
      expect(starts[1].startSentenceIndex, starts[2].startSentenceIndex);
      expect(starts[3].firstWords, '');
      expect(starts[3].startWordIndex, wordsOf(result).length);
      expect(starts[3].startSentenceIndex, result.sentences.length);
    });
  });

  group('range edges', () {
    // One sentence that fills several pages: every page break falls inside
    // it.
    List<PdfRawPage> oneLongSentence() {
      final t = Typesetter(indent: 12, bottom: 380);
      final clause = Prose(31);
      final parts = <String>[
        for (var i = 0; i < 40; i++)
          clause.sentence().replaceAll('.', i == 39 ? '.' : ','),
      ];
      t.paragraph(parts.join(' '));
      return t.build();
    }

    test('a range that opens mid-sentence says so', () {
      final pages = oneLongSentence();
      expect(pages.length, greaterThan(4));
      final tail = analyze(pages, firstPage: 2, lastPage: 3);
      expect(tail.continuesPrevious, isTrue);
      expect(tail.sentences.first.startsParagraph, isFalse);

      final head = analyze(pages, firstPage: 0, lastPage: 1);
      expect(head.continuesPrevious, isFalse);
      expect(head.sentences.first.startsParagraph, isTrue);
    });

    test('a range that opens on a new paragraph does not', () {
      final t = Typesetter(indent: 12, bottom: 380);
      final prose = Prose(8);
      final written = <String>[];
      for (var i = 0; i < 3; i++) {
        final text = prose.paragraph(4);
        written.add(text);
        t
          ..paragraph(text)
          ..pageBreak();
      }
      final pages = t.build();
      expect(pages.length, 3);
      final second = analyze(pages, firstPage: 1, lastPage: 1);
      expect(second.continuesPrevious, isFalse);
      expect(second.endsWithSplitWord, isFalse);
      expect(paragraphTexts(second), [written[1]]);
      expect(second.sentences.first.startsParagraph, isTrue);
    });

    test('without the page before it, a range falls back on how its first '
        'line looks', () {
      final pages = oneLongSentence();
      final blind = analyze([pages[2], pages[3]]);
      expect(pages[2].pageIndex, 2);
      // Lower-case and not indented: it continues something.
      expect(blind.continuesPrevious, isTrue);
    });

    group('a word hyphenated across the end of a range', () {
      PdfRawPage first() {
        final page = PageBuilder(0);
        block(page, [
          'The lighthouse keeper had read every book on the shelf,',
          'but the letters from the mainland were beyond his under-',
        ]);
        return page.build();
      }

      PdfRawPage second() {
        final page = PageBuilder(1);
        block(page, [
          r'standing, and so he kept them in a tin box by the door.$',
        ]);
        return page.build();
      }

      test('keeps the split-word marker until the ranges are merged', () {
        final pages = [first(), second()];
        final head = analyze(pages, firstPage: 0, lastPage: 0);
        expect(head.endsWithSplitWord, isTrue);
        expect(head.sentences.last.words.last, 'under$kSplitWordMarker');

        final tail = analyze(pages, firstPage: 1, lastPage: 1);
        expect(tail.continuesPrevious, isTrue);
        expect(tail.sentences.first.words.first, 'standing,');
        // The page is labelled as it will read once merged.
        expect(tail.pageStarts.single.firstWords, startsWith('understanding,'));

        ExtractedDocument doc(PdfLayoutResult r) => ExtractedDocument(
          sentences: r.sentences,
          pageBoundaries: [
            for (final p in r.pageStarts)
              PageBoundary(
                pageNumber: p.pageIndex,
                startSentenceIndex: p.startSentenceIndex,
                startWordIndex: p.startWordIndex,
                firstWords: p.firstWords,
              ),
          ],
          continuesPrevious: r.continuesPrevious,
        );
        final merged = doc(head).merge(doc(tail));
        final whole = analyze(pages);
        expect(merged.allWords, wordsOf(whole));
        expect(merged.sentences.length, whole.sentences.length);
        expect(
          merged.pageBoundaries.map((b) => b.startWordIndex),
          whole.pageStarts.map((p) => p.startWordIndex),
        );
        expect(
          merged.pageBoundaries.map((b) => b.startSentenceIndex),
          whole.pageStarts.map((p) => p.startSentenceIndex),
        );
      });

      test('is left as written when a heading follows instead', () {
        final next = PageBuilder(1)..line('Chapter 2', y: 500, size: 18);
        block(next, kFiller, y: 460);
        final head = analyze(
          [first(), next.build()],
          firstPage: 0,
          lastPage: 0,
        );
        expect(head.endsWithSplitWord, isFalse);
        expect(head.sentences.last.words.last, 'under-');
      });

      test('keeps the marker when nothing is known of what follows', () {
        final head = analyze([first()]);
        expect(head.endsWithSplitWord, isTrue);
        expect(head.sentences.last.words.last, 'under$kSplitWordMarker');
      });
    });
  });

  group('outline', () {
    List<PdfRawPage> twoChapters() {
      final t = Typesetter(indent: 12, bottom: 380)
        ..heading('Chapter 1', size: 18)
        ..paragraph(Prose(41).paragraph(6))
        ..pageBreak()
        ..heading('Chapter 2', size: 18)
        ..paragraph(Prose(42).paragraph(4));
      return t.build();
    }

    int wordIndexOf(PdfLayoutResult result, String heading) {
      var index = 0;
      for (final s in result.sentences) {
        if (s.isHeading && s.words.join(' ') == heading) return index;
        index += s.words.length;
      }
      fail('no heading "$heading"');
    }

    test('a bookmark lands on the heading just below its position', () {
      final pages = twoChapters();
      final result = analyze(
        pages,
        outline: const [
          PdfOutlineTarget(title: 'The Book', pageIndex: 0),
          PdfOutlineTarget(
            title: 'Chapter 1',
            pageIndex: 0,
            depth: 1,
            top: 520,
            left: 0,
          ),
          PdfOutlineTarget(
            title: 'Chapter 2',
            pageIndex: 1,
            depth: 1,
            top: 520,
            left: 0,
          ),
        ],
      );
      expect(result.outline.map((e) => e.title), [
        'The Book',
        'Chapter 1',
        'Chapter 2',
      ]);
      expect(result.outline.map((e) => e.depth), [0, 1, 1]);
      expect(
        result.outline[1].startWordIndex,
        wordIndexOf(result, 'Chapter 1'),
      );
      expect(
        result.outline[2].startWordIndex,
        wordIndexOf(result, 'Chapter 2'),
      );
      final second = result.sentences[result.outline[2].startSentenceIndex];
      expect(second.words, ['Chapter', '2']);
      // No title on the page for "The Book": the page's first word.
      expect(result.outline[0].startWordIndex, 0);
      expect(result.outline.every((e) => e.type == null), isTrue);
    });

    test('a bookmark without a position is found by its title', () {
      final page = PageBuilder(0);
      block(page, kFiller);
      page.line('2 Background', y: 440, size: 12);
      block(page, kFiller, y: 416);
      final result = analyze(
        [page.build()],
        outline: const [PdfOutlineTarget(title: 'Background', pageIndex: 0)],
      );
      final entry = result.outline.single;
      expect(result.sentences[entry.startSentenceIndex].words, [
        '2',
        'Background',
      ]);
    });

    test('a bookmark naming a line of ordinary size makes it a heading', () {
      PageBuilder page() {
        final p = PageBuilder(0);
        block(p, kFiller);
        p.line('The Boy Who Waited', y: 440);
        block(p, kFiller, y: 416);
        return p;
      }

      final plain = analyze([page().build()]);
      expect(headingsOf(plain), isEmpty);

      final marked = analyze(
        [page().build()],
        outline: const [
          PdfOutlineTarget(
            title: 'The Boy Who Waited',
            pageIndex: 0,
            depth: 1,
            top: 452,
            left: 50,
          ),
        ],
      );
      expect(headingsOf(marked), ['h4 The Boy Who Waited']);
      expect(marked.outline.single.startSentenceIndex, 1);
    });

    test('a line that merely begins with a bookmark title is found, but is '
        'not made a heading', () {
      final page = PageBuilder(0);
      block(page, [
        'Introduction to the harbour and its people came late in',
        r'the book, long after the reader had met them all.$',
      ]);
      final result = analyze(
        [page.build()],
        outline: const [PdfOutlineTarget(title: 'Introduction', pageIndex: 0)],
      );
      expect(headingsOf(result), isEmpty);
      expect(result.sentences.length, 1);
      expect(result.outline.single.startWordIndex, 0);
    });

    test('a bookmark that points into running text marks the place '
        'without breaking the sentence', () {
      final page = PageBuilder(0);
      block(page, kFiller);
      final plain = analyze([page.build()]);
      final marked = analyze(
        [page.build()],
        outline: const [
          PdfOutlineTarget(title: 'Page 1', pageIndex: 0, top: 496, left: 0),
        ],
      );
      expect(sentenceTexts(marked), sentenceTexts(plain));
      expect(marked.outline.single.startSentenceIndex, 0);
      // The second line of the block begins with "before".
      expect(wordsOf(marked)[marked.outline.single.startWordIndex], 'before');
    });

    test('bookmarks outside the emitted pages are left out, and the rest '
        'come back in reading order', () {
      final pages = twoChapters();
      final result = analyze(
        pages,
        firstPage: 1,
        lastPage: 1,
        outline: const [
          PdfOutlineTarget(title: 'Chapter 2', pageIndex: 1, top: 520),
          PdfOutlineTarget(title: 'Chapter 1', pageIndex: 0, top: 520),
          PdfOutlineTarget(title: 'Nowhere', pageIndex: 9, top: 520),
        ],
      );
      expect(result.outline.map((e) => e.title), ['Chapter 2']);
      expect(result.outline.single.startWordIndex, 0);
    });

    test('a bookmark on a page without text points at the next text', () {
      final t = Typesetter(indent: 12)..paragraph(Prose(5).paragraph(2));
      t.blankPage();
      t.paragraph(Prose(6).paragraph(2));
      final result = analyze(
        t.build(),
        outline: const [PdfOutlineTarget(title: 'Plate I', pageIndex: 1)],
      );
      expect(
        result.outline.single.startWordIndex,
        result.pageStarts[2].startWordIndex,
      );
    });
  });

  group('robustness', () {
    test('no pages, and pages without text', () {
      expect(analyze(const []).sentences, isEmpty);
      expect(analyze(const []).pageStarts, isEmpty);

      final blank = analyze([
        PdfRawPage.empty(pageIndex: 0),
        PdfRawPage.empty(pageIndex: 1),
      ]);
      expect(blank.sentences, isEmpty);
      expect(blank.pageStarts.map((p) => p.startWordIndex), [0, 0]);
      expect(blank.continuesPrevious, isFalse);
      expect(blank.endsWithSplitWord, isFalse);
    });

    test('text without character boxes is still read', () {
      final page = PageBuilder(3);
      block(page, kFiller);
      final result = analyze([page.build(withBoxes: false)]);
      expect(textOf(result), kFillerText);
      expect(result.pageStarts.single.pageIndex, 3);
    });

    test('every word of a typeset book comes back, in order, once', () {
      final t = Typesetter(
        indent: 12,
        bottom: 300,
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
      // Seed chosen so that the flow hyphenates both inside pages and at
      // the foot of a page (asserted below).
      final prose = Prose(58);
      final written = <String>[];
      for (var chapter = 1; chapter <= 3; chapter++) {
        t.heading('Chapter $chapter', size: 18);
        written.add('# Chapter $chapter');
        for (var i = 0; i < 9; i++) {
          final text = prose.paragraph(2 + (i + chapter) % 4);
          written.add(text);
          t.paragraph(text);
        }
      }
      final pages = t.build();
      // The fixture exercises both kinds of hyphenation.
      expect(pages.any((p) => p.text.contains(kStx)), isTrue);
      expect(pages.any((p) => RegExp(r'[a-z]-\r\n').hasMatch(p.text)), isTrue);

      final result = analyze(pages);
      expect(paragraphTexts(result), written);
      expect(result.pageStarts.length, pages.length);
      for (final start in result.pageStarts) {
        expect(
          wordsOf(result)[start.startWordIndex],
          t.firstWordOfPage[start.pageIndex],
        );
      }
    });
  });
}
