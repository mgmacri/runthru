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

/// Pre-computes per-character glyph widths for any font family to avoid
/// TextPainter.layout() calls during paint().
///
/// Caches widths at a reference size and scales linearly.
class GlyphMeasurer {
  GlyphMeasurer._();

  static GlyphMeasurer? _instance;
  static GlyphMeasurer get instance => _instance ??= GlyphMeasurer._();

  static const double _referenceSize = 48.0;

  // font family → (character → width) for regular weight
  final Map<String, Map<String, double>> _regularCache = {};
  // font family → (character → width) for bold weight
  final Map<String, Map<String, double>> _boldCache = {};

  String _currentFamily = 'BricolageGrotesque';
  bool _initialized = false;

  static const _chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
      '0123456789'
      '.,;:!\'"-()[]{}/@#\$%^&*+=<>~`_|\\'
      '\u2018\u2019\u201C\u201D\u2013\u2014\u2026';

  /// Set the active font family. Re-measures if changed.
  void setFontFamily(String family) {
    if (family == _currentFamily && _initialized) return;
    _currentFamily = family;
    _ensureMeasured(family);
  }

  /// Must be called once before use, e.g., in initState.
  void initialize() {
    _ensureMeasured(_currentFamily);
    _initialized = true;
  }

  void _ensureMeasured(String family) {
    if (_regularCache.containsKey(family)) return;

    final regularWidths = <String, double>{};
    final boldWidths = <String, double>{};

    final tp = TextPainter(textDirection: TextDirection.ltr);

    // Measure each printable ASCII character individually
    for (var i = 0; i < _chars.length; i++) {
      final c = _chars[i];

      tp.text = TextSpan(
        text: c,
        style: TextStyle(
          fontFamily: family,
          fontSize: _referenceSize,
          fontWeight: FontWeight.w400,
        ),
      );
      tp.layout();
      regularWidths[c] = tp.width;

      tp.text = TextSpan(
        text: c,
        style: TextStyle(
          fontFamily: family,
          fontSize: _referenceSize,
          fontWeight: FontWeight.w700,
        ),
      );
      tp.layout();
      boldWidths[c] = tp.width;
    }

    // Space character
    tp.text = TextSpan(
      text: ' ',
      style: TextStyle(
        fontFamily: family,
        fontSize: _referenceSize,
        fontWeight: FontWeight.w400,
      ),
    );
    tp.layout();
    regularWidths[' '] = tp.width;

    tp.text = TextSpan(
      text: ' ',
      style: TextStyle(
        fontFamily: family,
        fontSize: _referenceSize,
        fontWeight: FontWeight.w700,
      ),
    );
    tp.layout();
    boldWidths[' '] = tp.width;

    tp.dispose();

    _regularCache[family] = regularWidths;
    _boldCache[family] = boldWidths;
    _initialized = true;
  }

  /// Get width of a character at the reference size.
  double _widthAt(String char, {bool bold = false}) {
    final map = bold
        ? _boldCache[_currentFamily]!
        : _regularCache[_currentFamily]!;
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
      positions.add(GlyphPosition(character: char, xOffset: x, width: width));
      x += width;
    }

    return positions;
  }

  /// Total width of a measured word.
  double wordWidth(String word, double fontSize, {int? anchorIndex}) {
    final positions = measureWord(word, fontSize, anchorIndex: anchorIndex);
    if (positions.isEmpty) return 0;
    final last = positions.last;
    return last.xOffset + last.width;
  }
}
