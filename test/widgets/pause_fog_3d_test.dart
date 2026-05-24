import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/widgets/pause_fog_3d.dart';

// ignore_for_file: lines_longer_than_80_chars

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

// Check for CustomPaint specifically inside PauseFog3D (not Scaffold's own painters)
Finder _fogPainters() => find.descendant(
      of: find.byType(PauseFog3D),
      matching: find.byType(CustomPaint),
    );

void main() {
  group('PauseFog3D', () {
    testWidgets('does not render overlay when not paused', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PauseFog3D(isPaused: false, wpm: 300),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      // No resume semantics means the overlay is hidden
      expect(find.bySemanticsLabel('Resume reading'), findsNothing);
      // No fog CustomPaints inside PauseFog3D
      expect(_fogPainters(), findsNothing);
    });

    testWidgets('renders overlay content when paused', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PauseFog3D(isPaused: true, wpm: 300),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      expect(_fogPainters(), findsWidgets);
    });

    testWidgets('shows Resume reading semantics button when paused', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PauseFog3D(isPaused: true, wpm: 300),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Resume reading'), findsOneWidget);
    });

    testWidgets('onResume callback fires when play button tapped', (tester) async {
      var callCount = 0;

      await tester.pumpWidget(
        _wrap(
          PauseFog3D(
            isPaused: true,
            wpm: 300,
            onResume: () => callCount++,
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Resume reading'));
      await tester.pump();

      expect(callCount, 1);
    });

    testWidgets('reduced motion: overlay visible immediately without animation', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PauseFog3D(isPaused: true, wpm: 300),
          disableAnimations: true,
        ),
      );
      // Single pump — no animation frames needed
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
    });

    testWidgets('transitioning from paused to resumed hides overlay', (tester) async {
      final notifier = ValueNotifier(true);

      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder<bool>(
            valueListenable: notifier,
            builder: (_, paused, __) => PauseFog3D(
              isPaused: paused,
              wpm: 300,
            ),
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Resume reading'), findsOneWidget);

      notifier.value = false;
      await tester.pump();
      await tester.pump();

      expect(find.bySemanticsLabel('Resume reading'), findsNothing);
    });

    testWidgets('externalPosition at zero renders static pause overlay', (tester) async {
      final externalPos = ValueNotifier(Offset.zero);
      addTearDown(externalPos.dispose);

      await tester.pumpWidget(
        _wrap(
          PauseFog3D(
            isPaused: true,
            wpm: 300,
            externalPosition: externalPos,
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      // Overlay visible with static external position.
      expect(find.bySemanticsLabel('Resume reading'), findsOneWidget);
      expect(_fogPainters(), findsWidgets);
    });

    testWidgets('onRecalibrate is called when isPaused transitions to true', (tester) async {
      var calibrateCount = 0;
      final externalPos = ValueNotifier(Offset.zero);
      addTearDown(externalPos.dispose);

      final isPausedNotifier = ValueNotifier(false);

      // disableAnimations: false so isReducedMotion(context) is false
      // and _startParallax() is invoked (which fires onRecalibrate).
      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder<bool>(
            valueListenable: isPausedNotifier,
            builder: (_, paused, __) => PauseFog3D(
              isPaused: paused,
              wpm: 300,
              externalPosition: externalPos,
              onRecalibrate: () => calibrateCount++,
            ),
          ),
          disableAnimations: false,
        ),
      );
      await tester.pump();
      expect(calibrateCount, 0);

      isPausedNotifier.value = true;
      await tester.pump();

      expect(calibrateCount, 1);
    });

    testWidgets('externalPosition change moves parallax without own gyro', (tester) async {
      final externalPos = ValueNotifier(Offset.zero);
      addTearDown(externalPos.dispose);

      await tester.pumpWidget(
        _wrap(
          PauseFog3D(
            isPaused: true,
            wpm: 300,
            externalPosition: externalPos,
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      // Update the shared position — widget should not crash.
      externalPos.value = const Offset(0.3, -0.2);
      await tester.pump();

      expect(find.bySemanticsLabel('Resume reading'), findsOneWidget);
    });
  });
}
