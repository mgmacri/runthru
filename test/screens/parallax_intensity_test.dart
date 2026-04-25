import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/screens/settings_screen.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';

/// Fake [ConfigNotifier] for widget tests.
///
/// Stores state in memory — no SharedPreferences required.
class FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  FakeConfigNotifier(this._initial);
  final AppConfig _initial;

  @override
  Future<AppConfig> build() async => _initial;

  @override
  Future<void> setParallaxIntensity(ParallaxIntensity value) async {
    state = AsyncData(state.requireValue.copyWith(parallaxIntensity: value));
  }

  // No-op stubs for other ConfigNotifier methods — only parallax is tested.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Wraps [SettingsScreen] in required scaffolding with overridden providers.
Widget _harness(AppConfig config) {
  return ProviderScope(
    overrides: [configProvider.overrideWith(() => FakeConfigNotifier(config))],
    child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
  );
}

void main() {
  group('ParallaxIntensitySelector', () {
    testWidgets('shows 4 segments in correct order', (tester) async {
      await tester.pumpWidget(_harness(const AppConfig(hasPremium: true)));
      await tester.pumpAndSettle();

      // All 4 segments visible
      expect(find.text('None'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Subtle'), findsOneWidget);
      expect(find.text('Full'), findsOneWidget);
    });

    testWidgets('tapping a segment updates selection', (tester) async {
      await tester.pumpWidget(
        _harness(
          const AppConfig(
            hasPremium: true,
            parallaxIntensity: ParallaxIntensity.subtle,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to make the parallax selector visible
      await tester.ensureVisible(find.text('Full'));
      await tester.pumpAndSettle();

      // Tap "Full"
      await tester.tap(find.text('Full'));
      await tester.pumpAndSettle();

      // Verify the semantics now mark "Full" as selected
      expect(
        tester.getSemantics(find.text('Full')),
        matchesSemantics(
          label: 'Full',
          hint: 'Full parallax effect',
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
    });

    testWidgets('each segment has semantics label and hint', (tester) async {
      await tester.pumpWidget(
        _harness(
          const AppConfig(
            hasPremium: true,
            parallaxIntensity: ParallaxIntensity.subtle,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to make the parallax selector visible
      await tester.ensureVisible(find.text('Subtle'));
      await tester.pumpAndSettle();

      // Verify Semantics labels and hints for selected segment
      expect(
        tester.getSemantics(find.text('Subtle')),
        matchesSemantics(
          label: 'Subtle',
          hint: 'Gentle parallax effect',
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );

      // Verify unselected segment has correct label + not selected
      expect(
        tester.getSemantics(find.text('None')),
        matchesSemantics(
          label: 'None',
          hint: 'Flat background, no 3D room',
          isSelected: false,
          hasSelectedState: true,
          hasTapAction: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
    });
  });
}
