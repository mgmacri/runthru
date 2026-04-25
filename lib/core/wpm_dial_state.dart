import 'dart:ui' show Offset;

/// Immutable state for the WPM dial overlay.
class WpmDialState {
  const WpmDialState({
    this.isVisible = false,
    this.currentWpm = 200,
    this.position = Offset.zero,
  });

  /// Whether the dial is currently displayed.
  final bool isVisible;

  /// Current WPM value shown on the dial.
  final int currentWpm;

  /// Center point of the dial (long-press origin).
  final Offset position;

  WpmDialState copyWith({bool? isVisible, int? currentWpm, Offset? position}) {
    return WpmDialState(
      isVisible: isVisible ?? this.isVisible,
      currentWpm: currentWpm ?? this.currentWpm,
      position: position ?? this.position,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WpmDialState &&
          runtimeType == other.runtimeType &&
          isVisible == other.isVisible &&
          currentWpm == other.currentWpm &&
          position == other.position;

  @override
  int get hashCode => Object.hash(isVisible, currentWpm, position);
}
