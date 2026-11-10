import 'package:runthru/services/models.dart';
import 'package:runthru/store/models.dart';

/// Inclusive bounds for a sentence in a flat word list.
typedef SentenceBounds = ({int start, int end});

/// Finds the inclusive sentence bounds containing [wordIndex].
///
/// This helper works on the flat word slices used by the reading timer. It
/// clamps out-of-range indices and falls back to punctuation boundaries when
/// structured [Sentence] records are not available in the view layer.
SentenceBounds sentenceBoundsForWord(List<String> words, int wordIndex) {
  if (words.isEmpty) return (start: 0, end: -1);

  final clampedIndex = wordIndex.clamp(0, words.length - 1);
  var start = clampedIndex;
  while (start > 0 && !_isSentenceEnd(words[start - 1])) {
    start--;
  }

  var end = clampedIndex;
  while (end < words.length - 1 && !_isSentenceEnd(words[end])) {
    end++;
  }

  return (start: start, end: end);
}

bool _isSentenceEnd(String word) {
  final trimmed = word.trimRight();
  return trimmed.endsWith('.') ||
      trimmed.endsWith('!') ||
      trimmed.endsWith('?');
}

/// Returns the index of the first word of the sentence
/// containing [bookmark.wordIndex].
///
/// Sentences are flattened to a global word index space.
/// If the bookmark is already at a sentence start, returns same.
///
/// If a [ReadingRange] is set on the bookmark and the index falls
/// before the range start, snaps to [resolvedStartWordIndex].
int resumeIndex(BookmarkData bookmark, ExtractedDocument doc) {
  if (doc.sentences.isEmpty) return 0;

  final range = bookmark.readingRange;
  final minIndex = range?.resolvedStartWordIndex ?? 0;

  var globalIndex = 0;
  for (final sentence in doc.sentences) {
    final sentenceEnd = globalIndex + sentence.words.length;
    if (bookmark.wordIndex < sentenceEnd) {
      return globalIndex < minIndex ? minIndex : globalIndex;
    }
    globalIndex = sentenceEnd;
  }

  // Bookmark is past end — return last sentence start
  var lastStart = 0;
  for (var i = 0; i < doc.sentences.length - 1; i++) {
    lastStart += doc.sentences[i].words.length;
  }
  return lastStart < minIndex ? minIndex : lastStart;
}

/// A slice of a sentence that fits a small context panel and always contains
/// the current word.
typedef SentenceWindow = ({
  List<String> words,
  int highlight,
  bool clippedStart,
  bool clippedEnd,
});

/// Returns at most [maxWords] of [words] around [highlight], keeping about a
/// third of the window before the current word so the reader sees what led
/// up to it. Short sentences come back whole.
SentenceWindow sentenceWindowAround(
  List<String> words,
  int highlight, {
  int maxWords = 30,
}) {
  final h = words.isEmpty ? 0 : highlight.clamp(0, words.length - 1);
  if (words.length <= maxWords) {
    return (words: words, highlight: h, clippedStart: false, clippedEnd: false);
  }
  final start = (h - maxWords ~/ 3).clamp(0, words.length - maxWords);
  final end = start + maxWords;
  return (
    words: words.sublist(start, end),
    highlight: h - start,
    clippedStart: start > 0,
    clippedEnd: end < words.length,
  );
}
