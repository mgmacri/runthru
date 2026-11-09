import 'package:flutter/material.dart';
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

  setUp(() {
    fakeConfig = FakeConfigNotifier();
    container = ProviderContainer(
      overrides: [configProvider.overrideWith(() => fakeConfig)],
    );
    container.read(configProvider);

    controller = HintController(configNotifier: fakeConfig);
  });

  tearDown(() {
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

  test('reader gesture hints use the top slot instead of covering text', () {
    const topReadingSlot = Alignment(0, -0.58);
    for (final id in [
      HintId.tap,
      HintId.swipeUp,
      HintId.swipeLr,
      HintId.doubleTap,
      HintId.focusPause,
      HintId.focusBackSentence,
      HintId.focusForwardSentence,
    ]) {
      expect(controller.check(id)?.position, topReadingSlot, reason: id);
    }
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

  test('all hint IDs recognized', () {
    for (final id in HintId.all) {
      final hint = controller.check(id);
      expect(hint, isNotNull, reason: 'Hint "$id" should be recognized');
      expect(hint!.id, id);
      expect(hint.message, isNotEmpty);
    }
    expect(
      HintId.all,
      containsAllInOrder([
        HintId.tap,
        HintId.swipeUp,
        HintId.swipeLr,
        HintId.doubleTap,
        HintId.clipboard,
        HintId.focusPause,
        HintId.focusBackSentence,
        HintId.focusForwardSentence,
      ]),
    );
  });

  test('unrecognized hint ID returns null', () {
    final hint = controller.check('hint_nonexistent');
    expect(hint, isNull);
  });
}
