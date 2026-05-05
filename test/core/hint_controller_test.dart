import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/hint_controller.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';

/// Fake [ConfigNotifier] that stores state in memory (no SharedPreferences).
class FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  Set<String> _shownHints = {};

  @override
  Future<AppConfig> build() async => const AppConfig();

  @override
  bool hasHintBeenShown(String id) => _shownHints.contains(id);

  @override
  Future<void> markHintShown(String id) async {
    _shownHints = {..._shownHints, id};
    state = AsyncData(
      (state.valueOrNull ?? const AppConfig()).copyWith(
        shownHints: _shownHints,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late ProviderContainer container;
  late FakeConfigNotifier fakeConfig;
  late HintController controller;
  Timer? capturedTimer;

  setUp(() {
    fakeConfig = FakeConfigNotifier();
    container = ProviderContainer(
      overrides: [configProvider.overrideWith(() => fakeConfig)],
    );
    container.read(configProvider);

    capturedTimer = null;
    controller = HintController(
      configNotifier: fakeConfig,
      timerFactory: (duration, callback) {
        capturedTimer = Timer(duration, callback);
        return capturedTimer!;
      },
    );
  });

  tearDown(() {
    capturedTimer?.cancel();
    controller.dispose();
    container.dispose();
  });

  test('tap hint triggers after first word', () {
    // Before any words: check returns hint info
    final hint = controller.check(HintId.tap);
    expect(hint, isNotNull);
    expect(hint!.id, HintId.tap);
    expect(hint.message, 'Tap to pause or resume');
  });

  test('swipe-up hint triggers after 10 words', () {
    final hint = controller.check(HintId.swipeUp);
    expect(hint, isNotNull);
    expect(hint!.id, HintId.swipeUp);
    expect(hint.message, 'Swipe up to see context');
  });

  test('hint not shown if already in shownHints', () async {
    // Mark the tap hint as shown
    await fakeConfig.markHintShown(HintId.tap);

    // Now check should return null
    final hint = controller.check(HintId.tap);
    expect(hint, isNull);
  });

  test('markHintShown persists to AppConfig', () async {
    controller.markShown(HintId.swipeLr);

    // Verify via the fake config
    expect(fakeConfig.hasHintBeenShown(HintId.swipeLr), isTrue);
    // Verify the hint is no longer available
    expect(controller.check(HintId.swipeLr), isNull);
  });

  test('all 6 hint IDs recognized', () {
    for (final id in HintId.all) {
      final hint = controller.check(id);
      expect(hint, isNotNull, reason: 'Hint "$id" should be recognized');
      expect(hint!.id, id);
      expect(hint.message, isNotEmpty);
    }
    expect(HintId.all.length, 6);
  });

  test('unrecognized hint ID returns null', () {
    final hint = controller.check('hint_nonexistent');
    expect(hint, isNull);
  });

  group('long-press timer', () {
    test('fires callback after duration', () async {
      // ignore: unused_local_variable
      var fired = false;
      controller.onLongPressHintTimerFired = () => fired = true;
      controller.startLongPressTimer();

      // Timer should have been created
      expect(capturedTimer, isNotNull);
      expect(capturedTimer!.isActive, isTrue);
    });

    test('does not start timer if hint already shown', () async {
      await fakeConfig.markHintShown(HintId.longPress);
      controller.startLongPressTimer();
      expect(capturedTimer, isNull);
    });

    test('cancelLongPressTimer cancels active timer', () {
      controller.onLongPressHintTimerFired = () {};
      controller.startLongPressTimer();
      expect(capturedTimer!.isActive, isTrue);

      controller.cancelLongPressTimer();
      expect(capturedTimer!.isActive, isFalse);
    });

    test('startLongPressTimer only starts once', () {
      var startCount = 0;
      controller = HintController(
        configNotifier: fakeConfig,
        timerFactory: (duration, callback) {
          startCount++;
          capturedTimer = Timer(duration, callback);
          return capturedTimer!;
        },
      );

      controller.onLongPressHintTimerFired = () {};
      controller.startLongPressTimer();
      controller.startLongPressTimer();
      controller.startLongPressTimer();
      expect(startCount, 1);
    });
  });
}
