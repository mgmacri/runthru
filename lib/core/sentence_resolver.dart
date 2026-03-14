import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/store/models.dart';

/// Returns the index of the first word of the sentence
/// containing [bookmark.wordIndex].
///
/// Sentences are flattened to a global word index space.
/// If the bookmark is already at a sentence start, returns same.
int resumeIndex(BookmarkData bookmark, ExtractedDocument doc) {
  if (doc.sentences.isEmpty) return 0;

  var globalIndex = 0;
  for (final sentence in doc.sentences) {
    final sentenceEnd = globalIndex + sentence.words.length;
    if (bookmark.wordIndex < sentenceEnd) {
      return globalIndex;
    }
    globalIndex = sentenceEnd;
  }

  // Bookmark is past end — return last sentence start
  var lastStart = 0;
  for (var i = 0; i < doc.sentences.length - 1; i++) {
    lastStart += doc.sentences[i].words.length;
  }
  return lastStart;
}
