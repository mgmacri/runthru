/// Per-word pacing configuration.
///
/// Controls how much extra display time is added for long words,
/// complex words, and punctuation. All fields clamp on construction.
///
/// Algorithm constants derived from RSVP Nano
/// (ionutdecebal/rsvpnano, MIT). See NOTICE for attribution.
library;

/// Maximum delay per category in milliseconds.
const int _kMaxPacingDelayMs = 600;

/// Minimum scale percentage (floor).
const int _kMinScalePercent = 25;

/// Maximum scale percentage (ceiling).
const int _kMaxScalePercent = 200;

/// Per-word pacing configuration controlling bonus magnitudes.
///
/// Three independent categories (long words, complex words, punctuation)
/// each have a delay (ms) and a scale (%). Delays clamp to 0–600 ms.
/// Scales clamp to 25–200%.
class PacingConfig {
  /// Creates a [PacingConfig] with all fields clamped to valid ranges.
  const PacingConfig({
    int longWordDelayMs = 200,
    int complexWordDelayMs = 200,
    int punctuationDelayMs = 200,
    int longWordScalePercent = 100,
    int complexWordScalePercent = 100,
    int punctuationScalePercent = 100,
  }) : longWordDelayMs = longWordDelayMs < 0
           ? 0
           : longWordDelayMs > _kMaxPacingDelayMs
           ? _kMaxPacingDelayMs
           : longWordDelayMs,
       complexWordDelayMs = complexWordDelayMs < 0
           ? 0
           : complexWordDelayMs > _kMaxPacingDelayMs
           ? _kMaxPacingDelayMs
           : complexWordDelayMs,
       punctuationDelayMs = punctuationDelayMs < 0
           ? 0
           : punctuationDelayMs > _kMaxPacingDelayMs
           ? _kMaxPacingDelayMs
           : punctuationDelayMs,
       longWordScalePercent = longWordScalePercent < _kMinScalePercent
           ? _kMinScalePercent
           : longWordScalePercent > _kMaxScalePercent
           ? _kMaxScalePercent
           : longWordScalePercent,
       complexWordScalePercent = complexWordScalePercent < _kMinScalePercent
           ? _kMinScalePercent
           : complexWordScalePercent > _kMaxScalePercent
           ? _kMaxScalePercent
           : complexWordScalePercent,
       punctuationScalePercent = punctuationScalePercent < _kMinScalePercent
           ? _kMinScalePercent
           : punctuationScalePercent > _kMaxScalePercent
           ? _kMaxScalePercent
           : punctuationScalePercent;

  /// Deserializes from a JSON-compatible map.
  ///
  /// Missing keys fall back to defaults. Invalid types are treated as defaults.
  factory PacingConfig.fromJson(Map<String, Object?> json) {
    return PacingConfig(
      longWordDelayMs: _intOr(json['longWordDelayMs'], 200),
      complexWordDelayMs: _intOr(json['complexWordDelayMs'], 200),
      punctuationDelayMs: _intOr(json['punctuationDelayMs'], 200),
      longWordScalePercent: _intOr(json['longWordScalePercent'], 100),
      complexWordScalePercent: _intOr(json['complexWordScalePercent'], 100),
      punctuationScalePercent: _intOr(json['punctuationScalePercent'], 100),
    );
  }

  /// Delay applied to long-word bonus (0–600 ms).
  final int longWordDelayMs;

  /// Delay applied to complex-word bonus (0–600 ms).
  final int complexWordDelayMs;

  /// Delay applied to punctuation bonus (0–600 ms).
  final int punctuationDelayMs;

  /// Scale for long-word bonus (25–200%).
  final int longWordScalePercent;

  /// Scale for complex-word bonus (25–200%).
  final int complexWordScalePercent;

  /// Scale for punctuation bonus (25–200%).
  final int punctuationScalePercent;

  static int _intOr(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  /// Returns a copy with the given fields replaced.
  PacingConfig copyWith({
    int? longWordDelayMs,
    int? complexWordDelayMs,
    int? punctuationDelayMs,
    int? longWordScalePercent,
    int? complexWordScalePercent,
    int? punctuationScalePercent,
  }) {
    return PacingConfig(
      longWordDelayMs: longWordDelayMs ?? this.longWordDelayMs,
      complexWordDelayMs: complexWordDelayMs ?? this.complexWordDelayMs,
      punctuationDelayMs: punctuationDelayMs ?? this.punctuationDelayMs,
      longWordScalePercent: longWordScalePercent ?? this.longWordScalePercent,
      complexWordScalePercent:
          complexWordScalePercent ?? this.complexWordScalePercent,
      punctuationScalePercent:
          punctuationScalePercent ?? this.punctuationScalePercent,
    );
  }

  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'longWordDelayMs': longWordDelayMs,
    'complexWordDelayMs': complexWordDelayMs,
    'punctuationDelayMs': punctuationDelayMs,
    'longWordScalePercent': longWordScalePercent,
    'complexWordScalePercent': complexWordScalePercent,
    'punctuationScalePercent': punctuationScalePercent,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PacingConfig &&
          longWordDelayMs == other.longWordDelayMs &&
          complexWordDelayMs == other.complexWordDelayMs &&
          punctuationDelayMs == other.punctuationDelayMs &&
          longWordScalePercent == other.longWordScalePercent &&
          complexWordScalePercent == other.complexWordScalePercent &&
          punctuationScalePercent == other.punctuationScalePercent;

  @override
  int get hashCode => Object.hash(
    longWordDelayMs,
    complexWordDelayMs,
    punctuationDelayMs,
    longWordScalePercent,
    complexWordScalePercent,
    punctuationScalePercent,
  );

  @override
  String toString() =>
      'PacingConfig(longWordDelay: ${longWordDelayMs}ms, '
      'complexWordDelay: ${complexWordDelayMs}ms, '
      'punctuationDelay: ${punctuationDelayMs}ms, '
      'longWordScale: $longWordScalePercent%, '
      'complexWordScale: $complexWordScalePercent%, '
      'punctuationScale: $punctuationScalePercent%)';
}

/// Default pacing configuration — plain words schedule at exactly
/// `60000 / wpm` ms. No regression for existing users.
const defaultPacingConfig = PacingConfig();
