import 'package:flutter/material.dart';
import 'package:runthru/core/orp.dart';
import 'package:runthru/design/design.dart';

/// Splits [word] into spans with the ORP (optimal recognition point)
/// letter tinted in the stage focal colour. Shared by the continuous-text
/// reading modes for inked (read/active) words.
List<InlineSpan> anchoredWordSpans(String word, TextStyle style) {
  if (word.isEmpty) return [TextSpan(text: word, style: style)];
  final stripped = word.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  final strippedStart = stripped.isEmpty ? 0 : word.indexOf(stripped);
  final orpIndex = stripped.isEmpty ? 0 : bucketedOrpIndex(stripped);
  final anchorIndex = (strippedStart < 0 ? orpIndex : strippedStart + orpIndex)
      .clamp(0, word.length - 1);
  return [
    TextSpan(text: word.substring(0, anchorIndex), style: style),
    TextSpan(
      text: word.substring(anchorIndex, anchorIndex + 1),
      style: style.copyWith(color: RunThruTokens.stageFocalRed),
    ),
    TextSpan(text: word.substring(anchorIndex + 1), style: style),
  ];
}
