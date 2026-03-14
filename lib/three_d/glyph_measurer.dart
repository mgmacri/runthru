import 'package:flutter/painting.dart';

/// Position of a single glyph within a measured word.
class GlyphPosition {
  const GlyphPosition({
    required this.character,
    required this.xOffset,
    required this.width,
  });

  final String character;
  final double xOffset;
  final double width;
}

/// Pre-computes glyph widths for Space Mono to avoid
/// TextPainter.layout() calls during paint().
class GlyphMeasurer {
  GlyphMeasurer._();

  static GlyphMeasurer? _instance;
  static GlyphMeasurer get instance => _instance ??= GlyphMeasurer._();

  static const double _referenceSize = 48.0;
  final Map<String, double> _regularWidths = {};
  final Map<String, double> _boldWidths = {};
  bool _initialized = false;

  /// Must be called once before use, e.g., in initState.
  void initialize() {
    if (_initialized) return;

    // Space Mono is monospaced — all glyphs have the same width
    // at a given size. Measure one representative character.
    final tp = TextPainter(
      text: const TextSpan(
        text: 'M',
        style: TextStyle(
          fontFamily: 'SpaceMono',
          fontSize: _referenceSize,
          fontWeight: FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final regularWidth = tp.width;

    final tpBold = TextPainter(
      text: const TextSpan(
        text: 'M',
        style: TextStyle(
          fontFamily: 'SpaceMono',
          fontSize: _referenceSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final boldWidth = tpBold.width;

    // All printable ASCII characters share the monospace width
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
        '0123456789'
        '.,;:!?\'"-()[]{}/@#\$%^&*+=<>~`_|\\';

    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      _regularWidths[c] = regularWidth;
      _boldWidths[c] = boldWidth;
    }
    // Space character
    _regularWidths[' '] = regularWidth;
    _boldWidths[' '] = boldWidth;

    _initialized = true;
  }

  /// Get width of a character at the reference size.
  double _widthAt(String char, {bool bold = false}) {
    final map = bold ? _boldWidths : _regularWidths;
    return map[char] ?? map['M']!;
  }

  /// Measure a word and return per-glyph positions at [fontSize].
  List<GlyphPosition> measureWord(
    String word,
    double fontSize, {
    int? anchorIndex,
  }) {
    if (!_initialized) initialize();

    final scale = fontSize / _referenceSize;
    final positions = <GlyphPosition>[];
    var x = 0.0;

    for (var i = 0; i < word.length; i++) {
      final char = word[i];
      final isBold = anchorIndex != null && i == anchorIndex - 1;
      final width = _widthAt(char, bold: isBold) * scale;
      positions.add(
        GlyphPosition(character: char, xOffset: x, width: width),
      );
      x += width;
    }

    return positions;
  }

  /// Total width of a measured word.
  double wordWidth(
    String word,
    double fontSize, {
    int? anchorIndex,
  }) {
    final positions = measureWord(
      word,
      fontSize,
      anchorIndex: anchorIndex,
    );
    if (positions.isEmpty) return 0;
    final last = positions.last;
    return last.xOffset + last.width;
  }
}
