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

/// Modes offered in the mode menu and by swipe cycling, in cycle order.
///
/// [ReadingMode.sentence] is hidden for the 2.0 release (R-05): it has not
/// been aligned with the design reference's re-centering karaoke line. Its
/// view code stays in place; add it back here once it matches the design.
const List<ReadingMode> availableReadingModes = [
  ReadingMode.singleWord,
  ReadingMode.paragraph,
  ReadingMode.fullPage,
];

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

  /// Cycle forward through [availableReadingModes], wrapping.
  void cycleMode() => _step(1);

  /// Cycle backward through [availableReadingModes], wrapping.
  void cycleModeReverse() => _step(-1);

  void _step(int delta) {
    const modes = availableReadingModes;
    final i = modes.indexOf(state);
    // A hidden mode (i == -1) steps to the first or last available mode.
    final from = i < 0 ? (delta > 0 ? -1 : 0) : i;
    state = modes[(from + delta) % modes.length];
  }
}
