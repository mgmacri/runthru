import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/widgets/hint_overlay.dart';

void main() {
  testWidgets('renders redesigned tooltip text and live label', (tester) async {
    await tester.pumpWidget(_harness(onDismiss: () {}));

    expect(find.text('READING HINT'), findsOneWidget);
    expect(find.text('Tap to pause or resume'), findsOneWidget);
    expect(find.byKey(const ValueKey('hint-tooltip-pointer')), findsOneWidget);
    expect(
      find.bySemanticsLabel('Reading hint. Tap to pause or resume'),
      findsOneWidget,
    );
  });

  testWidgets('auto-dismisses after configured duration', (tester) async {
    var dismissed = false;

    await tester.pumpWidget(_harness(onDismiss: () => dismissed = true));
    await tester.pump(
      const Duration(milliseconds: RunThruTiming.hintAutoDismissMs + 1),
    );

    expect(dismissed, isTrue);
  });

  testWidgets('manual dismiss uses the close affordance', (tester) async {
    var dismissed = false;

    await tester.pumpWidget(_harness(onDismiss: () => dismissed = true));
    await tester.tap(find.byTooltip('Dismiss hint'));
    await tester.pump();

    expect(dismissed, isTrue);
  });

  testWidgets('tooltip card does not block underlying reading gestures', (
    tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox.expand(),
                ),
              ),
              HintOverlay(
                text: 'Tap to pause or resume',
                position: Alignment.center,
                slideFrom: AxisDirection.down,
                onDismiss: () {},
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.text('Tap to pause or resume')));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('reduced motion skips slide and fade progress', (tester) async {
    await tester.pumpWidget(
      _harness(onDismiss: () {}, disableAnimations: true),
    );

    final slide = tester.widget<SlideTransition>(
      find.byType(SlideTransition).first,
    );
    final fade = tester.widget<FadeTransition>(
      find.byType(FadeTransition).first,
    );

    expect(slide.position.value, Offset.zero);
    expect(fade.opacity.value, 1.0);
  });
}

Widget _harness({
  required VoidCallback onDismiss,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Stack(
          children: [
            HintOverlay(
              text: 'Tap to pause or resume',
              position: Alignment.center,
              slideFrom: AxisDirection.down,
              onDismiss: onDismiss,
            ),
          ],
        ),
      ),
    ),
  );
}
