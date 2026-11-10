import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/book_structure.dart';
import 'package:runthru/features/reading/chapter_flow.dart';

/// Front matter 0..10, three chapters, back matter 70..80.
///
/// * Chapter One: heading words 10..11, text 12..29.
/// * Chapter Two: heading words 30..32, text 33..49, a sub-heading at 40..41.
/// * Chapter Three: no heading words (title only in the contents), 50..69.
BookStructure _book() {
  return BookStructure(
    totalWords: 80,
    sections: const [
      BookSection(
        index: 0,
        kind: SectionKind.front,
        role: SectionRole.copyright,
        start: 0,
        end: 10,
        title: 'Copyright',
        headingWords: 1,
      ),
      BookSection(
        index: 1,
        kind: SectionKind.body,
        role: SectionRole.chapter,
        start: 10,
        end: 30,
        label: 'Chapter One',
        headingWords: 2,
      ),
      BookSection(
        index: 2,
        kind: SectionKind.body,
        role: SectionRole.chapter,
        start: 30,
        end: 50,
        label: 'Chapter Two',
        title: 'The Ledger',
        subtitle: 'In which accounts are kept',
        headingWords: 3,
      ),
      BookSection(
        index: 3,
        kind: SectionKind.body,
        role: SectionRole.epilogue,
        start: 50,
        end: 70,
        title: 'Epilogue',
      ),
      BookSection(
        index: 4,
        kind: SectionKind.back,
        role: SectionRole.other,
        start: 70,
        end: 80,
      ),
    ],
    subHeadings: const [SubHeading(start: 40, wordCount: 2, text: 'A Sub')],
  );
}

