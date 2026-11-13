import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/reading/widgets/full_page_mode_view.dart';
import 'package:runthru/features/reading/widgets/masked_reading_view.dart';
import 'package:runthru/features/reading/widgets/paragraph_mode_view.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(420, 720),
          disableAnimations: true,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(width: 420, height: 720, child: child),
        ),
      ),
    );
  }

  group('FullPageModeView', () {
    testWidgets('renders spotlight band, mask, and active-word sweep', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          FullPageModeView(
            words: 'one two three four five six'.split(' '),
            currentIndex: 3,
            letterSpacing: 0,
            wordSpacing: 0,
            fontFamily: 'AtkinsonHyperlegible',
            fontSize: 60,
            wpm: 300,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('four'), findsWidgets);
      expect(find.byKey(MaskedReadingView.maskKey), findsOneWidget);
      expect(find.byKey(MaskedReadingView.spotlightKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey('paragraph-word-highlight-3')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('out-of-range index clamps safely', (tester) async {
      await tester.pumpWidget(
        wrap(
          FullPageModeView(
            words: 'one two'.split(' '),
            currentIndex: 99,
            letterSpacing: 0,
            wordSpacing: 0,
            fontFamily: 'AtkinsonHyperlegible',
            fontSize: 60,
            wpm: 300,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Clamps to the last word and highlights it.
      expect(
        find.byKey(const ValueKey('paragraph-word-highlight-1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ParagraphModeView', () {
    testWidgets('renders active word with band ruler and tri-zone mask', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ParagraphModeView(
            words: 'alpha beta gamma delta epsilon'.split(' '),
            currentIndex: 2,
            letterSpacing: 0,
            wordSpacing: 0,
            fontFamily: 'AtkinsonHyperlegible',
            fontSize: 60,
            wpm: 300,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('gamma'), findsWidgets);
      expect(find.byKey(ParagraphModeView.readingLineKey), findsOneWidget);
      expect(find.byKey(MaskedReadingView.bandBarKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey('paragraph-word-highlight-2')),
        findsOneWidget,
      );
      expect(find.byKey(MaskedReadingView.maskKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('paragraph boundaries split the rendered window', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const ParagraphModeView(
            words: ['alpha', 'beta', '\n', 'gamma', 'delta'],
            currentIndex: 3,
            letterSpacing: 0,
            wordSpacing: 0,
            fontFamily: 'AtkinsonHyperlegible',
            fontSize: 60,
            wpm: 300,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Previous paragraph stays visible above the band for context;
      // read words render as RichText (inked ORP spans).
      expect(find.text('alpha', findRichText: true), findsWidgets);
      expect(
        find.byKey(const ValueKey('paragraph-word-highlight-3')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a token wider than the column shrinks instead of overflowing',
      (tester) async {
        // A URL cannot wrap; it used to run 48px past the right edge.
        await tester.pumpWidget(
          wrap(
            const ParagraphModeView(
              words: [
                'Other',
                'formats:',
                'www.example.org/ebooks/a-very-long-unbreakable-address/11',
                'and',
                'more',
              ],
              currentIndex: 2,
              letterSpacing: 0,
              wordSpacing: 0,
              fontFamily: 'AtkinsonHyperlegible',
              fontSize: 60,
              wpm: 300,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final box = tester.getRect(
          find.byKey(const ValueKey('paragraph-word-highlight-2')),
        );
        final stage = tester.getRect(find.byType(ParagraphModeView));
        expect(
          box.right,
          lessThanOrEqualTo(
            stage.right - MaskedReadingParams.paragraph.pad + 0.5,
          ),
        );
      },
    );

    testWidgets('text with no paragraph breaks is laid out in pieces', (
      tester,
    ) async {
      // Pasted text whose paragraphs are separated by single line breaks is
      // one paragraph to the segmenter: its only paragraph start is word 0.
      // The window used to grow to the whole document, measured word by
      // word on every tick.
      final words = [for (var i = 0; i < 5000; i++) 'w$i'];
      Widget at(int index) => wrap(
        ParagraphModeView(
          words: words,
          currentIndex: index,
          letterSpacing: 0,
          wordSpacing: 0,
          fontFamily: 'AtkinsonHyperlegible',
          fontSize: 60,
          wpm: 300,
          paragraphStarts: const {0},
        ),
      );
      bool shown(int i) =>
          find.text('w$i', findRichText: true).evaluate().isNotEmpty;

      await tester.pumpWidget(at(2500));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('paragraph-word-highlight-2500')),
        findsOneWidget,
      );
      // Pieces of 200 words: the one being read, one above, enough below.
      expect(shown(2200), isTrue);
      expect(shown(2799), isTrue);
      expect(shown(2199), isFalse);
      expect(shown(2800), isFalse);
      expect(shown(0), isFalse);
      expect(shown(4999), isFalse);

      // The pieces do not move with the reader: one word on, the same text.
      await tester.pumpWidget(at(2501));
      await tester.pumpAndSettle();
      expect(shown(2200), isTrue);
      expect(shown(2199), isFalse);
      expect(shown(2799), isTrue);
      expect(shown(2800), isFalse);
    });

    testWidgets('paragraphs of ordinary length are not cut', (tester) async {
      // 150-word paragraphs: a multiple of 200 falls inside every other one
      // and must not split it.
      final words = [for (var i = 0; i < 900; i++) 'w$i'];
      await tester.pumpWidget(
        wrap(
          ParagraphModeView(
            words: words,
            currentIndex: 380,
            letterSpacing: 0,
            wordSpacing: 0,
            fontFamily: 'AtkinsonHyperlegible',
            fontSize: 60,
            wpm: 300,
            paragraphStarts: const {0, 150, 300, 450, 600, 750},
          ),
        ),
      );
      await tester.pumpAndSettle();

      bool shown(int i) =>
          find.text('w$i', findRichText: true).evaluate().isNotEmpty;
      // The paragraph being read (300 to 449), the one above, and whole
      // paragraphs below until 220 words are in view: 150 to 749.
      expect(shown(150), isTrue);
      expect(shown(149), isFalse);
      expect(shown(749), isTrue);
      expect(shown(750), isFalse);
    });

    testWidgets('empty document does not crash', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ParagraphModeView(
            words: [],
            currentIndex: 0,
            letterSpacing: 0,
            wordSpacing: 0,
            fontFamily: 'AtkinsonHyperlegible',
            fontSize: 60,
            wpm: 300,
          ),
        ),
      );

      expect(find.byKey(ParagraphModeView.readingLineKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
