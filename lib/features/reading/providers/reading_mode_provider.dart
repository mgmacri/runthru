import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reading_mode_provider.g.dart';

/// The available reading modes.
enum ReadingMode {
  /// Word-at-a-time RSVP with ORP — the default.
  rsvp,

  /// Full sentence with current word highlighted.
  sentence,

  /// Full paragraph with current word highlighted and auto-scroll.
  paragraph,
}

/// Provides the current reading mode. Auto-disposed when the reading
/// screen is unmounted (session-only, not persisted in AppConfig).
@riverpod
class ReadingModeNotifier extends _$ReadingModeNotifier {
  @override
  ReadingMode build() => ReadingMode.rsvp;

  /// Switch to a specific reading mode.
  void setMode(ReadingMode mode) {
    state = mode;
  }

  /// Cycle to the next mode: rsvp → sentence → paragraph → rsvp.
  void cycleMode() {
    state = ReadingMode.values[(state.index + 1) % ReadingMode.values.length];
  }
}
