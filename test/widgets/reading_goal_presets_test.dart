import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/screens/settings_screen.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/widgets/reading_goal_presets.dart';

/// Fake [ConfigNotifier] that stores state in memory.
class FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  FakeConfigNotifier(this._initial);
  final AppConfig _initial;

  @override
  Future<AppConfig> build() async => _initial;

  @override
  Future<void> applyReadingGoalPreset(ReadingGoalConfig goal) async {
    state = AsyncData(
      state.requireValue.copyWith(
        defaultWpm: goal.wpm,
        parallaxIntensity: goal.parallaxIntensity,
        readingGoalPreset: goal.preset,
      ),
    );
  }

  @override
  Future<void> setDefaultWpm(int wpm) async {
    state = AsyncData(
      state.requireValue.copyWith(defaultWpm: wpm.clamp(30, 1000)),
    );
  }

  @override
  Future<void> setHasSeenReadingGoalOnboarding(bool seen) async {
    state = AsyncData(
      state.requireValue.copyWith(hasSeenReadingGoalOnboarding: seen),
    );
  }

  @override
  Future<void> setFocusModeEnabled(bool enabled) async {
    state = AsyncData(state.requireValue.copyWith(focusModeEnabled: enabled));
  }

  // No-op stubs for other ConfigNotifier methods.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Wraps [SettingsScreen] with overridden config.
Widget _settingsHarness(AppConfig config) {
  return ProviderScope(
    overrides: [configProvider.overrideWith(() => FakeConfigNotifier(config))],
    child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
  );
}

void main() {
  group('ReadingGoalPresets widget', () {
    testWidgets('shows 3 preset cards with correct names', (tester) async {
      ReadingGoalConfig? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReadingGoalPresets(onSelected: (g) => selected = g),
          ),
        ),
      );

      expect(find.text('Deep Read'), findsOneWidget);
      expect(find.text('Comfortable'), findsOneWidget);
      expect(find.text('Quick Scan'), findsOneWidget);
      expect(selected, isNull);
    });

    testWidgets('tapping a card fires onSelected with correct preset', (
      tester,
    ) async {
      ReadingGoalConfig? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReadingGoalPresets(onSelected: (g) => selected = g),
          ),
        ),
      );

      await tester.tap(find.text('Deep Read'));
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.preset, ReadingGoalPreset.deepRead);
      expect(selected!.wpm, 200);
    });
  });

  group('Reading Goal selector in Settings', () {
    testWidgets('shows 3 presets + Custom segments', (tester) async {
      await tester.pumpWidget(_settingsHarness(const AppConfig()));
      await tester.pumpAndSettle();

      // Short labels in the compact selector
      expect(find.text('Deep'), findsOneWidget);
      expect(find.text('Comfort'), findsOneWidget);
      expect(find.text('Quick'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('manual WPM change shows Custom selected', (tester) async {
      // Start with Comfortable preset applied (250 WPM)
      await tester.pumpWidget(
        _settingsHarness(
          const AppConfig(
            readingGoalPreset: ReadingGoalPreset.comfortable,
            defaultWpm: 275, // manually changed away from 250
            parallaxIntensity: ParallaxIntensity.subtle,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Custom should be selected because WPM doesn't match
      expect(
        tester.getSemantics(find.text('Custom')),
        matchesSemantics(
          label: 'Custom',
          hint: 'Manual WPM or room settings',
          isSelected: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );

      // Comfortable should NOT be selected
      expect(
        tester.getSemantics(find.text('Comfort')),
        matchesSemantics(
          label: 'Comfortable',
          hint: 'Your everyday reading pace.',
          isSelected: false,
          hasSelectedState: true,
          hasTapAction: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
    });

    testWidgets('tapping preset applies correct WPM and parallax', (
      tester,
    ) async {
      await tester.pumpWidget(
        _settingsHarness(
          const AppConfig(
            defaultWpm: 300,
            parallaxIntensity: ParallaxIntensity.full,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Deep" (200 WPM, subtle parallax)
      await tester.tap(find.text('Deep'));
      await tester.pumpAndSettle();

      // Deep Read should now be selected (semantics label is full name)
      expect(
        tester.getSemantics(find.text('Deep')),
        matchesSemantics(
          label: 'Deep Read',
          hint: 'Take your time with difficult material.',
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
    });

    testWidgets('Focus Mode setting writes shared config state', (
      tester,
    ) async {
      final config = FakeConfigNotifier(const AppConfig());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [configProvider.overrideWith(() => config)],
          child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Focus Mode'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(config.state.requireValue.focusModeEnabled, isTrue);
    });
  });

  group('Settings pushed over the reader', () {
    testWidgets('shows a back button that returns to the reader', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWith(
              () => FakeConfigNotifier(const AppConfig()),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(showBack: true),
                      ),
                    ),
                    child: const Text('reader'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('reader'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back to reading'), findsOneWidget);

      await tester.tap(find.byTooltip('Back to reading'));
      await tester.pumpAndSettle();
      expect(find.text('reader'), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
    });

    testWidgets('tab Settings has no back button', (tester) async {
      await tester.pumpWidget(_settingsHarness(const AppConfig()));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back to reading'), findsNothing);
    });
  });
}
