import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/context_reveal_state.dart';
import 'package:runthru/widgets/context_reveal_overlay.dart';

void main() {
  group('Adaptive sentence sizing', () {
    Widget buildOverlay({
      required List<String> words,
      double fontSize = 48,
      Size screenSize = const Size(400, 800),
    }) {
      return MediaQuery(
        data: MediaQueryData(size: screenSize),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: screenSize.width,
              height: screenSize.height,
              child: ContextRevealOverlay(
                tier: ContextRevealTier.sentence,
                words: words,
                sweepPosition: 0,
                fontSize: fontSize,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('short sentence renders at default font size', (tester) async {
      final words = 'The quick brown fox jumps'.split(' ');
      await tester.pumpWidget(buildOverlay(words: words, fontSize: 48));
      await tester.pumpAndSettle();

      // All words visible
      for (final word in words) {
        expect(find.text(word), findsOneWidget);
      }

      // Verify the focus word (index 0) uses the default font size
      final textWidget = tester.widget<Text>(find.text('The'));
      expect(textWidget.style?.fontSize, 48);
    });

    testWidgets('30-word sentence reduces font size', (tester) async {
      // 30 words on a small screen should trigger font reduction
      final words = List.generate(
        30,
        (i) => 'word${i.toString().padLeft(2, '0')}',
      );
      await tester.pumpWidget(
        buildOverlay(
          words: words,
          fontSize: 48,
          screenSize: const Size(360, 640), // small phone
        ),
      );
      await tester.pumpAndSettle();

      // Check that focus word font size is smaller than default
      final textWidget = tester.widget<Text>(find.text('word00'));
      expect(textWidget.style!.fontSize!, lessThan(48));
    });

    testWidgets('font size never below readability floor', (tester) async {
      // 100 words should push font down to the floor
      final words = List.generate(100, (i) => 'longword$i');
      await tester.pumpWidget(
        buildOverlay(
          words: words,
          fontSize: 48,
          screenSize: const Size(320, 568), // small phone (shortestSide < 400)
        ),
      );
      await tester.pumpAndSettle();

      // Focus word should be at least 14pt (small phone floor)
      final textWidget = tester.widget<Text>(find.text('longword0'));
      expect(textWidget.style!.fontSize!, greaterThanOrEqualTo(14));
    });

    testWidgets('very long sentence wraps with vertical centering', (
      tester,
    ) async {
      final words = List.generate(20, (i) => 'wrap$i');
      await tester.pumpWidget(
        buildOverlay(
          words: words,
          fontSize: 32,
          screenSize: const Size(400, 800),
        ),
      );
      await tester.pumpAndSettle();

      // Wrap widget should exist (sentence layout uses it)
      expect(find.byType(Wrap), findsOneWidget);

      // Center widget should exist (vertical centering)
      expect(find.byType(Center), findsOneWidget);
    });

    testWidgets('readability floor varies by device class', (tester) async {
      final words = List.generate(100, (i) => 'devicetest$i');

      // Small phone (shortestSide < 400) → floor = 14pt
      await tester.pumpWidget(
        buildOverlay(
          words: words,
          fontSize: 48,
          screenSize: const Size(320, 568),
        ),
      );
      await tester.pumpAndSettle();
      var textWidget = tester.widget<Text>(find.text('devicetest0'));
      expect(textWidget.style!.fontSize!, greaterThanOrEqualTo(14));

      // Large phone (shortestSide >= 400) → floor = 16pt
      await tester.pumpWidget(
        buildOverlay(
          words: words,
          fontSize: 48,
          screenSize: const Size(412, 915),
        ),
      );
      await tester.pumpAndSettle();
      textWidget = tester.widget<Text>(find.text('devicetest0'));
      expect(textWidget.style!.fontSize!, greaterThanOrEqualTo(16));

      // Tablet (shortestSide >= 600) → floor = 18pt
      await tester.pumpWidget(
        buildOverlay(
          words: words,
          fontSize: 48,
          screenSize: const Size(768, 1024),
        ),
      );
      await tester.pumpAndSettle();
      textWidget = tester.widget<Text>(find.text('devicetest0'));
      expect(textWidget.style!.fontSize!, greaterThanOrEqualTo(18));
    });
  });
}
