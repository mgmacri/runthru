import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/widgets/section_complete_overlay.dart';

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

const _completion = SectionCompletion(
  headline: 'Chapter 3 complete',
  detail: 'The Ledger',
  wordsRead: 2186,
  readingTime: Duration(minutes: 8, seconds: 20),
  chapterNumber: 3,
  chapterCount: 12,
  bookProgress: 0.24,
  nextName: 'Chapter 4: The Storm',
  nextMinutes: 9,
);

/// Until the figures have counted up and the badge has landed.
final Duration _settled =
    RunThruTiming.celebrationBadge +
    RunThruTiming.celebrationCountUp +
    const Duration(milliseconds: 100);

void main() {
  group('SectionCompletion', () {
    test('speed is words over time, and absent when too little was timed', () {
      expect(_completion.wordsPerMinute, 262);
      const blink = SectionCompletion(
        headline: 'x',
        wordsRead: 40,
        readingTime: Duration(seconds: 2),
      );
      expect(blink.wordsPerMinute, 0);
    });

    test('the spoken summary says what was read and what is next', () {
      expect(
        _completion.spokenLabel,
        'Chapter 3 complete. The Ledger. 2186 words in 8 minutes. '
        '3 of 12 chapters. Next: Chapter 4: The Storm',
      );
    });

    test('formatCount groups thousands', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(1000), '1,000');
      expect(formatCount(1234567), '1,234,567');
    });
  });

  group('SectionCompleteOverlay', () {
    testWidgets('shows what was read, the book progress and what is next', (
      tester,
    ) async {
      await _pump(
        tester,
        SectionCompleteOverlay(
          completion: _completion,
          autoContinue: false,
          onContinue: () {},
          onBreak: () {},
        ),
      );
      await tester.pump(_settled);

      expect(find.text('Chapter 3 complete'), findsOneWidget);
      expect(find.text('The Ledger'), findsOneWidget);
      expect(find.text('2,186'), findsOneWidget);
      expect(find.text('8:20'), findsOneWidget);
      expect(find.text('262'), findsOneWidget);
      expect(find.text('3 of 12 chapters  ·  24% of the book'), findsOneWidget);
      expect(find.text('NEXT  ·  9 MIN'), findsOneWidget);
      expect(find.text('Chapter 4: The Storm'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Take a break'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('the figures count up to their values', (tester) async {
      await _pump(
        tester,
        SectionCompleteOverlay(
          completion: _completion,
          autoContinue: false,
          onContinue: () {},
          onBreak: () {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('2,186'), findsNothing);
      await tester.pump(_settled);
      expect(find.text('2,186'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Continue and Take a break each act once', (tester) async {
      var continued = 0;
      var rested = 0;
      await _pump(
        tester,
        SectionCompleteOverlay(
          completion: _completion,
          autoContinue: false,
          onContinue: () => continued++,
          onBreak: () => rested++,
        ),
      );
      await tester.pump(_settled);
      await tester.tap(find.byKey(SectionCompleteOverlay.continueKey));
      await tester.tap(find.byKey(SectionCompleteOverlay.continueKey));
      await tester.tap(find.byKey(SectionCompleteOverlay.breakKey));
      await tester.pump(const Duration(seconds: 10));
      expect(continued, 1);
      expect(rested, 0);
    });

    testWidgets('Take a break stops here', (tester) async {
      var continued = 0;
      var rested = 0;
      await _pump(
        tester,
        SectionCompleteOverlay(
          completion: _completion,
          onContinue: () => continued++,
          onBreak: () => rested++,
        ),
      );
      await tester.pump(_settled);
      await tester.tap(find.byKey(SectionCompleteOverlay.breakKey));
      // The countdown must not go on to continue behind the reader's back.
      await tester.pump(RunThruTiming.celebrationAutoContinue * 2);
      expect(rested, 1);
      expect(continued, 0);
    });

    testWidgets('the next chapter starts by itself after the countdown', (
      tester,
    ) async {
      var continued = 0;
      await _pump(
        tester,
        SectionCompleteOverlay(
          completion: _completion,
          onContinue: () => continued++,
          onBreak: () {},
        ),
      );
      // The countdown starts when the badge has landed.
      await tester.pump(
        RunThruTiming.celebrationBadge + const Duration(milliseconds: 50),
      );
      await tester.pump(
        RunThruTiming.celebrationAutoContinue -
            const Duration(milliseconds: 300),
      );
      expect(continued, 0);
      await tester.pump(const Duration(milliseconds: 600));
      expect(continued, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(continued, 1);
    });

    testWidgets('touching the screen stops the countdown', (tester) async {
      var continued = 0;
      await _pump(
        tester,
        SectionCompleteOverlay(
          completion: _completion,
          onContinue: () => continued++,
          onBreak: () {},
        ),
      );
      await tester.pump(
        RunThruTiming.celebrationBadge + const Duration(milliseconds: 50),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(const Offset(200, 60));
      await tester.pump(RunThruTiming.celebrationAutoContinue * 2);
      expect(continued, 0);
      // The reader can still go on by hand.
      await tester.tap(find.byKey(SectionCompleteOverlay.continueKey));
      await tester.pump();
      expect(continued, 1);
    });

    testWidgets('reduced motion: finished state at once, nothing automatic', (
      tester,
    ) async {
      var continued = 0;
      await _pump(
        tester,
        SectionCompleteOverlay(
          completion: _completion,
          onContinue: () => continued++,
          onBreak: () {},
        ),
        reduced: true,
      );
      await tester.pump();
      // Final figures on the first frame: no count-up.
      expect(find.text('2,186'), findsOneWidget);
      await tester.pump(RunThruTiming.celebrationAutoContinue * 3);
      expect(continued, 0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a screen reader is never moved on automatically', (
      tester,
    ) async {
      var continued = 0;
      await _pump(
        tester,
        SectionCompleteOverlay(
          completion: _completion,
          onContinue: () => continued++,
          onBreak: () {},
        ),
        screenReader: true,
      );
      await tester.pump(RunThruTiming.celebrationAutoContinue * 3);
      expect(continued, 0);
    });

    testWidgets('without a break action only Continue is offered', (
      tester,
    ) async {
      await _pump(
        tester,
        SectionCompleteOverlay(
          completion: _completion,
          autoContinue: false,
          onContinue: () {},
        ),
      );
      await tester.pump(_settled);
      expect(find.byKey(SectionCompleteOverlay.breakKey), findsNothing);
      expect(find.byKey(SectionCompleteOverlay.continueKey), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('buttons are labelled and at least 48dp tall', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        SectionCompleteOverlay(
          completion: _completion,
          autoContinue: false,
          onContinue: () {},
          onBreak: () {},
        ),
      );
      await tester.pump(_settled);
      expect(
        find.bySemanticsLabel('Continue: Chapter 4: The Storm'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Take a break'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Chapter 3 complete\. The Ledger')),
        findsOneWidget,
      );
      for (final key in [
        SectionCompleteOverlay.continueKey,
        SectionCompleteOverlay.breakKey,
      ]) {
        expect(
          tester.getSize(find.byKey(key)).height,
          greaterThanOrEqualTo(RunThruA11y.minTapTarget),
        );
      }
      handle.dispose();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('short and narrow windows scroll instead of overflowing', (
      tester,
    ) async {
      for (final size in const [
        Size(320, 420),
        Size(700, 280),
        Size(1000, 1300),
      ]) {
        await _pump(
          tester,
          SectionCompleteOverlay(
            key: ValueKey(size),
            completion: _completion,
            autoContinue: false,
            onContinue: () {},
            onBreak: () {},
          ),
          size: size,
        );
        await tester.pump(_settled);
        expect(tester.takeException(), isNull, reason: 'at $size');
        await tester.pump(const Duration(seconds: 3));
      }
    });

    testWidgets('many chapters draw one bar instead of segments', (
      tester,
    ) async {
      await _pump(
        tester,
        SectionCompleteOverlay(
          completion: const SectionCompletion(
            headline: 'Chapter 80 complete',
            wordsRead: 900,
            readingTime: Duration(minutes: 3),
            chapterNumber: 80,
            chapterCount: 135,
            bookProgress: 0.6,
            nextName: 'Chapter 81',
          ),
          autoContinue: false,
          onContinue: () {},
          onBreak: () {},
        ),
      );
      await tester.pump(_settled);
      expect(
        find.text('80 of 135 chapters  ·  60% of the book'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('BookCompleteOverlay', () {
    const book = BookCompletion(
      title: 'The Lighthouse Keeper’s Ledger',
      wordsInBook: 61007,
      chapterCount: 24,
      sessionTime: Duration(minutes: 42, seconds: 5),
      backMatterMinutes: 12,
    );

    testWidgets('names the book and what was read', (tester) async {
      await _pump(
        tester,
        BookCompleteOverlay(
          completion: book,
          onLibrary: () {},
          onReadAgain: () {},
          onKeepReading: () {},
        ),
      );
      await tester.pump(_settled);
      expect(find.text('You finished it'), findsOneWidget);
      expect(find.text('The Lighthouse Keeper’s Ledger'), findsOneWidget);
      expect(find.text('61,007'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
      expect(find.text('42:05'), findsOneWidget);
      expect(
        find.text('Keep reading the notes and extras · 12 min'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('each choice calls its action', (tester) async {
      final calls = <String>[];
      await _pump(
        tester,
        BookCompleteOverlay(
          completion: book,
          onLibrary: () => calls.add('library'),
          onReadAgain: () => calls.add('again'),
          onKeepReading: () => calls.add('keep'),
        ),
      );
      await tester.pump(_settled);
      await tester.tap(find.byKey(BookCompleteOverlay.keepReadingKey));
      await tester.tap(find.byKey(BookCompleteOverlay.readAgainKey));
      await tester.tap(find.byKey(BookCompleteOverlay.libraryKey));
      expect(calls, ['keep', 'again', 'library']);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'with nothing after the last chapter there is no keep reading',
      (tester) async {
        await _pump(
          tester,
          BookCompleteOverlay(
            completion: const BookCompletion(
              title: 'A Short Piece',
              wordsInBook: 600,
              chapterCount: 0,
              sessionTime: Duration(seconds: 12),
            ),
            onLibrary: () {},
            onReadAgain: () {},
          ),
        );
        await tester.pump(_settled);
        expect(find.byKey(BookCompleteOverlay.keepReadingKey), findsNothing);
        // No chapters and a session too short to quote: only the word count.
        expect(find.text('CHAPTERS'), findsNothing);
        expect(find.text('600'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets('reduced motion shows the finished state without animation', (
      tester,
    ) async {
      await _pump(
        tester,
        BookCompleteOverlay(
          completion: book,
          onLibrary: () {},
          onReadAgain: () {},
        ),
        reduced: true,
      );
      await tester.pump();
      expect(find.text('61,007'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('small windows scroll instead of overflowing', (tester) async {
      for (final size in const [Size(320, 400), Size(720, 300)]) {
        await _pump(
          tester,
          BookCompleteOverlay(
            key: ValueKey(size),
            completion: book,
            onLibrary: () {},
            onReadAgain: () {},
            onKeepReading: () {},
          ),
          size: size,
        );
        await tester.pump(_settled);
        expect(tester.takeException(), isNull, reason: 'at $size');
        await tester.pump(const Duration(seconds: 5));
      }
    });
  });
}
