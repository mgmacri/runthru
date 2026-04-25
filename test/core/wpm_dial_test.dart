import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  group('WpmDialState', () {
    test('default state: not visible, 200 WPM', () {
      const state = WpmDialState();
      expect(state.isVisible, isFalse);
      expect(state.currentWpm, 200);
      expect(state.position, Offset.zero);
    });

    test('copyWith preserves unmodified fields', () {
      const state = WpmDialState(
        isVisible: true,
        currentWpm: 300,
        position: Offset(10, 20),
      );
      final copy = state.copyWith(currentWpm: 400);
      expect(copy.isVisible, isTrue);
      expect(copy.currentWpm, 400);
      expect(copy.position, const Offset(10, 20));
    });

    test('equality and hashCode', () {
      const a = WpmDialState(isVisible: true, currentWpm: 300);
      const b = WpmDialState(isVisible: true, currentWpm: 300);
      const c = WpmDialState(isVisible: false, currentWpm: 300);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('WpmDialNotifier', () {
    late ProviderContainer container;
    late FakeConfigNotifier fakeConfig;
    late WpmDialNotifier notifier;
    late List<bool> pauseHistory;
    Timer? capturedTimer;

    setUp(() {
      fakeConfig = FakeConfigNotifier();
      container = ProviderContainer(
        overrides: [configProvider.overrideWith(() => fakeConfig)],
      );
      // Force the async notifier to initialize.
      container.read(configProvider);

      pauseHistory = [];
      notifier = WpmDialNotifier(
        configNotifier: fakeConfig,
        onPauseChanged: (pause) => pauseHistory.add(pause),
        timerFactory: (duration, callback) {
          capturedTimer?.cancel();
          capturedTimer = Timer(duration, callback);
          return capturedTimer!;
        },
      );
    });

    tearDown(() {
      capturedTimer?.cancel();
      notifier.dispose();
      container.dispose();
    });

    test('show() makes dial visible and pauses reading', () {
      notifier.show(const Offset(100, 200), 250);
      expect(notifier.state.isVisible, isTrue);
      expect(notifier.state.currentWpm, 250);
      expect(notifier.state.position, const Offset(100, 200));
      expect(pauseHistory, [true]);
    });

    test('updateWpm changes WPM and resets timer', () {
      notifier.show(Offset.zero, 200);
      notifier.updateWpm(325);
      // 325 → closest 25-step = 325
      expect(notifier.state.currentWpm, 325);

      // Snap to nearest 25: 310 → 300
      notifier.updateWpm(310);
      expect(notifier.state.currentWpm, 300);
    });

    test('inactivity timer fires after 1.5 seconds', () async {
      notifier.show(Offset.zero, 200);
      expect(notifier.state.isVisible, isTrue);

      // Wait for the inactivity timer to fire
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      expect(notifier.state.isVisible, isFalse);
      // Should have pause=true (show) then pause=false (dismiss)
      expect(pauseHistory, [true, false]);
    });

    test('dismiss persists WPM to AppConfig', () async {
      notifier.show(Offset.zero, 200);
      notifier.updateWpm(350);
      notifier.dismiss();

      expect(notifier.state.isVisible, isFalse);

      // Wait for async persistence to complete
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(fakeConfig.lastPersistedWpm, 350);
    });

    test('rapid WPM changes reset timer each time', () async {
      notifier.show(Offset.zero, 200);

      // Simulate rapid changes over 2 seconds — each resets the 1.5s timer
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        notifier.updateWpm(200 + (i + 1) * 25);
      }

      // Dial should still be visible since we keep resetting
      expect(notifier.state.isVisible, isTrue);

      // Wait for inactivity timer to fire
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(notifier.state.isVisible, isFalse);
    });

    test('WPM clamped to 100-600 range', () {
      notifier.show(Offset.zero, 200);

      notifier.updateWpm(50);
      expect(notifier.state.currentWpm, 100);

      notifier.updateWpm(700);
      expect(notifier.state.currentWpm, 600);

      notifier.updateWpm(100);
      expect(notifier.state.currentWpm, 100);

      notifier.updateWpm(600);
      expect(notifier.state.currentWpm, 600);
    });

    test('updateWpm is no-op when dial not visible', () {
      notifier.updateWpm(400);
      expect(notifier.state.currentWpm, 200); // unchanged default
    });

    test('dismiss is no-op when dial not visible', () {
      notifier.dismiss();
      expect(pauseHistory, isEmpty); // no callback fired
    });

    test('WPM snaps to 25-step increments', () {
      notifier.show(Offset.zero, 200);

      notifier.updateWpm(
        112,
      ); // nearest 25-step = 100 or 125 → round(112/25)*25 = 100
      expect(notifier.state.currentWpm % 25, 0);

      notifier.updateWpm(113); // round(113/25)*25 = 125
      expect(notifier.state.currentWpm, 125);

      notifier.updateWpm(337); // round(337/25)*25 = 325
      expect(notifier.state.currentWpm, 325);

      notifier.updateWpm(338); // round(338/25)*25 = 350
      expect(notifier.state.currentWpm, 350);
    });
  });
}
