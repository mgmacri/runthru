import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:runthru/services/models.dart';

/// Resolves a [ReadingRange] to global word indices using page boundaries,
/// with word-text anchor validation.
///
/// Returns an updated [ReadingRange] with [resolvedStartWordIndex] and
/// [resolvedEndWordIndex] populated.
///
/// If the anchor text no longer matches (e.g. the PDF was re-extracted with
/// slightly different text), the resolved index is kept on a best-effort basis
/// and a warning is logged. Returns `null` if the range is invalid and cannot
/// be resolved (e.g. boundaries are empty).
ReadingRange? resolveAndValidateRange(
  ReadingRange range,
  List<PageBoundary> boundaries,
  List<String> allWords,
) {
  if (boundaries.isEmpty || allWords.isEmpty) return null;

  final resolved = resolveRange(range, boundaries);
  var globalStart = resolved.globalStart.clamp(0, allWords.length - 1);
  var globalEnd = resolved.globalEnd.clamp(0, allWords.length - 1);

  // Validate start anchor text.
  if (range.startWordAnchor != null && range.startWordAnchor!.isNotEmpty) {
    if (globalStart < allWords.length &&
        allWords[globalStart] != range.startWordAnchor) {
      dev.log(
        'Range start anchor mismatch: expected "${range.startWordAnchor}", '
        'found "${allWords[globalStart]}" at index $globalStart',
        name: 'reading_range_resolver',
      );
    }
  }

  // Validate end anchor text.
  if (range.endWordAnchor != null && range.endWordAnchor!.isNotEmpty) {
    if (globalEnd < allWords.length &&
        allWords[globalEnd] != range.endWordAnchor) {
      dev.log(
        'Range end anchor mismatch: expected "${range.endWordAnchor}", '
        'found "${allWords[globalEnd]}" at index $globalEnd',
        name: 'reading_range_resolver',
      );
    }
  }

  // Ensure start <= end.
  if (globalStart > globalEnd) {
    dev.log(
      'Range start ($globalStart) > end ($globalEnd), swapping',
      name: 'reading_range_resolver',
    );
    final temp = globalStart;
    globalStart = globalEnd;
    globalEnd = temp;
  }

  return range.copyWith(
    resolvedStartWordIndex: globalStart,
    resolvedEndWordIndex: globalEnd,
  );
}

/// Finds the page number for a given global word index.
/// Returns the 0-indexed page number, or 0 if boundaries are empty.
int pageForWordIndex(int globalWordIndex, List<PageBoundary> boundaries) {
  if (boundaries.isEmpty) return 0;
  for (var i = boundaries.length - 1; i >= 0; i--) {
    if (boundaries[i].startWordIndex <= globalWordIndex) {
      return boundaries[i].pageNumber;
    }
  }
  return boundaries.first.pageNumber;
}

/// Returns the word index on the page for a global word index.
int wordIndexOnPage(int globalWordIndex, List<PageBoundary> boundaries) {
  if (boundaries.isEmpty) return globalWordIndex;
  for (var i = boundaries.length - 1; i >= 0; i--) {
    if (boundaries[i].startWordIndex <= globalWordIndex) {
      return math.max(0, globalWordIndex - boundaries[i].startWordIndex);
    }
  }
  return globalWordIndex;
}
