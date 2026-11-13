import 'dart:isolate';

import 'package:runthru/core/text_segmentation.dart';
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
  static ExtractedDocument _normaliseSync(String raw, ContentType type) {
    final input = raw.replaceAll(kReservedMarkChars, '');
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

  /// The page's title: `og:title` when present, otherwise `<title>`.
  /// Null when the page has neither.
  static String? htmlTitle(String html) {
    // The value runs to the quote that opened it: a title in double quotes
    // may hold an apostrophe ("Don't Panic").
    final og = RegExp(
      r"""<meta[^>]+property=["']og:title["'][^>]*content=(["'])(.*?)\1""",
      caseSensitive: false,
    ).firstMatch(html);
    final raw =
        og?.group(2) ??
        RegExp(
          r'<title[^>]*>([\s\S]*?)</title>',
          caseSensitive: false,
        ).firstMatch(html)?.group(1);
    if (raw == null) return null;
    final title = _decodeEntities(raw).replaceAll(RegExp(r'\s+'), ' ').trim();
    return title.isEmpty ? null : title;
  }

  /// Readable text from an HTML page, like an e-reader's reading view.
  ///
  /// Drops page chrome (navigation, headers, footers, sidebars, forms,
  /// tables, figures) unless it holds most of the page's words, keeps only
  /// `<article>` or `<main>` when the page has one, removes citation
  /// markers ("[1]", "[edit]", superscript note links), and turns block
  /// elements into paragraph breaks.
  static String _stripHtml(String html) {
    var text = html;

    // Never content: head, scripts, styles, embedded media, comments.
    for (final tag in const [
      'head',
      'script',
      'style',
      'noscript',
      'svg',
      'template',
      'iframe',
    ]) {
      text = _dropElement(text, tag);
    }
    text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    // Prefer the main content region when the page marks one.
    final region = _innerOf(text, 'article') ?? _innerOf(text, 'main') ?? text;
    text = region;

    // Page chrome and non-prose blocks. An element that holds most of the
    // words is the page itself, not its chrome: a form wrapped around the
    // whole body (every ASP.NET WebForms page), a table used for layout.
    // Those are kept, and only their tags go.
    for (final tag in const [
      'nav',
      'header',
      'footer',
      'aside',
      'form',
      'button',
      'menu',
      'table',
      'figure',
    ]) {
      final without = _dropElement(text, tag);
      if (_textLength(without) * 2 < _textLength(text)) continue;
      text = without;
    }
    text = _dropNoteMarkers(text);

    // Link lists (tabs, tables of contents, menus) and small link-only
    // elements ("edit", "Talk") are navigation.
    text = _dropLinkLists(text);
    text = _dropLinkOnlyElements(text);
    text = _dropWikiChrome(text);

    // The source's line wrapping is not structure.
    text = text.replaceAll(RegExp(r'\s+'), ' ');

    // Headings keep their level: they stay whole ("2. Results" is not split
    // at the full stop) and the reader can announce them.
    text = text.replaceAllMapped(
      RegExp(r'<h([1-6])(\s[^>]*)?>', caseSensitive: false),
      (m) => '\n\n${headingMark(int.parse(m.group(1)!))}',
    );

    // Block elements (opening or closing, with attributes) → paragraph
    // breaks. <br> is a soft line break.
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ');
    text = text.replaceAll(
      RegExp(
        r'</?(p|div|h[1-6]|li|ul|ol|tr|td|th|caption|blockquote|section|article|main|dd|dt|dl|figcaption|pre|hr)(\s[^>]*)?>',
        caseSensitive: false,
      ),
      '\n\n',
    );

    // Remaining tags are inline (<a>, <em>, <span>): they vanish without
    // adding a space, so "</a>," stays "word," not "word ,".
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');

    // Decode HTML entities.
    text = _decodeEntities(text);
    text = tidyInlineSpacing(text);

    // Citation and edit markers left by wikis and news sites.
    text = text.replaceAll(RegExp(r'\[(\d+|edit|citation needed)\]'), '');

    // Collapse whitespace, preserve paragraph breaks.
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r' *\n *'), '\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return text.trim();
  }

  /// Removes lists that are mostly links with short items: tabs, tables of
  /// contents, menus. Innermost lists go first so nested menus come out
  /// whole.
  static String _dropLinkLists(String html) {
    final innermost = RegExp(
      r'<(ul|ol)(\s[^>]*)?>((?:(?!<(?:ul|ol)[\s>])[\s\S])*?)</\1>',
      caseSensitive: false,
    );
    var previous = '';
    var text = html;
    while (previous != text) {
      previous = text;
      text = text.replaceAllMapped(innermost, (m) {
        final inner = m.group(3)!;
        final items = RegExp(
          r'<li[\s>]',
          caseSensitive: false,
        ).allMatches(inner).length;
        final plain = inner.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
        final linked = RegExp(r'<a[\s>][\s\S]*?</a>', caseSensitive: false)
            .allMatches(inner)
            .map((a) => a.group(0)!.replaceAll(RegExp(r'<[^>]+>'), ''))
            .join(' ');
        final words = plain.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
        final shortItems = items > 0 && words.length / items <= 6;
        final mostlyLinks =
            plain.isNotEmpty && linked.trim().length >= plain.length * 0.6;
        // Keep the list's text in place of nested-list markers so an outer
        // list can still be judged; drop navigation lists entirely.
        return shortItems && mostlyLinks ? ' ' : '<p>$inner</p>';
      });
    }
    return text;
  }

  /// Removes small elements whose whole text is one short link, such as
  /// "edit" beside a heading or "Article" / "Talk" tabs. Headings and
  /// prose are untouched: their text is not a link.
  static String _dropLinkOnlyElements(String html) {
    final element = RegExp(
      r'<(span|div|li|p)(\s[^>]*)?>((?:(?!<(?:span|div|li|p)[\s>])[\s\S])*?)</\1>',
      caseSensitive: false,
    );
    String strip(String s) => s
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return html.replaceAllMapped(element, (m) {
      final inner = m.group(3)!;
      final plain = strip(inner);
      if (plain.isEmpty || plain.split(' ').length > 3) return m.group(0)!;
      final links = RegExp(
        r'<a(?:\s[^>]*)?>([\s\S]*?)</a>',
        caseSensitive: false,
      ).allMatches(inner).map((a) => strip(a.group(1)!)).join(' ').trim();
      return links == plain ? ' ' : m.group(0)!;
    });
  }

  /// MediaWiki conventions shared by Wikipedia and most wikis: "edit"
  /// links beside headings, the "Contents" heading of the (already
  /// removed) table of contents, and cross-reference notes ("Main
  /// article: …", "See also: …", "Further information: …").
  static String _dropWikiChrome(String html) => html
      .replaceAll(
        RegExp(
          r'<a(?:\s[^>]*)?>(?:\s|<[^>]+>)*\[?edit\]?(?:\s|<[^>]+>)*</a>',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'<(h[1-6])(\s[^>]*)?>(?:\s|<[^>]+>)*(table of )?contents(?:\s|<[^>]+>)*</\1>',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'<(div|p)(\s[^>]*)?>(?:\s|<[^>]+>)*(main article|see also|further information):(?:(?!</?\1[\s>])[\s\S])*?</\1>',
          caseSensitive: false,
        ),
        ' ',
      );

  /// Removes every `<tag …>…</tag>` (case-insensitive, non-greedy).
  static String _dropElement(String html, String tag) => html.replaceAll(
    RegExp('<$tag(\\s[^>]*)?>[\\s\\S]*?</$tag>', caseSensitive: false),
    ' ',
  );

  /// Inner HTML of the largest `<tag>` element, or null if there is none.
  ///
  /// Elements of one tag nest (an embedded card or a comment inside an
  /// article is an `<article>` too), so opening and closing tags are
  /// counted: stopping at the first closing tag would end the article at
  /// the end of the first thing embedded in it.
  static String? _innerOf(String html, String tag) {
    String? best;
    void offer(String inner) {
      if (best == null || inner.length > best!.length) best = inner;
    }

    var depth = 0;
    var innerStart = 0;
    for (final m in RegExp(
      '<(/?)$tag(?:\\s[^>]*)?>',
      caseSensitive: false,
    ).allMatches(html)) {
      if (m.group(1)!.isEmpty) {
        if (depth == 0) innerStart = m.end;
        depth++;
      } else if (depth > 0) {
        depth--;
        if (depth == 0) offer(html.substring(innerStart, m.start));
      }
    }
    // An element never closed runs to the end of the page.
    if (depth > 0) offer(html.substring(innerStart));
    return best;
  }

  /// How much text [html] holds: its characters without tags and spaces.
  static int _textLength(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .length;

  /// A superscript that is a note marker goes; any other superscript is
  /// text and stays ("21st", "Mlle", "10^6").
  ///
  /// A marker is a bracketed reference ("[1]", "[citation needed]"), or a
  /// number, symbol or single letter that links to its note or sits in an
  /// element named for references. A bare number is not taken for one: it
  /// is as likely an exponent or a unit ("km2").
  static String _dropNoteMarkers(String html) => html.replaceAllMapped(
    RegExp(r'(\d?)<sup(\s[^>]*)?>([\s\S]*?)</sup>', caseSensitive: false),
    (m) {
      final before = m.group(1)!;
      final attributes = m.group(2) ?? '';
      final inner = m.group(3)!;
      final plain = inner
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final bracketed = RegExp(r'^\[[^\]]{1,24}\]$').hasMatch(plain);
      final pointsToNote =
          RegExp(r'<a[\s>]', caseSensitive: false).hasMatch(inner) ||
          RegExp(
            r'reference|footnote|noteref|cite',
            caseSensitive: false,
          ).hasMatch(attributes);
      if (bracketed ||
          (pointsToNote && (plain.isEmpty || _noteMarker.hasMatch(plain)))) {
        return before;
      }
      // A number raised on a number is a power.
      if (before.isNotEmpty && RegExp(r'^\d+$').hasMatch(plain)) {
        return '$before^$plain';
      }
      return '$before$inner';
    },
  );

  /// The text of a footnote marker: a number, a symbol or one letter,
  /// bracketed or not (the EPUB extractor's rule).
  static final RegExp _noteMarker = RegExp(
    r'^[\[(]?\s*(?:\d{1,4}|[*†‡§¶]+|[a-z])\s*[\])]?$',
  );

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

    // Headings: "### Title" becomes a heading paragraph of that level.
    result = result.replaceAllMapped(
      // Spaces and tabs only, never a line break: `\s` would run on into
      // the next line. A closing run of hashes needs a space before it,
      // so "## Learning C#" keeps its last character.
      RegExp(r'^(#{1,6})[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$', multiLine: true),
      (m) => '\n\n${headingMark(m.group(1)!.length)}${m.group(2)!}\n\n',
    );

    // Remove horizontal rules.
    result = result.replaceAll(
      RegExp(r'^[ \t]*[-*_]{3,}[ \t]*$', multiLine: true),
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
      // `[ \t]`, not `\s`: a marker's indent must not reach back over the
      // blank line above it, which would join the list to the paragraph
      // (or heading) before it.
      RegExp(r'^[ \t]*[-*+][ \t]+(.+)$', multiLine: true),
      (m) => m.group(1)!,
    );

    // Remove ordered list markers.
    result = result.replaceAllMapped(
      RegExp(r'^[ \t]*\d+\.[ \t]+(.+)$', multiLine: true),
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

  /// Paragraph breaks (blank lines) start a new paragraph; they no longer
  /// insert a full stop into the text. See [textToSentences].
  static List<Sentence> _textToSentences(String text) => textToSentences(text);

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
