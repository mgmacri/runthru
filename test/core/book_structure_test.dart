import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/book_structure.dart';
import 'package:runthru/services/models.dart';

/// Builds documents the way the extractors do: heading sentences, body
/// paragraphs, and the source's own navigation entries.
class _Doc {
  final sentences = <Sentence>[];
  final outline = <OutlineEntry>[];
  int words = 0;

  /// Adds a heading line; returns its first word index.
  int h(String text, [int level = 2]) {
    final at = words;
    final w = text.split(' ');
    sentences.add(Sentence(words: w, startsParagraph: true, heading: level));
    words += w.length;
    return at;
  }

  /// Adds a plain one-sentence paragraph; returns its first word index.
  int p(String text) {
    final at = words;
    final w = text.split(' ');
    sentences.add(Sentence(words: w, startsParagraph: true));
    words += w.length;
    return at;
  }

  /// Adds [count] words of running text as paragraphs of full sentences.
  int text(int count) {
    final at = words;
    var left = count;
    var first = true;
    while (left > 0) {
      final n = left < 12 ? left : 12;
      sentences.add(
        Sentence(
          words: [for (var i = 0; i < n - 1; i++) 'word', 'end.'],
          startsParagraph: first,
        ),
      );
      first = false;
      words += n;
      left -= n;
    }
    return at;
  }

  /// Adds a navigation entry pointing at the current position.
  void nav(String title, {int depth = 0, String? type}) {
    outline.add(
      OutlineEntry(
        title: title,
        startWordIndex: words,
        startSentenceIndex: sentences.length,
        depth: depth,
        type: type,
      ),
    );
  }

  /// Adds an untitled typed mark (a landmark) at the current position.
  void mark(String type) => nav('', type: type);

  ExtractedDocument build() =>
      ExtractedDocument(sentences: sentences, outline: outline);
}

/// Every word belongs to exactly one section, in order.
void _expectContiguous(BookStructure st) {
  expect(st.sections, isNotEmpty);
  expect(st.sections.first.start, 0);
  expect(st.sections.last.end, st.totalWords);
  for (var i = 0; i < st.sections.length; i++) {
    final s = st.sections[i];
    expect(s.index, i);
    expect(s.end, greaterThan(s.start), reason: 'section $i is empty');
    expect(s.textStart, inInclusiveRange(s.start, s.end));
    if (i > 0) expect(s.start, st.sections[i - 1].end);
  }
  // Kinds never go backwards: front, then body, then back.
  final order = st.sections.map((s) => s.kind.index).toList();
  expect(order, [...order]..sort());
}

List<String> _names(Iterable<BookSection> sections) => [
  for (final s in sections) s.displayName(fallback: '—'),
];

