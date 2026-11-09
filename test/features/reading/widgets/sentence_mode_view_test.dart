import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/reading/widgets/reading_focus_chrome.dart';
import 'package:runthru/features/reading/widgets/sentence_mode_view.dart';

void main() {
  Widget buildView({
    required List<String> words,
    required int currentIndex,
    bool reducedMotion = false,
    int wpm = 300,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(500, 300),
          disableAnimations: reducedMotion,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 500,
            height: 300,
            child: SentenceModeView(
              words: words,
              currentIndex: currentIndex,
              letterSpacing: 0,
              wordSpacing: 0,
              fontFamily: 'AtkinsonHyperlegible',
              fontSize: 40,
              wpm: wpm,
            ),
          ),
        ),
      ),
    );
  }

  // R-05 (design alignment): the active word is a karaoke word, a faint base
  // plus an inked overlay that fills in. The inked overlay is the last
  // RichText under the current-word key.
  RichText inkedCurrent(WidgetTester tester) => tester.widget<RichText>(
    find
        .descendant(
          of: find.byKey(SentenceModeView.currentWordKey),
          matching: find.byType(RichText),
        )
        .last,
  );

  double translationX(WidgetTester tester) {
    final transform = tester.widget<Transform>(
      find.byKey(SentenceModeView.transformKey),
    );
    return transform.transform.getTranslation().x;
  }

  group('SentenceModeView', () {
    testWidgets('highlights current word with anchored rich text', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildView(words: 'The quick brown fox.'.split(' '), currentIndex: 1),
      );

      final richText = inkedCurrent(tester);
      expect(richText.text.toPlainText(), 'quick');
      final root = richText.text as TextSpan;
      expect(root.children, isNotNull);
      expect(root.children!.first.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('sentence strip translates as current index advances', (
      tester,
    ) async {
      final words = 'The quick brown fox.'.split(' ');
      await tester.pumpWidget(buildView(words: words, currentIndex: 0));
      await tester.pumpAndSettle();
      final firstX = translationX(tester);

      await tester.pumpWidget(buildView(words: words, currentIndex: 2));
      await tester.pumpAndSettle();
      final laterX = translationX(tester);

      expect(laterX, lessThan(firstX));
    });

    testWidgets('fixed guide remains centered as current index advances', (
      tester,
    ) async {
      final words = 'The quick brown fox.'.split(' ');
      await tester.pumpWidget(buildView(words: words, currentIndex: 0));
      await tester.pumpAndSettle();
      final firstCenter = tester.getCenter(
        find.byKey(SentenceModeView.fixedGuideKey),
      );

      await tester.pumpWidget(buildView(words: words, currentIndex: 2));
      await tester.pumpAndSettle();
      final laterCenter = tester.getCenter(
        find.byKey(SentenceModeView.fixedGuideKey),
      );

      expect(laterCenter.dx, firstCenter.dx);
      expect(laterCenter.dy, firstCenter.dy);
    });

    testWidgets('current word highlights the ORP anchor character', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildView(
          words: 'Trump administration officials'.split(' '),
          currentIndex: 1,
          reducedMotion: true,
        ),
      );
      await tester.pumpAndSettle();

      final root = inkedCurrent(tester).text as TextSpan;
      expect(root.children?[1].toPlainText(), 'n');
      expect(find.byKey(SentenceModeView.fixedGuideKey), findsOneWidget);
    });

    testWidgets('new sentence recalculates bounds', (tester) async {
      final words = 'One sentence ends. New sentence starts.'.split(' ');
      await tester.pumpWidget(buildView(words: words, currentIndex: 4));
      await tester.pumpAndSettle();

      // Read words are inked RichText, so match rich text too.
      expect(find.text('New', findRichText: true), findsOneWidget);
      expect(find.byKey(SentenceModeView.currentWordKey), findsOneWidget);
      expect(find.text('starts.', findRichText: true), findsOneWidget);
      expect(find.text('One', findRichText: true), findsNothing);
      expect(find.text('ends.', findRichText: true), findsNothing);
    });

    testWidgets('reduced motion disables sliding duration', (tester) async {
      await tester.pumpWidget(
        buildView(
          words: 'The quick brown fox.'.split(' '),
          currentIndex: 2,
          reducedMotion: true,
        ),
      );

      final builder = tester.widget<TweenAnimationBuilder<double>>(
        find.byKey(SentenceModeView.slideBuilderKey),
      );
      expect(builder.duration, Duration.zero);
      expect(find.byKey(SentenceModeView.currentWordKey), findsOneWidget);
    });

    testWidgets('empty document does not crash', (tester) async {
      await tester.pumpWidget(buildView(words: const [], currentIndex: 0));
      expect(tester.takeException(), isNull);
      expect(find.byKey(SentenceModeView.stripKey), findsNothing);
    });

    testWidgets('out-of-range index clamps safely', (tester) async {
      await tester.pumpWidget(
        buildView(words: 'The quick brown fox.'.split(' '), currentIndex: 99),
      );

      expect(inkedCurrent(tester).text.toPlainText(), 'fox.');
      expect(tester.takeException(), isNull);
    });

    testWidgets('read words are inked and upcoming words are faint', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildView(
          words: 'The quick brown fox.'.split(' '),
          currentIndex: 2,
          reducedMotion: true,
        ),
      );

      final done = tester.widget<KaraokeWord>(
        find.byKey(const ValueKey('sentence-mode-word-0')),
      );
      final next = tester.widget<KaraokeWord>(
        find.byKey(const ValueKey('sentence-mode-word-3')),
      );
      expect(done.state, KaraokeWordState.done);
      expect(next.state, KaraokeWordState.next);
      expect(
        tester
            .widget<KaraokeWord>(find.byKey(SentenceModeView.currentWordKey))
            .state,
        KaraokeWordState.active,
      );
      expect(done.inkedStyle.color!.a, greaterThan(done.faintStyle.color!.a));
    });

    testWidgets('edges fade out and the fill follows reading speed', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildView(
          words: 'The quick brown fox.'.split(' '),
          currentIndex: 1,
          wpm: 240,
        ),
      );

      expect(find.byKey(SentenceModeView.edgeFadeKey), findsOneWidget);
      final active = tester.widget<KaraokeWord>(
        find.byKey(SentenceModeView.currentWordKey),
      );
      expect(active.sweepDuration, const Duration(milliseconds: 250));
    });
  });
}
