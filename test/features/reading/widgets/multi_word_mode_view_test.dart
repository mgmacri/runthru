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
