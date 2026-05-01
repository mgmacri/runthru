import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/context_reveal_notifier.dart';
import 'package:runthru/core/context_reveal_state.dart';
import 'package:runthru/core/gesture_classifier.dart';
import 'package:runthru/core/word_timer.dart';
import 'package:runthru/core/wpm_dial_notifier.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';

/// Fake [ConfigNotifier] for WPM dial persistence in tests.
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

/// TASK-130 — Integration test: full gesture flow (v4).
///
/// Tests all v4 gestures end-to-end by combining the gesture classifier
/// (pure function) with state notifier transitions:
/// 1. Tap → pause/resume
/// 2. Double-tap → sentence restart
/// 3. Swipe left (30% + 200px/s) → next sentence
/// 4. Swipe right (30% + 200px/s) → previous sentence
/// 5. Swipe up → sentence view
/// 6. Swipe up in sentence → jiggle
/// 7. Swipe down → dismiss
/// 8. Long-press → WPM dial appears
/// 9. Sub-threshold swipes don't trigger
void main() {
  // Android reference device dimensions.
  const screenWidth = 1080.0;
  const screenHeight = 2400.0;

  late ProviderContainer container;
  late ContextRevealNotifier crNotifier;
  late WordTimerNotifier wordTimer;

  setUp(() {
    container = ProviderContainer();
    crNotifier = container.read(contextRevealProvider.notifier);
    wordTimer = container.read(wordTimerProvider.notifier);
    wordTimer.loadDocument(200, startIndex: 0);
  });

  tearDown(() {
    container.dispose();
  });

  group('v4 gesture flow integration', () {
    test('1. Tap → pause/resume with auto-rewind', () {
      wordTimer.play();
      wordTimer.seekTo(30);

      // Tap = pause.
      wordTimer.pause();
      expect(container.read(wordTimerProvider).isPlaying, isFalse);

      // Tap = resume (auto-rewind 3 words).
      wordTimer.play();
      expect(container.read(wordTimerProvider).isPlaying, isTrue);
      expect(container.read(wordTimerProvider).currentIndex, 27); // 30 - 3
    });

    test('2. Double-tap → sentence restart (no auto-rewind)', () {
      wordTimer.play();
      wordTimer.seekTo(45);

      // Double-tap restarts current sentence (assume sentence starts at 40).
      wordTimer.restartCurrentSentence(40);

      expect(container.read(wordTimerProvider).currentIndex, 40);
      expect(container.read(wordTimerProvider).isPlaying, isTrue);
    });

    test('3. Swipe left → recognised as left, triggers next sentence', () {
      // Classify: 35% of screen width, 200ms elapsed = 1890 px/s velocity.
      final direction = classifySwipe(
        dx: -(screenWidth * 0.35),
        dy: 0,
        elapsedMs: 200,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(direction, SwipeDirection.left);

      // Simulate next-sentence seek in word timer.
      wordTimer.play();
      wordTimer.seekTo(20);
      // App would resolve next sentence boundary → seekTo(sentenceStart).
      wordTimer.seekTo(30); // next sentence starts at 30
      expect(container.read(wordTimerProvider).currentIndex, 30);
    });

    test('4. Swipe right → recognised as right, triggers previous sentence',
        () {
      final direction = classifySwipe(
        dx: screenWidth * 0.35,
        dy: 0,
        elapsedMs: 200,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(direction, SwipeDirection.right);

      wordTimer.play();
      wordTimer.seekTo(50);
      wordTimer.seekTo(40); // previous sentence starts at 40
      expect(container.read(wordTimerProvider).currentIndex, 40);
    });

    test('5. Swipe up → enter sentence view', () {
      // Classify: 25% of screen height, 200ms = 3000 px/s velocity.
      final direction = classifySwipe(
        dx: 0,
        dy: -(screenHeight * 0.25),
        elapsedMs: 200,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(direction, SwipeDirection.up);

      // Execute: pause + enter CR.
      wordTimer.play();
      wordTimer.seekTo(55);
      wordTimer.pause();
      crNotifier.enterSentence(55);

      expect(container.read(wordTimerProvider).isPlaying, isFalse);
      expect(container.read(contextRevealProvider).isActive, isTrue);
      expect(
        container.read(contextRevealProvider).tier,
        ContextRevealTier.sentence,
      );
    });

    test('6. Swipe up in sentence → jiggle (tier unchanged)', () {
      wordTimer.pause();
      crNotifier.enterSentence(60);

      // Already in sentence view → jiggle.
      crNotifier.triggerJiggle();
      expect(container.read(contextRevealProvider).isJiggling, isTrue);
      expect(
        container.read(contextRevealProvider).tier,
        ContextRevealTier.sentence,
      );

      crNotifier.clearJiggle();
      expect(container.read(contextRevealProvider).isJiggling, isFalse);
    });

    test('7. Swipe down → dismiss CR and resume', () {
      final direction = classifySwipe(
        dx: 0,
        dy: screenHeight * 0.25,
        elapsedMs: 200,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(direction, SwipeDirection.down);

      // Set up CR with a window offset.
      wordTimer.play();
      wordTimer.seekTo(70);
      wordTimer.pause();
      crNotifier.enterSentence(70);
      crNotifier.shiftWindowForward();

      final resumeIndex = crNotifier.dismiss();
      expect(resumeIndex, 71);

      wordTimer.resumeFromContextReveal(resumeIndex);
      expect(container.read(wordTimerProvider).currentIndex, 71);
      expect(container.read(wordTimerProvider).isPlaying, isTrue);
      expect(container.read(contextRevealProvider).isActive, isFalse);
    });

    test('8. Long-press → WPM dial appears, reading pauses', () {
      final fakeConfig = FakeConfigNotifier();
      final dialContainer = ProviderContainer(
        overrides: [configProvider.overrideWith(() => fakeConfig)],
      );
      dialContainer.read(configProvider);

      final pauseHistory = <bool>[];
      Timer? capturedTimer;
      final dialNotifier = WpmDialNotifier(
        configNotifier: fakeConfig,
        onPauseChanged: pauseHistory.add,
        timerFactory: (duration, callback) {
          capturedTimer?.cancel();
          capturedTimer = Timer(duration, callback);
          return capturedTimer!;
        },
      );

      dialNotifier.show(const Offset(540, 1200), 250);
      expect(dialNotifier.state.isVisible, isTrue);
      expect(dialNotifier.state.currentWpm, 250);
      expect(pauseHistory, [true]);

      // Cleanup.
      capturedTimer?.cancel();
      dialNotifier.dispose();
      dialContainer.dispose();
    });

    test('9. Sub-threshold swipes do NOT trigger', () {
      // Distance too small (15% < 30%).
      final tooShort = classifySwipe(
        dx: -(screenWidth * 0.15),
        dy: 0,
        elapsedMs: 100,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(tooShort, isNull);

      // Velocity too slow (35% distance but 5 seconds = 75.6 px/s < 200).
      final tooSlow = classifySwipe(
        dx: -(screenWidth * 0.35),
        dy: 0,
        elapsedMs: 5000,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(tooSlow, isNull);

      // Vertical: distance ok but velocity too slow.
      final verticalSlow = classifySwipe(
        dx: 0,
        dy: -(screenHeight * 0.25),
        elapsedMs: 5000,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(verticalSlow, isNull);

      // Zero elapsed time — avoid division by zero.
      final instantaneous = classifySwipe(
        dx: -500,
        dy: 0,
        elapsedMs: 0,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(instantaneous, isNull);
    });

    test('full v4 session: all gestures in sequence', () {
      // Start reading.
      wordTimer.play();
      wordTimer.seekTo(20);

      // Tap pause.
      wordTimer.pause();
      expect(container.read(wordTimerProvider).isPlaying, isFalse);

      // Tap resume (auto-rewind).
      wordTimer.play();
      expect(container.read(wordTimerProvider).currentIndex, 17); // 20 - 3

      // Swipe up → sentence view.
      wordTimer.pause();
      crNotifier.enterSentence(17);
      expect(container.read(contextRevealProvider).isActive, isTrue);

      // Swipe up again → jiggle.
      crNotifier.triggerJiggle();
      expect(container.read(contextRevealProvider).isJiggling, isTrue);
      crNotifier.clearJiggle();

      // Swipe right → shift window.
      crNotifier.shiftWindowForward();
      expect(container.read(contextRevealProvider).windowOffset, 1);

      // Double-tap → restart sweep.
      crNotifier.resetSweep();
      expect(container.read(contextRevealProvider).sweepPosition, 0);

      // Swipe down → dismiss.
      final resumeIndex = crNotifier.dismiss();
      expect(resumeIndex, 18); // 17 + 1
      wordTimer.resumeFromContextReveal(resumeIndex);
      expect(container.read(wordTimerProvider).currentIndex, 18);
      expect(container.read(wordTimerProvider).isPlaying, isTrue);
    });
  });
}
