/// ORP (Optimal Recognition Point) calculation.
/// Returns 1-indexed anchor position for a given word.
int orpIndex(String word) {
  // Strip leading/trailing punctuation
  final stripped = word.replaceAll(
    RegExp(r'^[^a-zA-Z0-9]+|[^a-zA-Z0-9]+$'),
    '',
  );

  final length = stripped.length;
  if (length <= 0) return 1;

  if (length <= 3) return 1;
  if (length <= 5) return 2;
  if (length <= 9) return 3;
  if (length <= 13) return 4;
  return 5;
}

/// Returns the number of leading punctuation characters in [word].
/// Used to offset the ORP index back into the original word.
int leadingPunctuationCount(String word) {
  final match = RegExp(r'^[^a-zA-Z0-9]+').firstMatch(word);
  return match?.group(0)?.length ?? 0;
}

/// Returns the anchor index in the original (un-stripped) word.
int orpIndexInOriginal(String word) {
  return leadingPunctuationCount(word) + orpIndex(word);
}
