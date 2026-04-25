import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/core/word_timer.dart';
import 'package:speedy_boy/core/wpm_dial_notifier.dart';
import 'package:speedy_boy/core/wpm_dial_state.dart';
import 'package:speedy_boy/store/config.dart';
import 'package:speedy_boy/store/models.dart';

/// Fake [ConfigNotifier] that stores state in memory (no SharedPreferences).
class FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  int? lastPersistedWpm;

  @override
  Future<AppConfig> build() async => const AppConfig();

  @override
  Future<void> setDefaultWpm(int wpm) async {
    lastPersistedWpm = wpm.clamp(30, 1000);
    state = AsyncData(
      (state.valueOrNull ?? const AppConfig()).copyWith(
        defaultWpm: wpm.clamp(30, 1000),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// TASK-132 — Integration test: WPM dial lifecycle.
///
/// Tests the full dial interaction cycle:
/// 1. Long-press → dial appears, reading pauses
/// 2. Drag → WPM changes (25-step snap, 100–600 clamp)
/// 3. Wait 1.5s → dial auto-dismisses, reading resumes
/// 4. Verify WPM persisted to AppConfig
void main() {
  late ProviderContainer container;
  late FakeConfigNotifier fakeConfig;
  late WpmDialNotifier dialNotifier;
  late WordTimerNotifier wordTimer;
  late List<bool> pauseHistory;
  Timer? capturedTimer;

  // Keep a listener alive so auto-dispose doesn't reclaim the provider
  // during async gaps (Future.delayed).
  ProviderSubscription<WordTimerState>? wordTimerSub;

  setUp(() {
    fakeConfig = FakeConfigNotifier();
    container = ProviderContainer(
      overrides: [configProvider.overrideWith(() => fakeConfig)],
    );
    container.read(configProvider);

    wordTimer = container.read(wordTimerProvider.notifier);
    wordTimerSub = container.listen(wordTimerProvider, (_, __) {});
    wordTimer.loadDocument(100, startIndex: 0);

    pauseHistory = [];
    capturedTimer = null;
    dialNotifier = WpmDialNotifier(
      configNotifier: fakeConfig,
      onPauseChanged: (pause) {
        pauseHistory.add(pause);
        if (pause) {
          wordTimer.pause();
        } else {
          wordTimer.play();
        }
      },
      timerFactory: (duration, callback) {
        capturedTimer?.cancel();
        capturedTimer = Timer(duration, callback);
        return capturedTimer!;
      },
    );
  });

  tearDown(() {
    capturedTimer?.cancel();
    dialNotifier.dispose();
    wordTimerSub?.close();
    container.dispose();
  });

  group('WPM dial lifecycle integration', () {
    test('1. Long-press → dial appears, reading pauses', () {
      wordTimer.play();
      expect(container.read(wordTimerProvider).isPlaying, isTrue);

      dialNotifier.show(const Offset(540, 1200), 250);

      expect(dialNotifier.state.isVisible, isTrue);
      expect(dialNotifier.state.currentWpm, 250);
      expect(dialNotifier.state.position, const Offset(540, 1200));
      expect(pauseHistory, [true]);
      expect(container.read(wordTimerProvider).isPlaying, isFalse);
    });

    test('2. Drag → WPM changes with 25-step snap and clamping', () {
      dialNotifier.show(const Offset(540, 1200), 200);

      // Direct value.
      dialNotifier.updateWpm(350);
      expect(dialNotifier.state.currentWpm, 350);

      // 25-step snapping: 310 → 300.
      dialNotifier.updateWpm(310);
      expect(dialNotifier.state.currentWpm, 300);

      // 25-step snapping: 313 → 325.
      dialNotifier.updateWpm(313);
      expect(dialNotifier.state.currentWpm, 325);

      // Clamping: below 100.
      dialNotifier.updateWpm(50);
      expect(dialNotifier.state.currentWpm, 100);

      // Clamping: above 600.
      dialNotifier.updateWpm(700);
      expect(dialNotifier.state.currentWpm, 600);
    });

    test('3. Wait 1.5s → auto-dismiss, reading resumes', () async {
      wordTimer.play();
      dialNotifier.show(const Offset(540, 1200), 200);
      expect(dialNotifier.state.isVisible, isTrue);
      expect(container.read(wordTimerProvider).isPlaying, isFalse);

      // Wait for inactivity timer to fire (1500ms + margin).
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      expect(dialNotifier.state.isVisible, isFalse);
      expect(pauseHistory, [true, false]);
      expect(container.read(wordTimerProvider).isPlaying, isTrue);
    });

    test('4. WPM persisted on dismiss', () async {
      dialNotifier.show(const Offset(540, 1200), 200);
      dialNotifier.updateWpm(375);
      dialNotifier.dismiss();

      expect(dialNotifier.state.isVisible, isFalse);

      // Wait for async persistence.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(fakeConfig.lastPersistedWpm, 375);
    });

    test('rapid WPM changes keep dial alive', () async {
      dialNotifier.show(const Offset(540, 1200), 200);

      // Simulate rapid adjustments over 2 seconds — each resets 1.5s timer.
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        dialNotifier.updateWpm(200 + (i + 1) * 25);
      }

      // Dial should still be visible.
      expect(dialNotifier.state.isVisible, isTrue);

      // Wait for inactivity timer to fire.
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(dialNotifier.state.isVisible, isFalse);
    });

    test('explicit dismiss before timer fires', () {
      dialNotifier.show(const Offset(540, 1200), 200);
      expect(dialNotifier.state.isVisible, isTrue);

      // User taps elsewhere → immediate dismiss.
      dialNotifier.dismiss();
      expect(dialNotifier.state.isVisible, isFalse);
      expect(pauseHistory, [true, false]);
    });

    test('updateWpm is no-op when dial not visible', () {
      dialNotifier.updateWpm(400);
      expect(dialNotifier.state.currentWpm, 200); // default unchanged
    });

    test('default state is not visible, 200 WPM', () {
      expect(dialNotifier.state, const WpmDialState());
      expect(dialNotifier.state.isVisible, isFalse);
      expect(dialNotifier.state.currentWpm, 200);
    });
  });
}
