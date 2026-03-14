import 'package:flutter/painting.dart';

/// Pool of reusable TextPainters (max 3) for 3D word rendering.
/// Never allocate TextPainters inside paint().
class TextPainterPool {
  TextPainterPool() {
    for (var i = 0; i < maxSize; i++) {
      _pool.add(
        TextPainter(textDirection: TextDirection.ltr),
      );
    }
  }

  static const int maxSize = 3;
  final List<TextPainter> _pool = [];

  /// Get a TextPainter by index (0..2).
  TextPainter operator [](int index) => _pool[index];

  /// Configure a pooled painter with text and style, then layout.
  void configure(
    int index,
    String text,
    TextStyle style,
  ) {
    final tp = _pool[index];
    tp.text = TextSpan(text: text, style: style);
    tp.layout();
  }

  /// Dispose all painters.
  void dispose() {
    for (final tp in _pool) {
      tp.dispose();
    }
  }
}
