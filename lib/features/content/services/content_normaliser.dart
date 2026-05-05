import 'dart:isolate';

import 'package:runthru/services/models.dart';

/// Content types supported by the normaliser.
enum ContentType {
  /// Plain text — no formatting to strip.
  plainText,

  /// Markdown — headings, bold, italic, links, etc.
  markdown,

  /// HTML — tags, entities, inline styles.
  html,
}

/// Approximate words per "page" for generating page boundaries.
const int _wordsPerPage = 300;

/// Byte threshold above which processing runs in a background isolate.
const int _isolateThreshold = 10 * 1024; // 10 KB

/// Normalises plain text, Markdown, and HTML content into an
/// [ExtractedDocument] ready for the reading pipeline.
///
/// Reuses sentence/word tokenisation logic consistent with
/// [ClipboardDocument.fromClipboardText] for DRY compliance.
///
/// Processing runs in [Isolate.run()] for inputs larger than 10 KB
/// to avoid blocking the main event loop.
class ContentNormaliser {
  /// Normalise [input] of the given [type] into an [ExtractedDocument].
  ///
  /// For [ContentType.html]: strips all tags, decodes entities, preserves
  /// paragraph breaks as section markers.
  ///
  /// For [ContentType.markdown]: strips headings, bold/italic, links,
  /// list markers — preserves the readable text.
  ///
  /// For [ContentType.plainText]: tokenises directly into sentences
  /// and words.
  ///
  /// Output includes page boundaries based on ~300-word "pages".
  static Future<ExtractedDocument> normalise(
    String input,
    ContentType type,
  ) async {
    if (input.length > _isolateThreshold) {
      return Isolate.run(() => _normaliseSync(input, type));
    }
    return _normaliseSync(input, type);
  }

  /// Synchronous normalisation — called directly or from an isolate.
  static ExtractedDocument _normaliseSync(String input, ContentType type) {
    final cleaned = switch (type) {
      ContentType.html => _stripHtml(input),
      ContentType.markdown => _stripMarkdown(input),
      ContentType.plainText => input,
    };

    final sentences = _textToSentences(cleaned);
    final pageBoundaries = _generatePageBoundaries(sentences);

    return ExtractedDocument(
      sentences: sentences,
      pageBoundaries: pageBoundaries,
      totalPages: pageBoundaries.length,
    );
  }

  /// Strip HTML tags, decode entities, preserve paragraph breaks.
  static String _stripHtml(String html) {
    var text = html;

    // Remove <style> and <script> blocks.
    text = text.replaceAll(
      RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
      '',
    );

    // Remove inline style attributes.
    text = text.replaceAll(RegExp(r'\s+style\s*=\s*"[^"]*"'), '');
    text = text.replaceAll(RegExp(r"\s+style\s*=\s*'[^']*'"), '');

    // Block elements → paragraph breaks.
    text = text.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    text = text.replaceAll(
      RegExp(
        r'</(p|div|h[1-6]|li|tr|blockquote|section|article)>',
        caseSensitive: false,
      ),
      '\n\n',
    );

    // Strip all remaining tags.
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');

    // Decode HTML entities.
    text = _decodeEntities(text);

    // Collapse whitespace, preserve paragraph breaks.
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return text.trim();
  }

