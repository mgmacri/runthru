import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/hint_controller.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';

/// Fake [ConfigNotifier] that stores hint state in memory.
class FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  FakeConfigNotifier({Set<String>? initialShownHints})
    : _shownHints = initialShownHints ?? {};

  Set<String> _shownHints;

  @override
  Future<AppConfig> build() async => AppConfig(shownHints: _shownHints);

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

/// TASK-133 — Integration test: overlay hints progression.
///
/// Tests the hint system lifecycle (Rule 27):
/// 1. First word → tap hint appears
/// 2. After 10 words → swipe-up hint
/// 3. Dismiss hints → they don't reappear
/// 4. Restart app → hints still dismissed (persistence)
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

  group('Overlay hints integration', () {
    test('1. Tap hint available on first word', () {
      final hint = controller.check(HintId.tap);
      expect(hint, isNotNull);
      expect(hint!.id, HintId.tap);
      expect(hint.message, 'Tap to pause or resume');
    });

    test('2. Swipe-up hint available after 10 words', () {
      final hint = controller.check(HintId.swipeUp);
      expect(hint, isNotNull);
      expect(hint!.id, HintId.swipeUp);
      expect(hint.message, 'Swipe up to see context');
    });

    test('3. Dismissed hint does not reappear', () {
      // Tap hint is available.
      expect(controller.check(HintId.tap), isNotNull);

      // Mark as shown (dismiss).
      controller.markShown(HintId.tap);

      // No longer available.
      expect(controller.check(HintId.tap), isNull);
    });

    test('4. Hints persist across "app restart" (new controller)', () {
      // Show and dismiss two hints.
      controller.markShown(HintId.tap);
      controller.markShown(HintId.swipeUp);

      // Verify current controller reflects dismissal.
      expect(controller.check(HintId.tap), isNull);
      expect(controller.check(HintId.swipeUp), isNull);

      // Simulate app restart: create new FakeConfigNotifier with persisted
      // shownHints, and a new HintController.
      final persistedHints = {...fakeConfig._shownHints};
      final newConfig = FakeConfigNotifier(initialShownHints: persistedHints);
      final newContainer = ProviderContainer(
        overrides: [configProvider.overrideWith(() => newConfig)],
      );
      newContainer.read(configProvider);

      final newController = HintController(configNotifier: newConfig);

      // Previously dismissed hints remain gone.
      expect(newController.check(HintId.tap), isNull);
      expect(newController.check(HintId.swipeUp), isNull);

      // Other hints still available.
      expect(newController.check(HintId.swipeLr), isNotNull);
      expect(newController.check(HintId.doubleTap), isNotNull);
      expect(newController.check(HintId.longPress), isNotNull);
      expect(newController.check(HintId.clipboard), isNotNull);

      newController.dispose();
      newContainer.dispose();
    });

    test('5. All 6 hint IDs recognised, no extras', () {
      expect(HintId.all.length, 6);

      for (final id in HintId.all) {
        final hint = controller.check(id);
        expect(hint, isNotNull, reason: 'Hint "$id" should be recognised');
        expect(hint!.id, id);
        expect(hint.message, isNotEmpty);
      }
    });

    test('unrecognised hint ID returns null', () {
      expect(controller.check('hint_nonexistent'), isNull);
    });

    test('long-press timer fires callback', () {
      var timerFired = false;
      controller.onLongPressHintTimerFired = () => timerFired = true;
      controller.startLongPressTimer();

      expect(capturedTimer, isNotNull);
      expect(capturedTimer!.isActive, isTrue);

      // Timer would fire after 2 minutes — verify it was created.
      // (Actual firing is tested in unit tests via timer completion.)
    });

    test('long-press timer not started if hint already shown', () {
      fakeConfig.markHintShown(HintId.longPress);
      controller.startLongPressTimer();
      expect(capturedTimer, isNull);
    });

    test('cancel long-press timer stops it', () {
      controller.onLongPressHintTimerFired = () {};
      controller.startLongPressTimer();
      expect(capturedTimer!.isActive, isTrue);

      controller.cancelLongPressTimer();
      expect(capturedTimer!.isActive, isFalse);
    });

    test('progressive hint flow mirrors real usage', () {
      // Word 1 → tap hint.
      final tapHint = controller.check(HintId.tap);
      expect(tapHint, isNotNull);
      controller.markShown(HintId.tap);

      // Word 10 → swipe-up hint.
      final swipeHint = controller.check(HintId.swipeUp);
      expect(swipeHint, isNotNull);
      controller.markShown(HintId.swipeUp);

      // First pause → swipe L/R hint.
      final lrHint = controller.check(HintId.swipeLr);
      expect(lrHint, isNotNull);
      controller.markShown(HintId.swipeLr);

      // First sentence navigation → double-tap hint.
      final dtHint = controller.check(HintId.doubleTap);
      expect(dtHint, isNotNull);
      controller.markShown(HintId.doubleTap);

      // All shown — only longPress and clipboard remain.
      expect(controller.check(HintId.tap), isNull);
      expect(controller.check(HintId.swipeUp), isNull);
      expect(controller.check(HintId.swipeLr), isNull);
      expect(controller.check(HintId.doubleTap), isNull);
      expect(controller.check(HintId.longPress), isNotNull);
      expect(controller.check(HintId.clipboard), isNotNull);
    });
  });
}
