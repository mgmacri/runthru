import 'package:runthru/services/models.dart';

/// Shared text → [Sentence] segmentation for EPUB, article and clipboard
/// text.
///
/// Input is plain text in which a paragraph break is a blank line (two or
/// more newlines). A single newline is ordinary whitespace: pasted and
/// extracted text often hard-wraps every line.
/// Each paragraph is split into sentences on terminal punctuation followed
/// by whitespace, allowing closing quotes and brackets after the stop
/// (`said.” Then` splits after the quote). The first sentence of each
/// paragraph is marked [Sentence.startsParagraph], so paged and flowing
/// views can lay out real paragraphs and headings stay on their own line.
///
/// Paragraph breaks never insert punctuation: a heading such as
/// "Chapter One" stays "Chapter One", it does not become "Chapter One.".
List<Sentence> textToSentences(String text) {
  final sentences = <Sentence>[];
  for (final paragraph in text.split(_paragraphBreak)) {
    var first = true;
    for (final raw in paragraph.split(_sentenceBreak)) {
      final words = raw
          .trim()
          .split(_whitespace)
          .where((w) => w.isNotEmpty)
          .toList();
      if (words.isEmpty) continue;
      // A lone punctuation run ("." left by a stray full stop) is noise.
      if (words.every(_punctuationOnly.hasMatch)) continue;
      sentences.add(Sentence(words: words, startsParagraph: first));
      first = false;
    }
  }
  return sentences;
}

final RegExp _paragraphBreak = RegExp(r'\n[ \t]*\n\s*');
final RegExp _sentenceBreak = RegExp('(?<=[.!?…][”’"\')\\]]*)\\s+');
final RegExp _whitespace = RegExp(r'\s+');
final RegExp _punctuationOnly = RegExp(r'^[.!?,;:\-…]+$');

/// Global word indices that begin a paragraph in [document].
///
/// Returns an empty set for documents extracted before paragraph data was
/// stored; callers fall back to their own heuristics.
Set<int> paragraphStartWordIndices(ExtractedDocument document) {
  final starts = <int>{};
  var index = 0;
  for (final sentence in document.sentences) {
    if (sentence.startsParagraph && sentence.words.isNotEmpty) {
      starts.add(index);
    }
    index += sentence.words.length;
  }
  return starts;
}

/// Removes stray spaces that markup leaves before punctuation and inside
/// brackets: "shoals , reefs" → "shoals, reefs", "( note )" → "(note)".
/// Quotes are left alone: ’ is also an apostrophe ("the ’90s").
String tidyInlineSpacing(String text) => text
    .replaceAllMapped(RegExp(r'[ \t]+([,.;:!?)\]}])'), (m) => m.group(1)!)
    .replaceAllMapped(RegExp(r'([(\[{])[ \t]+'), (m) => m.group(1)!);