  /// Strip Markdown formatting — preserve readable text.
  static String _stripMarkdown(String text) {
    var result = text;

    // Remove fenced code blocks: ```lang\n...\n``` → removed entirely.
    // Must run before inline code stripping to avoid partial backtick matches.
    result = result.replaceAll(
      RegExp(r'```[^\n]*\n[\s\S]*?```', multiLine: true),
      '',
    );

    // Remove indented code blocks: blank line followed by 4+ space-indented lines.
    result = result.replaceAll(
      RegExp(r'(?<=\n\n)([ \t]{4,}[^\n]+\n?)+', multiLine: true),
      '',
    );

    // Remove markdown tables: lines starting/ending with pipes, including
    // header separator.
    result = result.replaceAll(
      RegExp(
        r'^\|[^\n]+\|[ \t]*\n(\|[-:\s|]+\|\n)?(\|[^\n]+\|[ \t]*\n?)*',
        multiLine: true,
      ),
      '',
    );

    // Remove footnote definitions: [^id]: text at line start.
    result = result.replaceAll(
      RegExp(r'^\[\^[^\]]+\]:[ \t]+[^\n]+$', multiLine: true),
      '',
    );

    // Remove footnote references: [^id] inline.
    result = result.replaceAll(RegExp(r'\[\^[^\]]+\]'), '');

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

    // Remove horizontal rules.
    result = result.replaceAll(
      RegExp(r'^[\s]*[-*_]{3,}[\s]*$', multiLine: true),
      '',
    );

    // Remove blockquote markers.
    result = result.replaceAllMapped(
      RegExp(r'^>\s?(.*)$', multiLine: true),
      (m) => m.group(1)!,
    );

    // Remove bold+italic (***text*** / ___text___).
    result = result.replaceAllMapped(
      RegExp(r'(?<!\\)\*{3}(.+?)(?<!\\)\*{3}'),
      (m) => m.group(1)!,
    );
    result = result.replaceAllMapped(
      RegExp(r'_{3}(.+?)_{3}'),
      (m) => m.group(1)!,
    );

    // Remove bold (**text** / __text__).
    result = result.replaceAllMapped(
      RegExp(r'(?<!\\)\*{2}(.+?)(?<!\\)\*{2}'),
      (m) => m.group(1)!,
    );
    result = result.replaceAllMapped(
      RegExp(r'_{2}(.+?)_{2}'),
      (m) => m.group(1)!,
    );

    // Remove italic (*text* / _text_).
    result = result.replaceAllMapped(
      RegExp(r'(?<!\\)\*(\S[^*]*\S|\S)(?<!\\)\*'),
      (m) => m.group(1)!,
    );
    result = result.replaceAllMapped(
      RegExp(r'(?<=\s|^)_(\S[^_]*\S|\S)_(?=\s|$)'),
      (m) => m.group(1)!,
    );

    // Remove strikethrough: ~~text~~.
    result = result.replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => m.group(1)!);

    // Remove inline code: `code`.
    result = result.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1)!);

    // Remove unordered list markers.
    result = result.replaceAllMapped(
      RegExp(r'^[\s]*[-*+]\s+(.+)$', multiLine: true),
      (m) => m.group(1)!,
    );

    // Remove ordered list markers.
    result = result.replaceAllMapped(
      RegExp(r'^[\s]*\d+\.\s+(.+)$', multiLine: true),
      (m) => m.group(1)!,
    );

    // Remove markdown escape backslashes: \* → *, \[ → [, etc.
    result = result.replaceAllMapped(
      RegExp(r'\\([\\`*_\{\}\[\]()#+\-.!|~])'),
      (m) => m.group(1)!,
    );

    // Collapse multiple blank lines.
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return result.trim();
  }

  /// Decode common HTML entities (named + numeric).
  static String _decodeEntities(String text) {
    var result = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '…')
        .replaceAll('&ldquo;', '\u201C')
        .replaceAll('&rdquo;', '\u201D')
        .replaceAll('&lsquo;', '\u2018')
        .replaceAll('&rsquo;', '\u2019');

    // Decode numeric hex entities.
    result = result.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code != null ? String.fromCharCode(code) : '';
    });

    // Decode numeric decimal entities.
    result = result.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code != null ? String.fromCharCode(code) : '';
    });

    // Strip remaining unrecognised entities.
    result = result.replaceAll(RegExp(r'&\w+;'), '');

    return result;
  }

  /// Split text into [Sentence] objects — same logic as PDF/clipboard pipeline.
  ///
  /// Paragraph breaks (\n\n) are normalised to sentence boundaries first.
  static List<Sentence> _textToSentences(String text) {
    // Treat paragraph breaks as sentence boundaries.
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
      // Skip sentences that are just punctuation artefacts.
      if (words.isNotEmpty &&
          !words.every((w) => RegExp(r'^[.!?,;:\-]+$').hasMatch(w))) {
        sentences.add(Sentence(words: words));
      }
    }

    return sentences;
  }

  /// Generate page boundaries based on ~300-word "pages".
  static List<PageBoundary> _generatePageBoundaries(List<Sentence> sentences) {
    final boundaries = <PageBoundary>[];
    var currentWordIndex = 0;
    var currentPageWords = 0;
    var pageNumber = 0;

    for (var i = 0; i < sentences.length; i++) {
      if (currentPageWords == 0 || currentPageWords >= _wordsPerPage) {
        final firstWords = sentences[i].words.take(5).join(' ');
        boundaries.add(
          PageBoundary(
            pageNumber: pageNumber,
            startSentenceIndex: i,
            startWordIndex: currentWordIndex,
            firstWords: firstWords,
          ),
        );
        pageNumber++;
        currentPageWords = 0;
      }
      currentPageWords += sentences[i].words.length;
      currentWordIndex += sentences[i].words.length;
    }

    // Ensure at least one page boundary for empty/short content.
    if (boundaries.isEmpty) {
      boundaries.add(
        const PageBoundary(
          pageNumber: 0,
          startSentenceIndex: 0,
          startWordIndex: 0,
        ),
      );
    }

    return boundaries;
  }
}
