import 'package:flutter/material.dart';
import 'package:runthru/store/config.dart';

/// Hint IDs for onboarding gestures (Rule 27).
///
/// Each hint has a unique ID tracked in `AppConfig.shownHints`.
/// Once a hint is shown and dismissed, it is never shown again.
abstract final class HintId {
  static const String tap = 'hint_tap';
  static const String swipeUp = 'hint_swipe_up';
  static const String swipeLr = 'hint_swipe_lr';
  static const String doubleTap = 'hint_double_tap';
  static const String clipboard = 'hint_clipboard';
  static const String focusPause = 'hint_focus_pause';
  static const String focusBackSentence = 'hint_focus_back_sentence';
  static const String focusForwardSentence = 'hint_focus_forward_sentence';

  /// All recognized hint IDs.
  static const List<String> all = [
    tap,
    swipeUp,
    swipeLr,
    doubleTap,
    clipboard,
    focusPause,
    focusBackSentence,
    focusForwardSentence,
  ];
}

/// Hint display metadata returned by [HintController.check].
class HintInfo {
  const HintInfo({
    required this.id,
    required this.message,
    required this.position,
    required this.slideFrom,
  });

  final String id;
  final String message;
  final Alignment position;
  final AxisDirection slideFrom;
}

/// Controller that decides when to show each onboarding hint (Rule 27).
///
/// The controller is instantiated in the reading viewport and consulted
/// at trigger points. It reads `AppConfig.shownHints` to check whether a
/// hint has been shown previously, and calls `markHintShown()` when a hint
/// is dismissed.
///
/// Trigger conditions:
/// - `hint_tap`        → after first word displayed
/// - `hint_swipe_up`   → after 10 words read
/// - `hint_swipe_lr`   → after first pause
/// - `hint_double_tap` → after first sentence navigation
/// - `hint_clipboard`  → on empty library screen (handled separately)
class HintController {
  HintController({required this.configNotifier});

  final ConfigNotifier configNotifier;

  /// Check if a hint should be shown for the given [hintId].
  ///
  /// Returns null if the hint has already been shown or if [hintId] is
  /// not recognized. Returns a [HintInfo] with the message and positioning
  /// metadata if the hint should be displayed.
  HintInfo? check(String hintId) {
    if (configNotifier.hasHintBeenShown(hintId)) return null;

    return switch (hintId) {
      HintId.tap => const HintInfo(
        id: HintId.tap,
        message: 'Tap to pause or resume',
        position: Alignment(0, -0.58),
        slideFrom: AxisDirection.down,
      ),
      HintId.swipeUp => const HintInfo(
        id: HintId.swipeUp,
        message: 'Swipe up to see context',
        position: Alignment(0, -0.58),
        slideFrom: AxisDirection.down,
      ),
      HintId.swipeLr => const HintInfo(
        id: HintId.swipeLr,
        message: 'Swipe left/right to navigate sentences',
        position: Alignment(0, -0.58),
        slideFrom: AxisDirection.left,
      ),
      HintId.doubleTap => const HintInfo(
        id: HintId.doubleTap,
        message: 'Double-tap to restart sentence',
        position: Alignment(0, -0.58),
        slideFrom: AxisDirection.down,
      ),
      HintId.clipboard => const HintInfo(
        id: HintId.clipboard,
        message: 'Paste text from clipboard to read',
        position: Alignment.bottomCenter,
        slideFrom: AxisDirection.up,
      ),
      HintId.focusPause => const HintInfo(
        id: HintId.focusPause,
        message: 'Tap anywhere to pause or resume',
        position: Alignment(0, -0.58),
        slideFrom: AxisDirection.down,
      ),
      HintId.focusBackSentence => const HintInfo(
        id: HintId.focusBackSentence,
        message: 'Swipe right to step back a sentence',
        position: Alignment(0, -0.58),
        slideFrom: AxisDirection.right,
      ),
      HintId.focusForwardSentence => const HintInfo(
        id: HintId.focusForwardSentence,
        message: 'Swipe left to step forward a sentence',
        position: Alignment(0, -0.58),
        slideFrom: AxisDirection.left,
      ),
      _ => null,
    };
  }

  /// Mark a hint as shown so it never appears again.
  void markShown(String hintId) {
    configNotifier.markHintShown(hintId);
  }
}
