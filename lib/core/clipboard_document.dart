import 'package:speedy_boy/services/models.dart';

/// Model for clipboard-sourced documents (Rule 28 — ephemeral, session-only).
///
/// Created from pasted text via [fromClipboardText]. The document is never
/// persisted to the library or bookmarks — reading position is tracked
/// during the session only and cleared on app restart.
class ClipboardDocument {
  const ClipboardDocument({
    required this.title,
    required this.fullText,
    required this.document,
    required this.pastedAt,
  });

  /// Tokenize clipboard text into an [ExtractedDocument] using the same
  /// sentence-splitting logic as the PDF pipeline.
  ///
  /// Title is extracted from the first 40 characters of the text, or
  /// defaults to "Clipboard" if the text is too short. Paragraph breaks
  /// (`\n\n`) are treated as sentence boundaries.
  factory ClipboardDocument.fromClipboardText(String text) {
    final trimmed = text.trim();
    final stripped = _stripMarkdown(trimmed);
    final title = _extractTitle(stripped);
    final sentences = _textToSentences(stripped);
    final document = ExtractedDocument(sentences: sentences);

    return ClipboardDocument(
      title: title,
      fullText: trimmed,
      document: document,
      pastedAt: DateTime.now(),
    );
  }

  /// Display title — first 40 characters of the text, or "Clipboard".
  final String title;

  /// The original full text as pasted.
  final String fullText;

  /// Parsed document with sentence structure and word lists.
  final ExtractedDocument document;

  /// Timestamp when the text was pasted.
  final DateTime pastedAt;

  /// Convenience — flat list of all words in reading order.
  List<String> get words => document.allWords;

  /// Strip common markdown formatting to produce clean reading text.
  ///
  /// Handles: headings (#), bold/italic (** / * / __ / _), strikethrough (~~),
  /// inline code (`), links [text](url), images ![alt](url),
  /// blockquotes (>), horizontal rules (--- / ***), and list markers (- / * / +).
  /// Preserves the readable text content — only formatting syntax is removed.
  // SPEC GAP — markdown stripping for clipboard, conservative approach
  static String _stripMarkdown(String text) {
    var result = text;

    // Remove images: ![alt](url) → alt
    result = result.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
      (m) => m.group(1)!,
    );

    // Convert links: [text](url) → text
    result = result.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (m) => m.group(1)!,
    );

    // Remove reference-style links: [text][ref] → text
    result = result.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\[[^\]]*\]'),
      (m) => m.group(1)!,
    );

    // Remove heading markers: ### heading → heading
    result = result.replaceAllMapped(
      RegExp(r'^#{1,6}\s+(.+)$', multiLine: true),
      (m) => m.group(1)!,
    );

    // Remove horizontal rules (---, ***, ___)
    result = result.replaceAll(
      RegExp(r'^[\s]*[-*_]{3,}[\s]*$', multiLine: true),
      '',
    );

    // Remove blockquote markers: > text → text
    result = result.replaceAllMapped(
      RegExp(r'^>\s?(.*)$', multiLine: true),
      (m) => m.group(1)!,
    );

    // Remove bold+italic: ***text*** or ___text___
    result = result.replaceAllMapped(
      RegExp(r'\*{3}(.+?)\*{3}'),
      (m) => m.group(1)!,
    );
    result = result.replaceAllMapped(
      RegExp(r'_{3}(.+?)_{3}'),
      (m) => m.group(1)!,
    );

    // Remove bold: **text** or __text__
    result = result.replaceAllMapped(
      RegExp(r'\*{2}(.+?)\*{2}'),
      (m) => m.group(1)!,
    );
    result = result.replaceAllMapped(
      RegExp(r'_{2}(.+?)_{2}'),
      (m) => m.group(1)!,
    );

    // Remove italic: *text* or _text_ (only around word chars)
    result = result.replaceAllMapped(
      RegExp(r'\*(\S[^*]*\S|\S)\*'),
      (m) => m.group(1)!,
    );
    result = result.replaceAllMapped(
      RegExp(r'(?<=\s|^)_(\S[^_]*\S|\S)_(?=\s|$)'),
      (m) => m.group(1)!,
    );

    // Remove standalone * or ** markers (e.g. "* word" bullet points)
    result = result.replaceAll(RegExp(r'(?<=\s|^)\*{1,2}(?=\s)'), '');

    // Remove strikethrough: ~~text~~
    result = result.replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => m.group(1)!);

    // Remove inline code: `code`
    result = result.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1)!);

    // Remove unordered list markers: - item, * item, + item
    result = result.replaceAllMapped(
      RegExp(r'^[\s]*[-*+]\s+(.+)$', multiLine: true),
      (m) => m.group(1)!,
    );

    // Remove ordered list markers: 1. item, 2. item
    result = result.replaceAllMapped(
      RegExp(r'^[\s]*\d+\.\s+(.+)$', multiLine: true),
      (m) => m.group(1)!,
    );

    // Collapse multiple blank lines
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return result.trim();
  }

  /// Extract a display title from the first line/40 chars of text.
  static String _extractTitle(String text) {
    if (text.isEmpty) return 'Clipboard';

    // Use first line if it's short enough.
    final firstLine = text.split('\n').first.trim();
    if (firstLine.isNotEmpty && firstLine.length <= 40) return firstLine;

    // Truncate to 40 chars at a word boundary.
    if (text.length <= 40) return text.replaceAll('\n', ' ').trim();
    final truncated = text.substring(0, 40);
    final lastSpace = truncated.lastIndexOf(' ');
    final boundary = lastSpace > 20 ? lastSpace : 40;
    return '${truncated.substring(0, boundary).trim()}\u2026';
  }

  /// Splits raw text into [Sentence] objects — same logic as PDF pipeline.
  ///
  /// Paragraph breaks (`\n\n`) are normalized to sentence boundaries before
  /// splitting on `.!?` followed by whitespace.
  static List<Sentence> _textToSentences(String text) {
    // Normalize paragraph breaks to sentence terminators.
    // P28 — treat \n\n as sentence boundaries
    final normalized = text.replaceAll(RegExp(r'\n{2,}'), '. ');

    final sentencePattern = RegExp(r'(?<=[.!?])\s+');
    final rawSentences = normalized.split(sentencePattern);
    final sentences = <Sentence>[];

    for (final raw in rawSentences) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;

      final words = trimmed
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      if (words.isNotEmpty) {
        sentences.add(Sentence(words: words));
      }
    }

    return sentences;
  }
}
