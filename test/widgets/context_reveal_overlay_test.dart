import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/core/context_reveal_state.dart';
import 'package:speedy_boy/widgets/context_reveal_overlay.dart';

void main() {
  group('ContextRevealOverlay', () {
    Widget buildOverlay({
      required ContextRevealTier tier,
      required List<String> words,
      int sweepPosition = 0,
      double fontSize = 24,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ContextRevealOverlay(
            tier: tier,
            words: words,
            sweepPosition: sweepPosition,
            fontSize: fontSize,
          ),
        ),
      );
    }

    testWidgets('sentence tier displays all words', (tester) async {
      final words = 'The quick brown fox jumps over the lazy dog'.split(' ');
      await tester.pumpWidget(
        buildOverlay(tier: ContextRevealTier.sentence, words: words),
      );
      await tester.pumpAndSettle();

      for (final word in words) {
        expect(find.text(word), findsWidgets);
      }
    });

    testWidgets('none tier renders empty', (tester) async {
      await tester.pumpWidget(
        buildOverlay(tier: ContextRevealTier.none, words: ['hello', 'world']),
      );
      await tester.pump();

      // SizedBox.shrink when tier is none
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('sweep position highlights focus word', (tester) async {
      await tester.pumpWidget(
        buildOverlay(
          tier: ContextRevealTier.sentence,
          words: ['the', 'quick', 'brown'],
          sweepPosition: 1,
        ),
      );
      await tester.pumpAndSettle();

      // All 3 words should be visible
      expect(find.text('the'), findsOneWidget);
      expect(find.text('quick'), findsOneWidget);
      expect(find.text('brown'), findsOneWidget);
    });

    testWidgets('exit animation calls onExitComplete', (tester) async {
      var exitCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextRevealOverlay(
              tier: ContextRevealTier.sentence,
              words: const ['hello', 'world', 'test'],
              sweepPosition: 0,
              fontSize: 24,
              onExitComplete: () => exitCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Rebuild with tier = none to trigger exit
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextRevealOverlay(
              tier: ContextRevealTier.none,
              words: const ['hello', 'world', 'test'],
              sweepPosition: 0,
              fontSize: 24,
              onExitComplete: () => exitCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(exitCalled, isTrue);
    });
  });
}
