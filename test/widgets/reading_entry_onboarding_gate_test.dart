import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/reading_goal_presets.dart';
import 'package:runthru/core/word_timer.dart';
import 'package:runthru/screens/home_shell.dart';
import 'package:runthru/screens/parallax_reading_screen.dart';
import 'package:runthru/screens/reading_screen.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/widgets/reading_goal_onboarding_gate.dart';

void main() {
  group('ReadingEntryOnboardingGate', () {
    for (final entry in ['local', 'clipboard', 'imported', 'parallax']) {
      testWidgets('$entry entry shows onboarding before playback', (
        tester,
      ) async {
        final config = _FakeConfigNotifier(const AppConfig());

        await tester.pumpWidget(_harness(config, entry));
        await tester.pump();

        expect(find.text('WELCOME TO RUNTHRU'), findsOneWidget);
        expect(find.text('Reading, brought to you.'), findsOneWidget);
        expect(find.text('reader-$entry'), findsNothing);
        expect(find.byType(HomeShell), findsNothing);
        expect(find.byType(ReadingScreen), findsNothing);
        expect(find.byType(ParallaxReadingScreen), findsNothing);

        final context = tester.element(find.byType(MaterialApp));
        final container = ProviderScope.containerOf(context);
        expect(container.read(wordTimerProvider).isPlaying, isFalse);
      });
    }

    testWidgets('returning user enters reader normally', (tester) async {
      final config = _FakeConfigNotifier(
        const AppConfig(hasSeenReadingGoalOnboarding: true),
      );

      await tester.pumpWidget(_harness(config, 'returning'));
      await tester.pump();
      await tester.pump();

      expect(find.text('WELCOME TO RUNTHRU'), findsNothing);
      expect(find.text('reader-returning'), findsOneWidget);
    });

    testWidgets('skip persists gate and relaunch stays dismissed', (
      tester,
    ) async {
      final config = _FakeConfigNotifier(const AppConfig());

      await tester.pumpWidget(_harness(config, 'first'));
      await tester.pump();
      await tester.ensureVisible(find.text('Skip'));
      await tester.pump();
      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.pump();

      expect(config.seenPersisted, isTrue);
      expect(find.text('WELCOME TO RUNTHRU'), findsNothing);
      expect(find.text('reader-first'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        _harness(
          _FakeConfigNotifier(
            config.state.requireValue.copyWith(
              hasSeenReadingGoalOnboarding: true,
            ),
          ),
          'relaunch',
        ),
      );
      await tester.pump();

      expect(find.text('WELCOME TO RUNTHRU'), findsNothing);
      expect(find.text('reader-relaunch'), findsOneWidget);
    });

    testWidgets('Next advances intro cards with reduced motion on', (
      tester,
    ) async {
      final config = _FakeConfigNotifier(const AppConfig());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [configProvider.overrideWith(() => config)],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const ReadingEntryOnboardingGate(
              child: _PlaybackProbe(label: 'reduced'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('WELCOME TO RUNTHRU'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('WHY IT FEELS EASIER'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('ON YOUR TERMS'), findsOneWidget);
    });

    testWidgets('waits for persisted config before reader entry', (
      tester,
    ) async {
      final config = _FakeConfigNotifier.delayed();

      await tester.pumpWidget(_harness(config, 'delayed'));
      await tester.pump();

      expect(find.text('WELCOME TO RUNTHRU'), findsNothing);
      expect(find.text('reader-delayed'), findsNothing);

      config.complete(const AppConfig());
      await tester.pump();
      await tester.pump();

      expect(find.text('WELCOME TO RUNTHRU'), findsOneWidget);
      expect(find.text('reader-delayed'), findsNothing);
    });
  });

  group('Mocked reader onboarding tour', () {
    testWidgets('intro enters mocked tour without mounting real reader', (
      tester,
    ) async {
      final config = _FakeConfigNotifier(const AppConfig());

      await tester.pumpWidget(_harness(config, 'mock'));
      await tester.pump();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show me how'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mock-tour-surface')), findsOneWidget);
      expect(find.byKey(const ValueKey('mock-tour-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('mock-tour-word-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('mock-tour-play')), findsOneWidget);
      expect(find.byKey(const ValueKey('mock-tour-prev')), findsOneWidget);
      expect(find.byKey(const ValueKey('mock-tour-next')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mock-tour-speed-selector')),
        findsOneWidget,
      );
      expect(find.byType(HomeShell), findsNothing);
      expect(find.byType(ReadingScreen), findsNothing);
      expect(find.byType(ParallaxReadingScreen), findsNothing);
    });

    testWidgets('all six mocked steps advance with expected scenes', (
      tester,
    ) async {
      await tester.pumpWidget(_tourHarness());
      await tester.pump();

      final expected = [
        ('No place to lose.', 'steady', '260 WPM', 'mock-tour-highlight-word'),
        (
          'A spot to lock onto.',
          'reading',
          '280 WPM',
          'mock-tour-highlight-tintedLetter',
        ),
        (
          'Only what matters.',
          'anchor',
          '280 WPM',
          'mock-tour-highlight-focus',
        ),
        (
          'Step back a sentence.',
          'sentence',
          '260 WPM',
          'mock-tour-highlight-prev',
        ),
        (
          'Step forward a sentence.',
          'momentum',
          '300 WPM',
          'mock-tour-highlight-next',
        ),
        ('Dial it in.', 'comfortable', '320 WPM', 'mock-tour-highlight-speed'),
      ];

      for (var i = 0; i < expected.length; i++) {
        final (title, word, speed, highlightKey) = expected[i];
        expect(find.text(title), findsOneWidget);
        expect(_richTextContaining(word), findsAtLeastNWidgets(1));
        expect(find.text(speed), findsOneWidget);
        expect(find.text('${i + 1} of 6'), findsOneWidget);
        expect(find.byKey(ValueKey(highlightKey)), findsOneWidget);

        if (i == 2) {
          expect(
            find.byKey(const ValueKey('mock-tour-focus-hint')),
            findsOneWidget,
          );
        } else {
          expect(
            find.byKey(const ValueKey('mock-tour-focus-hint')),
            findsNothing,
          );
        }

        if (i < expected.length - 1) {
          await tester.tap(find.byKey(const ValueKey('mock-tour-cta')));
          await tester.pumpAndSettle();
        }
      }

      expect(find.text('Start reading'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    });

    testWidgets('fake controls do not trigger WordTimer playback', (
      tester,
    ) async {
      await tester.pumpWidget(_tourHarnessWithProviders());
      await tester.pump();

      final context = tester.element(find.byType(MaterialApp));
      final container = ProviderScope.containerOf(context);
      expect(container.read(wordTimerProvider).isPlaying, isFalse);

      for (final key in [
        const ValueKey('mock-tour-play'),
        const ValueKey('mock-tour-prev'),
        const ValueKey('mock-tour-next'),
        const ValueKey('mock-tour-speed-selector'),
      ]) {
        await tester.tap(find.byKey(key), warnIfMissed: false);
        await tester.pump();
        expect(container.read(wordTimerProvider).isPlaying, isFalse);
      }
    });

    testWidgets('skip and finish complete onboarding', (tester) async {
      final skippedConfig = _FakeConfigNotifier(const AppConfig());
      await tester.pumpWidget(_harness(skippedConfig, 'skip'));
      await tester.pump();
      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.pump();
      expect(skippedConfig.seenPersisted, isTrue);
      expect(find.text('reader-skip'), findsOneWidget);

      final finishedConfig = _FakeConfigNotifier(const AppConfig());
      await tester.pumpWidget(_harness(finishedConfig, 'finish'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show me how'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byKey(const ValueKey('mock-tour-cta')));
        await tester.pumpAndSettle();
      }

      expect(finishedConfig.seenPersisted, isTrue);
      expect(
        finishedConfig.state.requireValue.readingGoalPreset,
        ReadingGoalPreset.comfortable,
      );
      expect(find.text('reader-finish'), findsOneWidget);
    });
  });
}

Widget _harness(_FakeConfigNotifier config, String label) {
  return ProviderScope(
    key: ValueKey('provider-$label'),
    overrides: [configProvider.overrideWith(() => config)],
    child: MaterialApp(
      home: ReadingEntryOnboardingGate(child: _PlaybackProbe(label: label)),
    ),
  );
}

Finder _richTextContaining(String value) {
  return find.byWidgetPredicate((widget) {
    if (widget is! RichText) return false;
    return widget.text.toPlainText().contains(value);
  });
}

Widget _tourHarness() {
  return const MaterialApp(home: _MockTourHarness());
}

Widget _tourHarnessWithProviders() {
  return ProviderScope(child: _tourHarness());
}

class _MockTourHarness extends StatefulWidget {
  const _MockTourHarness();

  @override
  State<_MockTourHarness> createState() => _MockTourHarnessState();
}

class _MockTourHarnessState extends State<_MockTourHarness> {
  var stepIndex = 0;

  @override
  Widget build(BuildContext context) {
    return MockedReaderTour(
      stepIndex: stepIndex,
      completing: false,
      onSkip: () {},
      onNext: () {
        if (stepIndex < 5) {
          setState(() => stepIndex += 1);
        }
      },
    );
  }
}

class _PlaybackProbe extends ConsumerStatefulWidget {
  const _PlaybackProbe({required this.label});

  final String label;

  @override
  ConsumerState<_PlaybackProbe> createState() => _PlaybackProbeState();
}

class _PlaybackProbeState extends ConsumerState<_PlaybackProbe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final timer = ref.read(wordTimerProvider.notifier);
      timer.loadDocument(3);
      timer.play();
    });
  }

  @override
  Widget build(BuildContext context) => Text('reader-${widget.label}');
}

class _FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  _FakeConfigNotifier(this._initial);

  _FakeConfigNotifier.delayed() : _initial = null;

  final AppConfig? _initial;
  final Completer<AppConfig> _completer = Completer<AppConfig>();
  bool seenPersisted = false;

  @override
  Future<AppConfig> build() async {
    final initial = _initial;
    if (initial != null) return initial;
    return _completer.future;
  }

  void complete(AppConfig config) {
    if (!_completer.isCompleted) {
      _completer.complete(config);
    }
  }

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
    seenPersisted = seen;
    state = AsyncData(
      state.requireValue.copyWith(hasSeenReadingGoalOnboarding: seen),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
