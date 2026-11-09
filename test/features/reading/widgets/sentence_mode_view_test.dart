import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/reading/widgets/sentence_mode_view.dart';

void main() {
  Widget buildView({
    required List<String> words,
    required int currentIndex,
    bool reducedMotion = false,
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
            ),
          ),
        ),
      ),
    );
  }

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

      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(SentenceModeView.currentWordKey),
          matching: find.byType(RichText),
        ),
      );
      expect(richText.text.toPlainText(), 'quick');
      final root = richText.text as TextSpan;
      expect(root.style?.fontWeight, FontWeight.bold);
      expect(root.children, isNotNull);
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

      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(SentenceModeView.currentWordKey),
          matching: find.byType(RichText),
        ),
      );
      final root = richText.text as TextSpan;
      expect(root.children?[1].toPlainText(), 'n');
      expect(find.byKey(SentenceModeView.fixedGuideKey), findsOneWidget);
    });

    testWidgets('new sentence recalculates bounds', (tester) async {
      final words = 'One sentence ends. New sentence starts.'.split(' ');
      await tester.pumpWidget(buildView(words: words, currentIndex: 4));
      await tester.pumpAndSettle();

      expect(find.text('New'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(SentenceModeView.currentWordKey),
          matching: find.byType(RichText),
        ),
        findsOneWidget,
      );
      expect(find.text('starts.'), findsOneWidget);
      expect(find.text('One'), findsNothing);
      expect(find.text('ends.'), findsNothing);
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

      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(SentenceModeView.currentWordKey),
          matching: find.byType(RichText),
        ),
      );
      expect(richText.text.toPlainText(), 'fox.');
      expect(tester.takeException(), isNull);
    });
  });
}
