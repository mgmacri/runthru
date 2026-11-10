import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/screens/home_shell.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/widgets/reading_goal_onboarding_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('App-level onboarding gate', () {
    testWidgets('fresh config shows onboarding before shell', (tester) async {
      final config = _SyncConfig(const AppConfig());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [configProvider.overrideWith(() => config)],
          child: const MaterialApp(
            home: ReadingEntryOnboardingGate(child: _FakeShell()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('WELCOME TO RUNTHRU'), findsOneWidget);
      expect(find.text('Reading, brought to you.'), findsOneWidget);
      // The design mockup's fake phone status bar must not render over the
      // real system status bar (screen readers announced "8:19", "5G").
      expect(find.text('8:19'), findsNothing);
      expect(find.text('5G'), findsNothing);
      expect(find.text('shell'), findsNothing);
    });

    testWidgets('completed flag skips onboarding and shows shell', (
      tester,
    ) async {
      final config = _SyncConfig(
        const AppConfig(hasSeenReadingGoalOnboarding: true),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [configProvider.overrideWith(() => config)],
          child: const MaterialApp(
            home: ReadingEntryOnboardingGate(child: _FakeShell()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('WELCOME TO RUNTHRU'), findsNothing);
      expect(find.text('shell'), findsOneWidget);
    });

    testWidgets('loading config shows splash and no onboarding', (
      tester,
    ) async {
      final config = _DelayedConfig();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [configProvider.overrideWith(() => config)],
          child: const MaterialApp(
            home: ReadingEntryOnboardingGate(child: _FakeShell()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('WELCOME TO RUNTHRU'), findsNothing);
      expect(find.text('shell'), findsNothing);

      config.resolve(const AppConfig());
      await tester.pump();
      await tester.pump();

      expect(find.text('WELCOME TO RUNTHRU'), findsOneWidget);
    });

    testWidgets('completing onboarding reveals shell', (tester) async {
      final config = _SyncConfig(const AppConfig());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [configProvider.overrideWith(() => config)],
          child: const MaterialApp(
            home: ReadingEntryOnboardingGate(child: _FakeShell()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('WELCOME TO RUNTHRU'), findsOneWidget);

      await tester.ensureVisible(find.text('Skip'));
      await tester.pump();
      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.pump();

      expect(find.text('shell'), findsOneWidget);
      expect(find.text('WELCOME TO RUNTHRU'), findsNothing);
      expect(config.state.requireValue.hasSeenReadingGoalOnboarding, isTrue);
    });

    testWidgets('intro carousel leads into designer tour and persists finish', (
      tester,
    ) async {
      final config = _SyncConfig(const AppConfig());

      await tester.pumpWidget(_onboardingHarness(config));
      await tester.pump();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Your eyes get to rest.'), findsOneWidget);
      expect(find.text('USUALLY · EYES HOP'), findsOneWidget);
      expect(find.byKey(const ValueKey('intro-eye-hop-path')), findsOneWidget);
      expect(find.text('RUNTHRU · EYES STILL'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('It was never a race.'), findsOneWidget);

      await tester.tap(find.text('Show me how'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mock-tour-surface')), findsOneWidget);
      expect(find.text('No place to lose.'), findsOneWidget);
      expect(find.text('1 of 6'), findsOneWidget);

      for (final label in [
        'Got it',
        'Nice',
        'Okay',
        'Handy',
        'Got it',
        'Start reading',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pump();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      expect(config.state.requireValue.hasSeenReadingGoalOnboarding, isTrue);
      expect(
        config.state.requireValue.readingGoalPreset,
        ReadingGoalPreset.comfortable,
      );
    });

    testWidgets('mock tour is self-contained and pips change by step', (
      tester,
    ) async {
      final config = _SyncConfig(const AppConfig());

      await tester.pumpWidget(_onboardingHarness(config));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show me how'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsNothing);
      expect(find.byKey(const ValueKey('mock-tour-surface')), findsOneWidget);
      expect(find.byKey(const ValueKey('mock-tour-word-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('mock-tour-play')), findsOneWidget);
      expect(find.byKey(const ValueKey('mock-tour-prev')), findsOneWidget);
      expect(find.byKey(const ValueKey('mock-tour-next')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mock-tour-speed-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mock-tour-highlight-word')),
        findsOneWidget,
      );
      expect(find.text('1 of 6'), findsOneWidget);
      expect(find.text('No place to lose.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('onboarding-step-dots')),
        findsOneWidget,
      );
      expect(find.text('Skip tour'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
      expect(
        tester
            .widget<AnimatedContainer>(
              find.byKey(const ValueKey('onboarding-step-dot-0')),
            )
            .duration,
        const Duration(milliseconds: 180),
      );

      await tester.tap(find.byKey(const ValueKey('mock-tour-cta')));
      await tester.pumpAndSettle();
      expect(find.text('2 of 6'), findsOneWidget);
      expect(find.text('A spot to lock onto.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mock-tour-highlight-tintedLetter')),
        findsOneWidget,
      );
    });

    testWidgets('final tour CTA omits trailing arrow', (tester) async {
      final config = _SyncConfig(const AppConfig());

      await tester.pumpWidget(_onboardingHarness(config));
      await tester.pump();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show me how'));
      await tester.pumpAndSettle();

      for (final label in ['Got it', 'Nice', 'Okay', 'Handy', 'Got it']) {
        await tester.ensureVisible(find.text(label));
        await tester.pump();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      expect(find.text('6 of 6'), findsOneWidget);
      expect(find.text('Start reading'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    });

    testWidgets('reduced motion removes onboarding dot animation duration', (
      tester,
    ) async {
      final config = _SyncConfig(const AppConfig());

      await tester.pumpWidget(
        _onboardingHarness(
          config,
          mediaQueryData: const MediaQueryData(disableAnimations: true),
        ),
      );
      await tester.pump();

      expect(
        tester
            .widget<AnimatedContainer>(
              find.byKey(const ValueKey('onboarding-step-dot-0')),
            )
            .duration,
        Duration.zero,
      );
    });

    testWidgets('onboarding tolerates tiny width with large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final config = _SyncConfig(const AppConfig());

      await tester.pumpWidget(
        _onboardingHarness(
          config,
          mediaQueryData: const MediaQueryData(
            textScaler: TextScaler.linear(1.7),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show me how'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mock-tour-surface')), findsOneWidget);
      expect(find.text('No place to lose.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('HomeShell bottom nav zero-width safety', () {
    testWidgets('does not throw at tiny screen width', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(30, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final config = _SyncConfig(
        const AppConfig(hasSeenReadingGoalOnboarding: true),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [configProvider.overrideWith(() => config)],
          child: const MaterialApp(home: HomeShell()),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('does not throw when width grows from zero', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(0, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final config = _SyncConfig(
        const AppConfig(hasSeenReadingGoalOnboarding: true),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [configProvider.overrideWith(() => config)],
          child: const MaterialApp(home: HomeShell()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(800, 800);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeShell extends StatelessWidget {
  const _FakeShell();

  @override
  Widget build(BuildContext context) => const Text('shell');
}

Widget _onboardingHarness(
  ConfigNotifier config, {
  MediaQueryData? mediaQueryData,
}) {
  final home = mediaQueryData == null
      ? const ReadingEntryOnboardingGate(child: _FakeShell())
      : MediaQuery(
          data: mediaQueryData,
          child: const ReadingEntryOnboardingGate(child: _FakeShell()),
        );
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, __) => home)],
  );
  return ProviderScope(
    overrides: [configProvider.overrideWith(() => config)],
    child: MaterialApp.router(routerConfig: router),
  );
}

class _SyncConfig extends AsyncNotifier<AppConfig> implements ConfigNotifier {
  _SyncConfig(this._initial);

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
  Future<void> setHasSeenReadingGoalOnboarding(bool seen) async {
    state = AsyncData(
      state.requireValue.copyWith(hasSeenReadingGoalOnboarding: seen),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DelayedConfig extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  final _completer = Completer<AppConfig>();

  void resolve(AppConfig config) {
    if (!_completer.isCompleted) _completer.complete(config);
    state = AsyncData(config);
  }

  @override
  Future<AppConfig> build() => _completer.future;

  @override
  Future<void> applyReadingGoalPreset(ReadingGoalConfig goal) async {}

  @override
  Future<void> setHasSeenReadingGoalOnboarding(bool seen) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