void main() {
  final book = _book();

  group('chapterEventFor', () {
    test('ordinary reading inside a chapter is no event', () {
      expect(
        chapterEventFor(structure: book, previous: 14, current: 15),
        isNull,
      );
    });

    test('stepping onto the next chapter finishes the one before', () {
      final event = chapterEventFor(structure: book, previous: 29, current: 30);
      expect(event, isA<SectionBoundary>());
      final boundary = event! as SectionBoundary;
      expect(boundary.completed.label, 'Chapter One');
      expect(boundary.next.label, 'Chapter Two');
      expect(boundary.endsBook, isFalse);
    });

    test('a jump onto a chapter start is not a completion', () {
      // A sentence skip or a seek lands on word 30 from far away: the
      // position is among heading words, so reading moves on to the text.
      final event = chapterEventFor(structure: book, previous: 12, current: 30);
      expect(event, isA<SkipHeading>());
      expect((event! as SkipHeading).to, 33);
    });

    test('a rewind into the heading carries on from the text', () {
      final event = chapterEventFor(structure: book, previous: 34, current: 31);
      expect(event, isA<SkipHeading>());
      expect((event! as SkipHeading).to, 33);
    });

    test('running into the back matter ends the book', () {
      final event = chapterEventFor(structure: book, previous: 69, current: 70);
      expect(event, isA<SectionBoundary>());
      expect((event! as SectionBoundary).endsBook, isTrue);
      expect((event as SectionBoundary).completed.title, 'Epilogue');
    });

    test('the front matter running into chapter one is a boundary too', () {
      final event = chapterEventFor(structure: book, previous: 9, current: 10);
      expect(event, isA<SectionBoundary>());
      expect((event! as SectionBoundary).completed.kind, SectionKind.front);
    });

    test('a sub-heading is announced when read onto, skipped otherwise', () {
      final reached = chapterEventFor(
        structure: book,
        previous: 39,
        current: 40,
      );
      expect(reached, isA<SubHeadingReached>());
      expect((reached! as SubHeadingReached).heading.text, 'A Sub');

      final landed = chapterEventFor(
        structure: book,
        previous: 44,
        current: 41,
      );
      expect(landed, isA<SkipHeading>());
      expect((landed! as SkipHeading).to, 42);
    });

    test(
      'a chapter with no heading words in the text still has a boundary',
      () {
        final event = chapterEventFor(
          structure: book,
          previous: 49,
          current: 50,
        );
        expect(event, isA<SectionBoundary>());
        expect((event! as SectionBoundary).next.title, 'Epilogue');
      },
    );

    test('a flat document never produces events', () {
      final flat = BookStructure.flat(100);
      for (var i = 1; i < 100; i++) {
        expect(
          chapterEventFor(structure: flat, previous: i - 1, current: i),
          isNull,
        );
      }
    });
  });

  group('playStartFor', () {
    test('at a chapter\'s first word the title is announced first', () {
      final start = playStartFor(book, 30);
      expect(start.announce!.label, 'Chapter Two');
      expect(start.from, 33);
    });

    test('among heading words reading starts at the text, unannounced', () {
      final start = playStartFor(book, 31);
      expect(start.announce, isNull);
      expect(start.from, 33);
    });

    test('inside the text reading starts where it is', () {
      final start = playStartFor(book, 36);
      expect(start.announce, isNull);
      expect(start.from, 36);
    });

    test('inside a sub-heading reading starts after it', () {
      expect(playStartFor(book, 41).from, 42);
    });

    test('an untitled section start is just a position', () {
      final start = playStartFor(book, 70);
      expect(start.announce, isNull);
      expect(start.from, 70);
    });
  });

  group('announcementFor', () {
    test('carries label, title, subtitle, place and reading time', () {
      final a = announcementFor(book, book.sections[2], wpm: 300);
      expect(a.overline, 'Chapter Two');
      expect(a.headline, 'The Ledger');
      expect(a.subtitle, 'In which accounts are kept');
      expect(a.position, '2 of 3');
      expect(a.minutes, 1); // 17 words: under a minute rounds up to one
      expect(a.spokenLabel, contains('Chapter Two. The Ledger'));
    });

    test('a chapter with only a number shows it as the headline', () {
      final a = announcementFor(book, book.sections[1], wpm: 300);
      expect(a.overline, isEmpty);
      expect(a.headline, 'Chapter One');
      expect(a.minutes, 1);
    });

    test('front matter has no place among the chapters', () {
      final a = announcementFor(book, book.sections[0], wpm: 300);
      expect(a.position, isNull);
    });
  });

  group('completionFor', () {
    test('counts what was read and where the reader now stands', () {
      final c = completionFor(
        book,
        completed: book.sections[2],
        next: book.sections[3],
        readFrom: 33,
        readingTime: const Duration(seconds: 30),
        wpm: 300,
      );
      expect(c.headline, 'Chapter Two complete');
      expect(c.detail, 'The Ledger');
      expect(c.wordsRead, 17);
      expect(c.wordsPerMinute, 34);
      expect(c.chapterNumber, 2);
      expect(c.chapterCount, 3);
      // Body is words 10..70; chapter two ends at 50.
      expect(c.bookProgress, closeTo(40 / 60, 1e-9));
      expect(c.nextName, 'Epilogue');
      expect(c.nextMinutes, 1);
    });

    test('a run that began mid-chapter counts only what was read', () {
      final c = completionFor(
        book,
        completed: book.sections[2],
        next: book.sections[3],
        readFrom: 44,
        readingTime: const Duration(seconds: 2),
        wpm: 300,
      );
      expect(c.wordsRead, 6);
      // Too little was timed to quote a speed.
      expect(c.wordsPerMinute, 0);
    });

    test('the headline does not repeat itself as the detail', () {
      final c = completionFor(
        book,
        completed: book.sections[3],
        next: null,
        readFrom: 50,
        readingTime: const Duration(minutes: 1),
        wpm: 300,
      );
      expect(c.headline, 'Epilogue complete');
      expect(c.detail, isNull);
      expect(c.nextName, isNull);
    });
  });

  test('minutesFor rounds up and never says zero for real text', () {
    expect(minutesFor(0, 300), 0);
    expect(minutesFor(1, 300), 1);
    expect(minutesFor(300, 300), 1);
    expect(minutesFor(301, 300), 2);
    expect(minutesFor(9000, 250), 36);
    // Nonsense speeds are clamped rather than dividing by zero.
    expect(minutesFor(300, 0), 10);
  });
}
