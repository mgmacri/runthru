/// ORP (Optimal Recognition Point) calculation.
/// Returns 1-indexed anchor position for a given word.
/// Uses the center character of the word.
int orpIndex(String word) {
  // Strip leading/trailing punctuation
  final stripped = word.replaceAll(
    RegExp(r'^[^a-zA-Z0-9]+|[^a-zA-Z0-9]+$'),
    '',
  );

  final length = stripped.length;
  if (length <= 0) return 1;

  // Center letter (1-indexed), slightly left of center for even lengths
  return (length + 1) ~/ 2;
}

/// Bucketed ORP index for focal word display (0-indexed).
/// Groups words by length:
/// - length 1 → index 0
/// - length 2–5 → index 1
/// - length 6–9 → index 2
/// - length 10–13 → index 3
/// - length ≥ 14 → index 4
int bucketedOrpIndex(String word) {
  final stripped = word.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  final length = stripped.length;
  if (length <= 0) return 0;
  return (length + 2) ~/ 4;
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

final RegExp _anchorableChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Index in [word] of the character every reading mode tints as the anchor,
/// or -1 when [word] has no letters or digits (a lone dash or ellipsis).
///
/// Punctuation anywhere in the word (leading quotes, trailing commas,
/// apostrophes, hyphens) is skipped, and letters outside ASCII count, so the
/// anchor always lands on a letter: "Minow," → `i`, "I’m," → `m`, "café" → `a`.
/// The position within the letters follows [bucketedOrpIndex].
int anchorIndexInWord(String word) {
  final letters = <int>[];
  for (var i = 0; i < word.length; i++) {
    if (_anchorableChar.hasMatch(word[i])) letters.add(i);
  }
  if (letters.isEmpty) return -1;
  final bucket = ((letters.length + 2) ~/ 4).clamp(0, letters.length - 1);
  return letters[bucket];
}