void main() {
  group('publisher navigation (EPUB contents, landmarks, types)', () {
    test('starts at the stated bodymatter and ends at backmatter', () {
      final d = _Doc();
      d.nav('Titlepage', type: 'frontmatter titlepage');
      d.h('Frankenstein', 1);
      d.p('By Mary Shelley.');
      d.nav('Imprint', type: 'frontmatter imprint');
      d.h('Imprint');
      d.text(180);
      d.nav('Introduction', type: 'frontmatter introduction');
      d.h('Introduction');
      d.text(2200);
      d.nav('Preface', type: 'frontmatter preface');
      d.h('Preface');
      d.text(500);
      d.nav('Frankenstein', type: 'frontmatter halftitlepage');
      d.h('Frankenstein');
      d.h('Or, The Modern Prometheus', 6);
      final letter1 = d.words;
      d.nav('Letter I', depth: 1, type: 'bodymatter chapter');
      d.h('Letter I');
      d.text(1200);
      d.nav('Chapter I', depth: 1, type: 'bodymatter chapter');
      d.h('Chapter I');
      d.text(1800);
      final sub = d.words;
      d.nav('Walton, in Continuation', depth: 2);
      d.h('Walton, in Continuation', 3);
      d.text(900);
      final notes = d.words;
      d.nav('Endnotes', type: 'backmatter endnotes');
      d.h('Endnotes');
      d.text(40);
      d.nav('Colophon', type: 'backmatter colophon');
      d.h('Colophon');
      d.text(160);

      final st = analyzeBookStructure(d.build());
      _expectContiguous(st);

      expect(st.bodyStart, letter1);
      expect(st.bodyEnd, notes);
      expect(_names(st.chapters), ['Letter I', 'Chapter I']);
      expect(st.chapters.first.headingWords, 2);
      expect(st.chapters.first.role, SectionRole.chapter);
      expect(st.hasChapters, isTrue);
      expect(st.hasFrontMatter, isTrue);
      expect(st.hasBackMatter, isTrue);

      // The author's introduction is front matter because the publisher
      // says where the text starts.
      final intro = st.sections.firstWhere((s) => s.title == 'Introduction');
      expect(intro.kind, SectionKind.front);
      expect(intro.role, SectionRole.introduction);

      // The half-title keeps its subtitle and stays front matter.
      final half = st.sections.lastWhere((s) => s.title == 'Frankenstein');
      expect(half.kind, SectionKind.front);
      expect(half.subtitle, 'Or, The Modern Prometheus');

      // A deeper entry inside a real chapter is a sub-heading, not a chapter.
      expect(st.subHeadings.map((h) => h.start), [sub]);
      expect(st.subHeadingAt(sub)!.text, 'Walton, in Continuation');
      expect(st.subHeadingAt(sub + 1), isNull);

      expect(st.skippedFrontTitles, contains('Preface'));
    });

    test('Project Gutenberg: header, contents and licence are skipped', () {
      final d = _Doc();
      d.mark('pg-header frontmatter');
      d.h('The Project Gutenberg eBook of Alice');
      d.text(120);
      d.p('*** START OF THE PROJECT GUTENBERG EBOOK ALICE ***');
      d.nav('Alice’s Adventures in Wonderland');
      d.h('Alice’s Adventures in Wonderland', 1);
      d.h('by Lewis Carroll');
      d.nav('Contents');
      d.h('Contents');
      d.p('CHAPTER I. Down the Rabbit-Hole');
      d.p('CHAPTER II. The Pool of Tears');
      final ch1 = d.words;
      d.nav('CHAPTER I. Down the Rabbit-Hole');
      d.h('CHAPTER I. Down the Rabbit-Hole');
      d.text(2100);
      d.nav('CHAPTER II. THE POOL OF TEARS');
      d.h('CHAPTER II. THE POOL OF TEARS');
      d.text(2000);
      d.h('THE END', 5);
      final footer = d.words;
      d.mark('pg-footer backmatter');
      d.p('*** END OF THE PROJECT GUTENBERG EBOOK ALICE ***');
      d.text(200);
      d.nav('THE FULL PROJECT GUTENBERG™ LICENSE');
      d.h('THE FULL PROJECT GUTENBERG™ LICENSE');
      d.text(2600);

      final st = analyzeBookStructure(d.build());
      _expectContiguous(st);

      expect(st.bodyStart, ch1);
      expect(st.bodyEnd, footer);
      expect(st.chapters.length, 2);

      final first = st.chapters.first;
      expect(first.label, 'Chapter I');
      expect(first.title, 'Down the Rabbit-Hole');
      expect(first.overline, 'Chapter I');
      expect(first.headline, 'Down the Rabbit-Hole');
      expect(first.headingWords, 5);
      expect(first.textStart, ch1 + 5);
      expect(first.displayName(), 'Chapter I: Down the Rabbit-Hole');

      // ALL CAPS headings are shown in title case; the numeral stays.
      expect(st.chapters[1].label, 'Chapter II');
      expect(st.chapters[1].title, 'The Pool of Tears');

      // The title page keeps the byline as its subtitle.
      final titlePage = st.sections.firstWhere(
        (s) => s.title.startsWith('Alice'),
      );
      expect(titlePage.kind, SectionKind.front);
      expect(titlePage.subtitle, 'by Lewis Carroll');

      final licence = st.sections.last;
      expect(licence.kind, SectionKind.back);
      expect(licence.role, SectionRole.license);
    });

    test('a lone child under a heading is its subtitle, not a chapter', () {
      final d = _Doc();
      d.nav('CHAPTER 1. Loomings.');
      d.h('CHAPTER 1. Loomings.');
      d.text(900);
      final epilogue = d.words;
      d.nav('Epilogue');
      d.h('Epilogue');
      d.nav('“AND I ONLY AM ESCAPED” Job.', depth: 1);
      d.h('“AND I ONLY AM ESCAPED” Job.', 3);
      d.text(300);

      final st = analyzeBookStructure(d.build());
      _expectContiguous(st);
      expect(st.chapters.length, 2);
      final last = st.chapters.last;
      expect(last.start, epilogue);
      expect(last.title, 'Epilogue');
      expect(last.subtitle, '“AND I ONLY AM ESCAPED” Job');
      expect(last.role, SectionRole.epilogue);
      expect(last.kind, SectionKind.body);
      // Both heading lines are skipped by the reader.
      expect(last.headingWords, 1 + 6);
      expect(st.chapters.first.label, 'Chapter 1');
      expect(st.chapters.first.title, 'Loomings');
    });

    test('a contents title without a heading in the text still counts', () {
      final d = _Doc();
      d.nav('Chapter One');
      d.p('Chapter One'); // a plain paragraph, not a heading element
      d.text(700);
      d.nav('Dedication');
      d.p('To my mother, who read to me.'); // text does not repeat the title
      d.text(40);
      d.nav('Chapter Two');
      d.p('Chapter Two');
      d.text(700);

      final st = analyzeBookStructure(d.build());
      _expectContiguous(st);
      final one = st.sections.firstWhere((s) => s.label == 'Chapter One');
      expect(one.headingWords, 2);
      final dedication = st.sections.firstWhere((s) => s.title == 'Dedication');
      expect(dedication.headingWords, 0);
    });

    test('parts that only group chapters fold into their first chapter', () {
      final d = _Doc();
      final part1 = d.words;
      d.nav('Part One');
      d.h('Part One', 1);
      d.nav('Chapter 1', depth: 1);
      d.h('Chapter 1');
      d.text(800);
      d.nav('Chapter 2', depth: 1);
      d.h('Chapter 2');
      d.text(800);
      final part2 = d.words;
      d.nav('Part Two');
      d.h('Part Two', 1);
      d.nav('Chapter 3', depth: 1);
      d.h('Chapter 3');
      d.text(800);
      d.nav('Chapter 4', depth: 1);
      d.h('Chapter 4');
      d.text(800);

      final st = analyzeBookStructure(d.build());
      _expectContiguous(st);
      expect(_names(st.chapters), [
        'Chapter 1',
        'Chapter 2',
        'Chapter 3',
        'Chapter 4',
      ]);
      expect(st.chapters[0].start, part1);
      expect(st.chapters[0].groupTitle, 'Part One');
      expect(st.chapters[0].headingWords, 4);
      expect(st.chapters[1].groupTitle, isNull);
      expect(st.chapters[2].start, part2);
      expect(st.chapters[2].groupTitle, 'Part Two');
      expect(st.bodyStart, 0);
    });

    test('back matter named only by a heading in the tail is cut off', () {
      final d = _Doc();
      d.nav('Introduction');
      d.h('1 Introduction');
      d.text(900);
      d.nav('Conclusion');
      d.h('7 Conclusion');
      d.text(600);
      final refs = d.words;
      d.h('References'); // not in the bookmarks
      d.text(700);

      final st = analyzeBookStructure(d.build());
      _expectContiguous(st);
      expect(st.bodyEnd, refs);
      expect(st.sections.last.role, SectionRole.notes);
      expect(st.sections.last.kind, SectionKind.back);
      // An article starts at its first word: nothing is front matter.
      expect(st.bodyStart, 0);
    });
  });

  group('headings only (no navigation)', () {
    test('skips the title and copyright pages, keeps the prologue', () {
      final d = _Doc();
      d.h('The Lighthouse Keeper', 1);
      d.p('A Novel');
      d.h('Copyright');
      d.p('Copyright © 2020 by A. Writer. All rights reserved.');
      d.h('Contents');
      d.p('Prologue');
      d.p('Chapter One');
      final prologue = d.words;
      d.h('Prologue');
      d.text(500);
      d.h('Chapter One');
      d.h('The Arrival', 3);
      d.text(1500);
      d.h('Chapter Two');
      d.text(1500);
      d.h('Epilogue');
      d.text(300);
      final ack = d.words;
      d.h('Acknowledgments');
      d.text(200);
      d.h('About the Author');
      d.text(100);

      final st = analyzeBookStructure(d.build());
      _expectContiguous(st);
      expect(st.bodyStart, prologue);
      expect(st.bodyEnd, ack);
      expect(_names(st.chapters), [
        'Prologue',
        'Chapter One: The Arrival',
        'Chapter Two',
        'Epilogue',
      ]);
      final one = st.chapters[1];
      expect(one.label, 'Chapter One');
      expect(one.title, 'The Arrival');
      expect(one.headingWords, 4);
      expect(
        st.sections.where((s) => s.kind == SectionKind.back).map((s) => s.role),
        [SectionRole.acknowledgments, SectionRole.aboutAuthor],
      );
    });

    test(
      'an attributed introduction is front matter; the author\'s is not',
      () {
        _Doc book(String introTitle) {
          final d = _Doc();
          d.h('Title', 1);
          d.h(introTitle);
          d.text(900);
          d.h('Chapter 1');
          d.text(900);
          d.h('Chapter 2');
          d.text(900);
          return d;
        }

        final own = analyzeBookStructure(book('Introduction').build());
        expect(own.chapters.first.title, 'Introduction');
        expect(own.chapters.first.role, SectionRole.introduction);

        final attributed = analyzeBookStructure(
          book('Introduction by Jane Scholar').build(),
        );
        expect(attributed.chapters.first.label, 'Chapter 1');
        expect(attributed.skippedFrontTitles, [
          'Title',
          'Introduction by Jane Scholar',
        ]);
      },
    );

    test('a foreword and preface are skipped; body starts at chapter 1', () {
      final d = _Doc();
      d.h('Foreword');
      d.text(700);
      d.h('Preface');
      d.text(500);
      final ch1 = d.words;
      d.h('1. The Problem');
      d.text(1200);
      d.h('2. The Method');
      d.text(1200);

      final st = analyzeBookStructure(d.build());
      _expectContiguous(st);
      expect(st.bodyStart, ch1);
      expect(st.chapters.first.label, '1');
      expect(st.chapters.first.title, 'The Problem');
      expect(st.skippedFrontTitles, ['Foreword', 'Preface']);
    });

    test('sub-headings inside chapters are announced, not chapters', () {
      final d = _Doc();
      d.h('Chapter 1', 1);
      d.text(300);
      final sub1 = d.words;
      d.h('A smaller heading', 2);
      d.text(300);
      d.h('Chapter 2', 1);
      d.text(300);
      final sub2 = d.words;
      d.h('Another one', 2);
      d.text(300);

      final st = analyzeBookStructure(d.build());
      _expectContiguous(st);
      expect(_names(st.chapters), ['Chapter 1', 'Chapter 2']);
      expect(st.subHeadings.map((h) => h.start), [sub1, sub2]);
      expect(st.subHeadings.first.wordCount, 3);
    });

    test('an article with a title and sections starts at its first word', () {
      final d = _Doc();
      d.h('How Lighthouses Work', 1);
      d.text(150);
      d.h('History');
      d.text(400);
      d.h('Optics');
      d.text(400);
      d.h('Keepers');
      d.text(400);

      final st = analyzeBookStructure(d.build());
      _expectContiguous(st);
      expect(st.bodyStart, 0);
      expect(st.bodyEnd, st.totalWords);
      expect(_names(st.chapters), [
        'How Lighthouses Work',
        'History',
        'Optics',
        'Keepers',
      ]);
      expect(st.hasChapters, isTrue);
      expect(st.hasFrontMatter, isFalse);
    });

    test(
      'long unheaded prose before chapter 1 is the opening, not skipped',
      () {
        final d = _Doc();
        d.text(2400); // a prologue whose heading was not detected
        d.h('Chapter 1');
        d.text(1500);
        d.h('Chapter 2');
        d.text(1500);
        expect(analyzeBookStructure(d.build()).bodyStart, 0);

        final short = _Doc();
        short.p('The Great Novel');
        short.p(
          'Copyright © 1925. All rights reserved. ISBN 978-0-00-000000-0.',
        );
        short.p('Published by Example House.');
        final ch1 = short.words;
        short.h('Chapter 1');
        short.text(1500);
        short.h('Chapter 2');
        short.text(1500);
        expect(analyzeBookStructure(short.build()).bodyStart, ch1);
      },
    );

    test('a closing THE END ends the story before trailing boilerplate', () {
      final d = _Doc();
      d.h('Chapter 1');
      d.text(1200);
      d.h('Chapter 2');
      d.text(1200);
      d.p('THE END');
      final after = d.words;
      d.text(500); // an unlabelled advert or licence

      final st = analyzeBookStructure(d.build());
      _expectContiguous(st);
      expect(st.bodyEnd, after);
      expect(st.sections.last.kind, SectionKind.back);
    });
  });

  group('plain text (no markup at all)', () {
    test('finds chapters by pattern and ignores the contents list', () {
      final d = _Doc();
      d.p('A Tale of Two Lighthouses');
      d.p('Contents');
      for (var i = 1; i <= 6; i++) {
        d.p('Chapter $i');
      }
      final ch1 = d.words;
      for (var i = 1; i <= 6; i++) {
        d.p('Chapter $i');
        d.text(800);
      }

      final st = analyzeBookStructure(d.build());
      _expectContiguous(st);
      expect(st.bodyStart, ch1);
      expect(st.chapters.length, 6);
      expect(st.chapters.first.label, 'Chapter 1');
      expect(st.chapters.first.headingWords, 2);
      expect(
        st.sections
            .where((s) => s.kind == SectionKind.front)
            .map((s) => s.role),
        contains(SectionRole.contents),
      );
    });

    test('a number in running text is not a chapter', () {
      final d = _Doc();
      d.text(300);
      // "Chapter 7" opens a sentence that continues: not a paragraph alone.
      d.sentences.add(
        const Sentence(words: ['Chapter', '7'], startsParagraph: true),
      );
      d.sentences.add(const Sentence(words: ['was', 'her', 'favourite.']));
      d.words += 5;
      d.text(300);

      final st = analyzeBookStructure(d.build());
      expect(st.hasChapters, isFalse);
      expect(st.sections.length, 1);
    });

    test('text with no structure is one untitled body section', () {
      final d = _Doc()..text(900);
      final st = analyzeBookStructure(d.build());
      _expectContiguous(st);
      expect(st.sections.single.kind, SectionKind.body);
      expect(st.sections.single.isTitled, isFalse);
      expect(st.hasChapters, isFalse);
      expect(st.bodyStart, 0);
      expect(st.bodyEnd, 900);
    });

    test('an empty document is flat and empty', () {
      final st = analyzeBookStructure(const ExtractedDocument(sentences: []));
      expect(st.totalWords, 0);
      expect(st.sections.single.start, 0);
      expect(st.hasChapters, isFalse);
    });
  });

  group('BookStructure lookups', () {
    late BookStructure st;
    late int ch2;

    setUp(() {
      final d = _Doc();
      d.h('Preface');
      d.text(300);
      d.h('Chapter 1');
      d.text(600);
      ch2 = d.words;
      d.h('Chapter 2');
      d.text(600);
      d.h('Index');
      d.text(100);
      st = analyzeBookStructure(d.build());
    });

    test('sectionAt finds the section of any word and clamps', () {
      expect(st.sectionAt(0).title, 'Preface');
      expect(st.sectionAt(ch2 - 1).label, 'Chapter 1');
      expect(st.sectionAt(ch2).label, 'Chapter 2');
      expect(st.sectionAt(1 << 30).title, 'Index');
      expect(st.sectionAt(-5).title, 'Preface');
    });

    test('chapterNumber counts body sections only', () {
      expect(st.chapterNumber(st.sectionAt(ch2)), 2);
      expect(st.chapterNumber(st.sectionAt(0)), 0);
    });

    test('next walks to the following section and stops at the end', () {
      final one = st.sectionAt(ch2 - 1);
      expect(st.next(one)!.label, 'Chapter 2');
      expect(st.next(st.sections.last), isNull);
    });

    test('flat structure covers the whole document', () {
      final flat = BookStructure.flat(50);
      expect(flat.sections.single.end, 50);
      expect(flat.sectionAt(25).kind, SectionKind.body);
      expect(flat.hasChapters, isFalse);
    });
  });
}
