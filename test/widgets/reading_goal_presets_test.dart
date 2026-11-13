import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/features/reading/pacing/pacing_config.dart';
import 'package:runthru/screens/settings_screen.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake [ConfigNotifier] that stores state in memory.
class FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  FakeConfigNotifier(this._initial);
  final AppConfig _initial;

  @override
  Future<AppConfig> build() async => _initial;

  // The same rules as ConfigNotifier: this fake once gave free readers the
  // goal's 3D room, which the real one never does, and so hid B-54.
  @override
  Future<void> applyReadingGoalPreset(ReadingGoalConfig goal) async {
    state = AsyncData(state.requireValue.withReadingGoal(goal));
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
          hint: 'Lights up when you change a setting after choosing a goal',
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
          isButton: true,
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
          isButton: true,
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

  // B-54. These run on the real ConfigNotifier and saved settings, not the
  // fake above, so choosing a goal goes through the same rules as the app.
  group('Reading Goal on saved settings', () {
    Future<ProviderContainer> pumpSettings(
      WidgetTester tester, {
      bool premium = false,
    }) async {
      SharedPreferences.setMockInitialValues({
        if (premium) 'runthru_config': jsonEncode({'premiumUnlocked': true}),
      });
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: SettingsScreen())),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
    }

    /// Short segment labels in the order shown.
    const segments = ['Deep', 'Comfort', 'Quick', 'Custom'];

    /// Expects only [lit] (or nothing) to be selected.
    void expectSelected(WidgetTester tester, String? lit) {
      for (final label in segments) {
        expect(
          tester.getSemantics(find.text(label)),
          isSemantics(isSelected: label == lit),
          reason: '$label should ${label == lit ? '' : 'not '}be selected',
        );
      }
    }

    ReadingGoalConfig goalFor(ReadingGoalPreset preset) =>
        readingGoalConfigs.firstWhere((g) => g.preset == preset);

    testWidgets('nothing is lit before a goal is chosen', (tester) async {
      await pumpSettings(tester);
      expectSelected(tester, null);
    });

    testWidgets('a tapped goal stays pressed in, without RunThru Unlock', (
      tester,
    ) async {
      final container = await pumpSettings(tester);

      for (final (label, preset) in [
        ('Deep', ReadingGoalPreset.deepRead),
        ('Quick', ReadingGoalPreset.quickScan),
        ('Comfort', ReadingGoalPreset.comfortable),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expectSelected(tester, label);

        final goal = goalFor(preset);
        final config = container.read(configProvider).requireValue;
        expect(config.defaultWpm, goal.wpm);
        expect(config.pacingConfig, goal.pacing);
        expect(config.parallaxIntensity, ParallaxIntensity.none);
      }
    });

    testWidgets('a goal moves the Word Pacing sliders too', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Deep'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Reset pacing'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      // Long words, complexity and punctuation all read 150%.
      expect(find.text('150%'), findsNWidgets(3));
      expect(find.textContaining('at 200 WPM'), findsOneWidget);
    });

    testWidgets('Custom lights up only after a setting is changed by hand', (
      tester,
    ) async {
      final container = await pumpSettings(tester);
      final notifier = container.read(configProvider.notifier);

      await tester.tap(find.text('Comfort'));
      await tester.pumpAndSettle();
      expectSelected(tester, 'Comfort');

      await notifier.setDefaultWpm(280);
      await tester.pumpAndSettle();
      expectSelected(tester, 'Custom');

      // Choosing the goal again puts its settings back.
      await tester.tap(find.text('Comfort'));
      await tester.pumpAndSettle();
      expectSelected(tester, 'Comfort');

      await notifier.updatePacingConfig(
        defaultPacingConfig.copyWith(punctuationScalePercent: 175),
      );
      await tester.pumpAndSettle();
      expectSelected(tester, 'Custom');
    });

    testWidgets('Unlock owners: the goal sets the room, another room is '
        'Custom', (tester) async {
      final container = await pumpSettings(tester, premium: true);
      expect(
        find.text(
          'Choose a preset to set reading speed, word pacing and the 3D room.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Quick'));
      await tester.pumpAndSettle();
      expectSelected(tester, 'Quick');
      expect(
        container.read(configProvider).requireValue.parallaxIntensity,
        ParallaxIntensity.off,
      );

      await container
          .read(configProvider.notifier)
          .setParallaxIntensity(ParallaxIntensity.full);
      await tester.pumpAndSettle();
      expectSelected(tester, 'Custom');
    });

    testWidgets('free readers are not told a goal sets the room', (
      tester,
    ) async {
      await pumpSettings(tester);
      expect(
        find.text('Choose a preset to set reading speed and word pacing.'),
        findsOneWidget,
      );
    });

    testWidgets('goals are 48dp buttons; Custom is a status, not a button', (
      tester,
    ) async {
      await pumpSettings(tester);

      for (final label in segments) {
        final segment = find
            .ancestor(
              of: find.text(label),
              matching: find.byType(GestureDetector),
            )
            .first;
        expect(
          tester.getSize(segment).height,
          greaterThanOrEqualTo(48),
          reason: label,
        );
      }
      for (final label in ['Deep', 'Comfort', 'Quick']) {
        expect(
          tester.getSemantics(find.text(label)),
          isSemantics(isButton: true, hasTapAction: true),
          reason: label,
        );
      }
      expect(
        tester.getSemantics(find.text('Custom')),
        isSemantics(isButton: false, hasTapAction: false),
      );
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
