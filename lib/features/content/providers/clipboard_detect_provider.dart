import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'clipboard_detect_provider.g.dart';

/// State for clipboard content detection.
///
/// Tracks whether readable text is available on the system clipboard
/// and whether the user has dismissed the prompt this session.
class ClipboardDetectState {
  /// Creates a [ClipboardDetectState].
  const ClipboardDetectState({
    this.isAvailable = false,
    this.preview = '',
    this.wordCount = 0,
    this.isDismissed = false,
  });

  /// Whether readable text was detected on the clipboard.
  final bool isAvailable;

  /// First ~30 characters of clipboard content for preview.
  final String preview;

  /// Approximate word count of clipboard content.
  final int wordCount;

  /// Whether the user has dismissed the prompt this session.
  final bool isDismissed;

  /// Whether to show the clipboard prompt.
  bool get shouldShowPrompt => isAvailable && !isDismissed;

  /// Creates a copy with updated fields.
  ClipboardDetectState copyWith({
    bool? isAvailable,
    String? preview,
    int? wordCount,
    bool? isDismissed,
  }) {
    return ClipboardDetectState(
      isAvailable: isAvailable ?? this.isAvailable,
      preview: preview ?? this.preview,
      wordCount: wordCount ?? this.wordCount,
      isDismissed: isDismissed ?? this.isDismissed,
    );
  }
}

/// Minimum word count for clipboard text to be considered importable.
const int _minWordCount = 20;

/// Maximum preview length in characters.
const int _maxPreviewLength = 30;

/// Detects readable text on the system clipboard on app foreground resume.
///
/// Rule 28 compliance: clipboard is only READ (not imported) on foreground.
/// Actual import requires an explicit user tap on the clipboard prompt.
/// Clipboard contents are never logged or transmitted.
@riverpod
class ClipboardDetect extends _$ClipboardDetect {
  @override
  ClipboardDetectState build() {
    return const ClipboardDetectState();
  }

  /// Check the system clipboard for readable text.
  ///
  /// Called on [AppLifecycleState.resumed]. If text with ≥20 words is
  /// found, updates state to show the clipboard prompt. Does NOT import.
  Future<void> checkClipboard() async {
    if (state.isDismissed) return;

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();

      if (text == null || text.isEmpty) {
        state = const ClipboardDetectState();
        return;
      }

      final words = text.split(RegExp(r'\s+'));
      final wordCount = words.where((w) => w.isNotEmpty).length;

      if (wordCount < _minWordCount) {
        state = const ClipboardDetectState();
        return;
      }

      final preview = text.length <= _maxPreviewLength
          ? text.replaceAll('\n', ' ')
          : '${text.substring(0, _maxPreviewLength).replaceAll('\n', ' ')}\u2026';

      state = ClipboardDetectState(
        isAvailable: true,
        preview: preview,
        wordCount: wordCount,
      );
    } on PlatformException {
      // Clipboard access denied or unavailable — silently ignore.
      state = const ClipboardDetectState();
    }
  }

  /// Dismiss the clipboard prompt for this session.
  void dismiss() {
    state = state.copyWith(isDismissed: true, isAvailable: false);
  }

  /// Reset detection state (e.g. after successful import).
  void clear() {
    state = const ClipboardDetectState();
  }
}
