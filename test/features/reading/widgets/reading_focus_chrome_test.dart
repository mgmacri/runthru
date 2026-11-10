import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/widgets/reading_focus_chrome.dart';

/// Returns the single tinted character and its colour, or null if no span
/// carries a colour different from [base].
(String, Color)? _tinted(List<InlineSpan> spans, TextStyle base) {
  for (final span in spans.cast<TextSpan>()) {
    final color = span.style?.color;
    if (color != null && color != base.color && (span.text ?? '').isNotEmpty) {
      return (span.text!, color);
    }
  }
  return null;
}

void main() {
  const base = TextStyle(color: Color(0xFF000000));
  const custom = Color(0xFF195190);

  group('anchoredWordSpans', () {
    test('tint always lands on a letter, never punctuation', () {
      for (final (word, expected) in [
        ('to.', 'o'),
        ('it,', 't'),
        ('Minow,', 'i'),
        ('I’m,', 'm'),
        ('“Keep', 'e'),
      ]) {
        final tinted = _tinted(anchoredWordSpans(word, base), base);
        expect(tinted?.$1, expected, reason: word);
      }
    });

    test('spans rebuild the original word exactly', () {
      for (final word in ['to.', 'I’m,', 'café', '—']) {
        final text = anchoredWordSpans(
          word,
          base,
        ).cast<TextSpan>().map((s) => s.text ?? '').join();
        expect(text, word);
      }
    });

    test('uses the reader anchor colour', () {
      final tinted = _tinted(
        anchoredWordSpans('reading', base, anchorColor: custom),
        base,
      );
      expect(tinted?.$2, custom);
    });

    test('defaults to the stage focal red', () {
      final tinted = _tinted(anchoredWordSpans('reading', base), base);
      expect(tinted?.$2, RunThruTokens.stageFocalRed);
    });

    test('a token without letters gets no tint', () {
      expect(_tinted(anchoredWordSpans('—', base), base), isNull);
    });
  });
}
