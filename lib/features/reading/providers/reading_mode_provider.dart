import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reading_mode_provider.g.dart';

/// The available reading modes.
enum ReadingMode {
  /// Word-at-a-time RSVP with ORP — the default.
  singleWord,

  /// Flowing sentence strip with current word anchored.
  sentence,

  /// Full paragraph with current word highlighted and auto-scroll.
  paragraph,

  /// Full document/page-style reading view.
  fullPage,
}

/// Backwards-compatible display and parsing helpers for [ReadingMode].
extension ReadingModeX on ReadingMode {
  /// User-facing mode label.
  String get label => switch (this) {
    ReadingMode.singleWord => 'Single Word',
    ReadingMode.sentence => 'Flowing Sentence',
    ReadingMode.paragraph => 'Paragraph',
    ReadingMode.fullPage => 'Full Page',
  };

  /// Parses persisted mode names without throwing on old values.
  static ReadingMode parse(String? value) => switch (value) {
    'singleWord' || 'rsvp' => ReadingMode.singleWord,
    'sentence' => ReadingMode.sentence,
    'paragraph' => ReadingMode.paragraph,
    'fullPage' => ReadingMode.fullPage,
    _ => ReadingMode.singleWord,
  };
}

/// Provides the current reading mode. Auto-disposed when the reading
/// screen is unmounted (session-only, not persisted in AppConfig).
@riverpod
class ReadingModeNotifier extends _$ReadingModeNotifier {
  @override
  ReadingMode build() => ReadingMode.singleWord;

  /// Switch to a specific reading mode.
  void setMode(ReadingMode mode) {
    state = mode;
  }

  /// Cycle to the next mode:
  /// singleWord → sentence → paragraph → fullPage → singleWord.
  void cycleMode() {
    state = ReadingMode.values[(state.index + 1) % ReadingMode.values.length];
  }

  /// Cycle to the previous mode:
  /// fullPage → paragraph → sentence → singleWord → fullPage.
  void cycleModeReverse() {
    state = ReadingMode.values[(state.index - 1) % ReadingMode.values.length];
  }
}
