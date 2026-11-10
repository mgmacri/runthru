import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/widgets/chapter_title_card.dart';

/// Pumps [child] filling a window of [size].
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduced = false,
  bool screenReader = false,
  Size size = const Size(400, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: reduced,
          accessibleNavigation: screenReader,
        ),
        child: Scaffold(body: SizedBox.expand(child: child)),
      ),
    ),
  );
}

const _chapter = ChapterAnnouncement(
  overline: 'Chapter 3',
  headline: 'The Ledger',
  subtitle: 'In which accounts are kept',
  position: '3 of 12',
  minutes: 9,
);

/// Words a card for [_chapter] is held for: title, subtitle and label.
const int _chapterWords = 2 + 5 + 2;

/// Enter + hold + exit of a card for [_chapter].
Duration get _chapterLifetime =>
    RunThruTiming.titleCardEnter +
    RunThruTiming.titleWordStagger +
    ChapterTitleCard.holdFor(_chapterWords) +
    RunThruTiming.titleCardExit;

void main() {
  group('ChapterTitleCard', () {
    testWidgets('announces label, title, subtitle, place and time', (
      tester,
    ) async {
      await _pump(
        tester,
        ChapterTitleCard(announcement: _chapter, onDone: () {}),
      );
      await tester.pump(RunThruTiming.titleCardEnter * 2);

      expect(find.text('CHAPTER 3'), findsOneWidget);
      expect(find.text('The'), findsOneWidget);
      expect(find.text('Ledger'), findsOneWidget);
      expect(find.text('In which accounts are kept'), findsOneWidget);
      expect(find.text('3 of 12  ·  9 min'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('leaves on its own after the hold, calling onDone once', (
      tester,
    ) async {
      var done = 0;
      await _pump(
        tester,
        ChapterTitleCard(announcement: _chapter, onDone: () => done++),
      );
      await tester.pump(_chapterLifetime - const Duration(milliseconds: 80));
      expect(done, 0);
      await tester.pump(const Duration(milliseconds: 160));
      expect(done, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(done, 1);
    });

    testWidgets('a tap starts reading now: only the exit plays', (
      tester,
    ) async {
      var done = 0;
      await _pump(
        tester,
        ChapterTitleCard(announcement: _chapter, onDone: () => done++),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(200, 650));
      await tester.pump();
      expect(done, 0);
      await tester.pump(
        RunThruTiming.titleCardExit + const Duration(milliseconds: 60),
      );
      expect(done, 1);
      // A second tap during or after the exit changes nothing.
      await tester.tapAt(const Offset(200, 650));
      await tester.pump(const Duration(seconds: 5));
      expect(done, 1);
    });

    testWidgets('reduced motion: whole card at once, no motion, same hold', (
      tester,
    ) async {
      var done = 0;
      await _pump(
        tester,
        ChapterTitleCard(announcement: _chapter, onDone: () => done++),
        reduced: true,
      );
      await tester.pump();
      // Everything is present on the first frame, fully opaque.
      expect(find.text('Ledger'), findsOneWidget);
      final fades = tester.widgetList<FadeTransition>(
        find.descendant(
          of: find.byType(ChapterTitleCard),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fades, isNotEmpty);
      for (final fade in fades) {
        expect(fade.opacity.value, 1.0);
      }
      // No entrance and no exit: the card lasts exactly its hold.
      final hold = ChapterTitleCard.holdFor(_chapterWords);
      await tester.pump(hold - const Duration(milliseconds: 50));
      expect(done, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(done, 1);
    });

    testWidgets('a screen reader gets twice as long to hear it', (
      tester,
    ) async {
      var done = 0;
      await _pump(
        tester,
        ChapterTitleCard(announcement: _chapter, onDone: () => done++),
        screenReader: true,
      );
      final hold = ChapterTitleCard.holdFor(_chapterWords);
      await tester.pump(hold + const Duration(milliseconds: 200));
      expect(done, 0);
      await tester.pump(hold);
      expect(done, 1);
    });

    testWidgets(
      'offers the skipped front matter; taking it never calls onDone',
      (tester) async {
        var done = 0;
        var fromStart = 0;
        const a = ChapterAnnouncement(
          headline: 'Chapter One',
          skippedNote: 'Skipped the front matter · 12 min',
        );
        await _pump(
          tester,
          ChapterTitleCard(
            announcement: a,
            onDone: () => done++,
            onReadFromStart: () => fromStart++,
          ),
        );
        await tester.pump(RunThruTiming.titleCardEnter * 2);
        expect(find.text('Skipped the front matter · 12 min'), findsOneWidget);
        expect(find.text('Read from the start'), findsOneWidget);
        final target = tester.getSize(
          find.byKey(ChapterTitleCard.readFromStartKey),
        );
        expect(target.height, greaterThanOrEqualTo(RunThruA11y.minTapTarget));

        await tester.tap(find.byKey(ChapterTitleCard.readFromStartKey));
        await tester.pump(const Duration(seconds: 10));
        expect(fromStart, 1);
        expect(done, 0);
      },
    );

    testWidgets('the offer keeps clear of the reader\'s tray', (tester) async {
      const a = ChapterAnnouncement(
        headline: 'Chapter One',
        skippedNote: 'Skipped the front matter · 12 min',
      );
      await _pump(
        tester,
        ChapterTitleCard(
          announcement: a,
          insets: const EdgeInsets.only(top: 120, bottom: 200),
          onDone: () {},
          onReadFromStart: () {},
        ),
      );
      await tester.pump(RunThruTiming.titleCardEnter * 2);
      final pill = tester.getRect(
        find.byKey(ChapterTitleCard.readFromStartKey),
      );
      expect(pill.bottom, lessThanOrEqualTo(800 - 200));
      final title = tester.getRect(find.byKey(ChapterTitleCard.titleKey));
      expect(title.top, greaterThanOrEqualTo(120));
      expect(title.bottom, lessThanOrEqualTo(pill.top));
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('is announced once and offers a labelled way to start', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        ChapterTitleCard(announcement: _chapter, onDone: () {}),
      );
      await tester.pump(RunThruTiming.titleCardEnter * 2);
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Chapter 3\. The Ledger\. In which accounts are kept\. '
            r'About 9 minutes',
          ),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Start reading'), findsOneWidget);
      // The decorative words are not separate nodes.
      expect(find.bySemanticsLabel('Ledger'), findsNothing);
      handle.dispose();
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('long titles and small windows never overflow', (tester) async {
      const long = ChapterAnnouncement(
        groupTitle: 'Part the Second',
        overline: 'Chapter XXVIII',
        headline:
            'Containing a Great Deal of Matter, Partly Comic and Partly '
            'Otherwise, and Some of It of the Utmost Consequence',
        subtitle: 'A subtitle that also runs on for rather longer than most',
        position: '28 of 60',
        minutes: 14,
        skippedNote: 'Skipped the front matter · 1 h 5 min',
      );
      for (final size in const [
        Size(320, 480),
        Size(640, 300),
        Size(900, 1200),
      ]) {
        await _pump(
          tester,
          ChapterTitleCard(
            key: ValueKey(size),
            announcement: long,
            insets: const EdgeInsets.only(top: 60, bottom: 90),
            onDone: () {},
            onReadFromStart: () {},
          ),
          size: size,
        );
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull, reason: 'at $size');
        await tester.pump(const Duration(seconds: 10));
      }
    });

    test('hold grows with the title and is capped', () {
      final short = ChapterTitleCard.holdFor(1);
      final longer = ChapterTitleCard.holdFor(6);
      final huge = ChapterTitleCard.holdFor(200);
      expect(longer, greaterThan(short));
      expect(huge, RunThruTiming.titleCardMaxHold);
      expect(
        ChapterTitleCard.holdFor(1, hasSkippedNote: true),
        short + RunThruTiming.titleCardSkippedNoteHold,
      );
    });
  });

  group('SubHeadingCard', () {
    testWidgets('shows the heading whole, then reads on', (tester) async {
      var done = 0;
      await _pump(
        tester,
        SubHeadingCard(
          text: 'The First Entry',
          fontFamily: 'AtkinsonHyperlegible',
          onDone: () => done++,
        ),
      );
      await tester.pump(RunThruTiming.subHeadingEnter);
      expect(find.text('The First Entry'), findsOneWidget);
      final life =
          RunThruTiming.subHeadingEnter +
          SubHeadingCard.holdFor(3) +
          RunThruTiming.subHeadingExit;
      await tester.pump(life);
      expect(done, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(done, 1);
    });

    testWidgets('a tap reads on at once', (tester) async {
      var done = 0;
      await _pump(
        tester,
        SubHeadingCard(
          text: 'The First Entry',
          fontFamily: 'AtkinsonHyperlegible',
          onDone: () => done++,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(const Offset(200, 400));
      await tester.pump();
      expect(done, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(done, 1);
    });

    testWidgets('reduced motion: no entrance or exit', (tester) async {
      var done = 0;
      await _pump(
        tester,
        SubHeadingCard(
          text: 'One Two',
          fontFamily: 'AtkinsonHyperlegible',
          onDone: () => done++,
        ),
        reduced: true,
      );
      await tester.pump();
      final hold = SubHeadingCard.holdFor(2);
      await tester.pump(hold - const Duration(milliseconds: 40));
      expect(done, 0);
      await tester.pump(const Duration(milliseconds: 80));
      expect(done, 1);
    });
  });
}
