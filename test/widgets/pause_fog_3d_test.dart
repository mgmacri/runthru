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

      // No fog CustomPaints inside PauseFog3D when playing
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

    testWidgets('fog has NO transport controls (transport lives on reader)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const PauseFog3D(isPaused: true, wpm: 300),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      // Primary transport is now in the persistent reader tray, not the fog.
      expect(find.byTooltip('Previous sentence'), findsNothing);
      expect(find.byTooltip('Next sentence'), findsNothing);
      expect(find.text('SPEED'), findsNothing);
      expect(find.text('200'), findsNothing);
      expect(find.text('300'), findsNothing);
      expect(find.text('400'), findsNothing);
      expect(find.text('500'), findsNothing);
    });

    testWidgets('shows Focus Mode toggle when onFocusModeChanged provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PauseFog3D(isPaused: true, wpm: 300, onFocusModeChanged: (_) {}),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      expect(find.text('Focus Mode'), findsOneWidget);
    });

    testWidgets('focus mode keeps the exit toggle but hides transport', (
      tester,
    ) async {
      var focusEnabled = true;

      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return PauseFog3D(
                isPaused: true,
                wpm: 300,
                focusModeEnabled: focusEnabled,
                onFocusModeChanged: (value) =>
                    setState(() => focusEnabled = value),
              );
            },
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      // The toggle stays visible — it is the only way out of focus mode.
      expect(find.text('Focus Mode'), findsOneWidget);
      // No transport — it lives on the reader screen permanently.
      expect(find.bySemanticsLabel('Resume reading'), findsNothing);
      expect(find.byTooltip('Previous sentence'), findsNothing);
      expect(find.byTooltip('Next sentence'), findsNothing);
      expect(find.text('Gesture controls are active'), findsNothing);

      // Toggling it off escapes focus mode.
      tester
          .widget<Switch>(find.byKey(const ValueKey('pause-focus-mode-switch')))
          .onChanged
          ?.call(false);
      await tester.pump();
      expect(focusEnabled, isFalse);
    });

    testWidgets(
      'reduced motion: overlay visible immediately without animation',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const PauseFog3D(isPaused: true, wpm: 300),
            disableAnimations: true,
          ),
        );
        // Single pump — no animation frames needed
        await tester.pump();

        expect(_fogPainters(), findsWidgets);
        // No transport in the fog.
        expect(find.text('SPEED'), findsNothing);
      },
    );

    testWidgets('transitioning from paused to resumed hides overlay', (
      tester,
    ) async {
      final notifier = ValueNotifier(true);

      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder<bool>(
            valueListenable: notifier,
            builder: (_, paused, __) => PauseFog3D(isPaused: paused, wpm: 300),
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      expect(_fogPainters(), findsWidgets);

      notifier.value = false;
      await tester.pump();
      await tester.pump();

      expect(_fogPainters(), findsNothing);
    });

    testWidgets('externalPosition at zero renders static pause overlay', (
      tester,
    ) async {
      final externalPos = ValueNotifier(Offset.zero);
      addTearDown(externalPos.dispose);

      await tester.pumpWidget(
        _wrap(
          PauseFog3D(isPaused: true, wpm: 300, externalPosition: externalPos),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      expect(_fogPainters(), findsWidgets);
    });

    testWidgets('onRecalibrate is called when isPaused transitions to true', (
      tester,
    ) async {
      var calibrateCount = 0;
      final externalPos = ValueNotifier(Offset.zero);
      addTearDown(externalPos.dispose);

      final isPausedNotifier = ValueNotifier(false);

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

    testWidgets('externalPosition change moves parallax without own gyro', (
      tester,
    ) async {
      final externalPos = ValueNotifier(Offset.zero);
      addTearDown(externalPos.dispose);

      await tester.pumpWidget(
        _wrap(
          PauseFog3D(isPaused: true, wpm: 300, externalPosition: externalPos),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      externalPos.value = const Offset(0.3, -0.2);
      await tester.pump();

      expect(_fogPainters(), findsWidgets);
    });

    testWidgets('paused overlay does not show a 3D reading promo', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PauseFog3D(isPaused: true, wpm: 300, onFocusModeChanged: (_) {}),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      expect(find.text('Try 3D reading mode'), findsNothing);
      expect(find.bySemanticsLabel('Enable 3D reading mode'), findsNothing);
    });
  });
}
