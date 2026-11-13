import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/services/content_normaliser.dart';
import 'package:runthru/services/models.dart';

void main() {
  group('ContentNormaliser — plain text', () {
    test('tokenises simple text into sentences and words', () async {
      const input = 'Hello world. This is a test. Another sentence here.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.plainText,
      );

      expect(doc.sentences, isNotEmpty);
      expect(doc.totalWords, greaterThan(0));
      expect(doc.allWords, contains('Hello'));
      expect(doc.allWords, contains('test.'));
    });

    test('handles paragraphs as sentence boundaries', () async {
      const input = 'First paragraph text here\n\nSecond paragraph text here';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.plainText,
      );

      expect(doc.sentences.length, greaterThanOrEqualTo(2));
    });

    test('handles empty input', () async {
      final doc = await ContentNormaliser.normalise('', ContentType.plainText);
      expect(doc.sentences, isEmpty);
      expect(doc.totalWords, 0);
    });

    test('handles whitespace-only input', () async {
      final doc = await ContentNormaliser.normalise(
        '   \n\n  ',
        ContentType.plainText,
      );
      expect(doc.sentences, isEmpty);
    });

    test('generates page boundaries for long text', () async {
      // Create text with ~600 words (should be ~2 pages at 300 words/page).
      final words = List.generate(600, (i) => 'word$i');
      final input =
          '${words.sublist(0, 300).join(' ')}. ${words.sublist(300).join(' ')}.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.plainText,
      );

      expect(doc.pageBoundaries, isNotEmpty);
      expect(doc.pageBoundaries.length, greaterThanOrEqualTo(2));
    });

    test('page boundaries have increasing word indices', () async {
      final words = List.generate(900, (i) => 'word$i');
      final input = '${words.join(' ')}.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.plainText,
      );

      for (var i = 1; i < doc.pageBoundaries.length; i++) {
        expect(
          doc.pageBoundaries[i].startWordIndex,
          greaterThan(doc.pageBoundaries[i - 1].startWordIndex),
        );
      }
    });
  });

  group('ContentNormaliser — Markdown', () {
    test('strips heading markers', () async {
      const input = '# Heading One\n\n## Heading Two\n\nBody text here.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('Heading'));
      expect(allText, isNot(contains('#')));
    });

    test('headings become heading lines with their level', () async {
      const input = '# Heading One\n\n## 2. Heading Two\n\nBody text here.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );
      expect(doc.sentences[0].heading, 1);
      expect(doc.sentences[0].words, ['Heading', 'One']);
      expect(doc.sentences[1].heading, 2);
      expect(doc.sentences[1].words.join(' '), '2. Heading Two');
      expect(doc.sentences[2].isHeading, isFalse);
    });

    test('strips bold markers', () async {
      const input = 'This is **bold** and __also bold__ text.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('bold'));
      expect(allText, isNot(contains('**')));
      expect(allText, isNot(contains('__')));
    });

    test('strips italic markers', () async {
      const input = 'This is *italic* text.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('italic'));
    });

    test('converts links to plain text', () async {
      const input = 'Visit [Google](https://google.com) for more.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('Google'));
      expect(allText, isNot(contains('https://')));
      expect(allText, isNot(contains(']()')));
    });

    test('strips list markers', () async {
      const input = '- Item one\n- Item two\n1. Ordered item\n2. Second item';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('Item'));
      expect(allText, contains('Ordered'));
    });

    test('strips strikethrough', () async {
      const input = 'This is ~~deleted~~ text.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('deleted'));
      expect(allText, isNot(contains('~~')));
    });

    test('strips inline code', () async {
      const input = 'Use the `print()` function.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('print()'));
      expect(allText, isNot(contains('`')));
    });
  });

  group('ContentNormaliser — Markdown lines', () {
    Future<List<Sentence>> sentencesOf(String markdown) async =>
        (await ContentNormaliser.normalise(
          markdown,
          ContentType.markdown,
        )).sentences;

    test(
      'a list straight after a heading is not part of the heading',
      () async {
        for (final MapEntry(key: text, value: heading) in {
          '## Key points\n- Fast. Very fast.\n- Cheap': 'Key points',
          '### Steps\n\n1. Open the app. Tap Settings.\n2. Pick a voice.':
              'Steps',
        }.entries) {
          final sentences = await sentencesOf(text);
          expect(
            [
              for (final s in sentences)
                if (s.isHeading) s.words.join(' '),
            ],
            [heading],
            reason: text,
          );
          expect(sentences.where((s) => !s.isHeading).length, 3, reason: text);
        }
      },
    );

    test('a heading that ends in a hash keeps it', () async {
      final sentences = await sentencesOf(
        '## Learning C#\n\nBody text here.\n\n# Closed #\n\nMore.',
      );
      expect(
        [
          for (final s in sentences)
            if (s.isHeading) s.words.join(' '),
        ],
        ['Learning C#', 'Closed'],
      );
    });
  });

  group('ContentNormaliser — HTML', () {
    test('strips basic HTML tags', () async {
      const input = '<p>Hello <b>world</b></p>';
      final doc = await ContentNormaliser.normalise(input, ContentType.html);

      final allText = doc.allWords.join(' ');
      expect(allText, contains('Hello'));
      expect(allText, contains('world'));
      expect(allText, isNot(contains('<p>')));
      expect(allText, isNot(contains('<b>')));
    });

    test('decodes HTML entities', () async {
      const input = '<p>Tom &amp; Jerry &mdash; the &ldquo;classic&rdquo;</p>';
      final doc = await ContentNormaliser.normalise(input, ContentType.html);

      final allText = doc.allWords.join(' ');
      expect(allText, contains('&'));
      expect(allText, contains('—'));
    });

    test('strips inline styles', () async {
      const input =
          '<div style="color: red;"><span style="font-size: 16px;">Styled text.</span></div>';
      final doc = await ContentNormaliser.normalise(input, ContentType.html);

      final allText = doc.allWords.join(' ');
      expect(allText, contains('Styled'));
      expect(allText, isNot(contains('color:')));
      expect(allText, isNot(contains('style=')));
    });

    test('converts br tags to whitespace', () async {
      const input = '<p>Line one.<br/>Line two.</p>';
      final doc = await ContentNormaliser.normalise(input, ContentType.html);

      expect(doc.sentences, isNotEmpty);
    });

    test('strips script and style blocks', () async {
      const input = '''
<html>
<head><style>body { color: red; }</style></head>
<body>
<script>alert("hi");</script>
<p>Actual content here.</p>
</body>
</html>''';
      final doc = await ContentNormaliser.normalise(input, ContentType.html);

      final allText = doc.allWords.join(' ');
      expect(allText, contains('Actual'));
      expect(allText, isNot(contains('alert')));
      expect(allText, isNot(contains('color:')));
    });

    test('preserves paragraph boundaries', () async {
      const input = '<p>First paragraph.</p><p>Second paragraph.</p>';
      final doc = await ContentNormaliser.normalise(input, ContentType.html);

      expect(doc.sentences.length, greaterThanOrEqualTo(2));
    });

    test('decodes numeric HTML entities', () async {
      const input = '<p>Copyright &#169; 2024 &#x2014; dash</p>';
      final doc = await ContentNormaliser.normalise(input, ContentType.html);

      final allText = doc.allWords.join(' ');
      expect(allText, contains('\u00A9')); // ©
      expect(allText, contains('—')); // em dash
    });

    test('handles deeply nested tags', () async {
      const input =
          '<div><section><article><p><span><em><strong>Deep text.</strong></em></span></p></article></section></div>';
      final doc = await ContentNormaliser.normalise(input, ContentType.html);

      final allText = doc.allWords.join(' ');
      expect(allText, contains('Deep'));
    });
  });

  group('ContentNormaliser — web page reading view', () {
    const page = '''
<html><head><title>Lighthouse - Wikipedia</title>
<meta property="og:title" content="Lighthouse">
<script>var x = 1;</script></head>
<body>
<header><a href="/">Home</a> <a>Random</a> <a>Log in</a></header>
<nav><ul><li>Create account</li><li>Settings</li></ul></nav>
<main id="content">
  <h1 class="title">Lighthouse</h1>
  <table class="infobox"><tr><td>Type</td><td>Tower</td></tr></table>
  <p class="lead">A lighthouse is a tower<sup class="reference">[1]</sup> designed
  to emit light.[2] It guides ships.</p>
  <h2>History <span>[edit]</span></h2>
  <p>The Pharos of Alexandria was among the first.</p>
  <figure><img src="a.png"><figcaption>A tower</figcaption></figure>
</main>
<aside>Donate now</aside>
<footer>Privacy policy · Disclaimers</footer>
</body></html>''';

    test('keeps the article and drops page chrome', () async {
      final doc = await ContentNormaliser.normalise(page, ContentType.html);
      final text = doc.allWords.join(' ');
      expect(
        text,
        'Lighthouse A lighthouse is a tower designed to emit light. '
        'It guides ships. History The Pharos of Alexandria was among the '
        'first.',
      );
    });

    test('headings and paragraphs start paragraphs', () async {
      final doc = await ContentNormaliser.normalise(page, ContentType.html);
      final starts = [
        for (final s in doc.sentences)
          if (s.startsParagraph) s.words.join(' '),
      ];
      expect(starts, [
        'Lighthouse',
        'A lighthouse is a tower designed to emit light.',
        'History',
        'The Pharos of Alexandria was among the first.',
      ]);
    });

    test('article headings keep their level', () async {
      final doc = await ContentNormaliser.normalise(page, ContentType.html);
      final headings = [
        for (final s in doc.sentences)
          if (s.isHeading) '${s.heading}:${s.words.join(' ')}',
      ];
      expect(headings, ['1:Lighthouse', '2:History']);
    });

    test('drops nested link-list navigation, keeps prose lists', () async {
      const html = '''
<main><p>Intro text here.</p>
<div id="toc"><h2>Contents</h2><ul>
  <li><a href="#a">1 History</a><ul><li><a href="#b">1.1 Ancient</a></li></ul></li>
  <li><a href="#c">2 Design</a></li>
</ul></div>
<ul><li>Pack a warm coat for the crossing.</li><li>Bring a lamp.</li></ul>
</main>''';
      final doc = await ContentNormaliser.normalise(html, ContentType.html);
      final text = doc.allWords.join(' ');
      expect(text, isNot(contains('1.1')));
      expect(text, isNot(contains('2 Design')));
      expect(text, contains('Pack a warm coat for the crossing.'));
      expect(text, contains('Bring a lamp.'));
    });

    test('drops short link-only elements, keeps link-free headings', () async {
      const html = '''
<main><div class="tabs"><a href="/a">Article</a></div><div><a href="/t">Talk</a></div>
<h2>History<span class="editsection"><a href="/e">edit</a></span></h2>
<p>See <a href="/p">Pharos</a> for more.</p></main>''';
      final doc = await ContentNormaliser.normalise(html, ContentType.html);
      expect(doc.allWords.join(' '), 'History See Pharos for more.');
    });

    test('drops wiki edit links, Contents heading and hatnotes', () async {
      const html = '''
<main><h2 id="toc">Contents</h2>
<h2>History<span class="editsection"><a href="/e"><span>edit</span></a></span></h2>
<div class="hatnote">Main article: <a href="/h">History of lighthouses</a></div>
<p>Before ports existed, fires guided ships.</p></main>''';
      final doc = await ContentNormaliser.normalise(html, ContentType.html);
      expect(
        doc.allWords.join(' '),
        'History Before ports existed, fires guided ships.',
      );
    });

    test('inline markup leaves no space before punctuation', () async {
      const html =
          '<p>Hazardous <a href="/s">shoals</a>, <a href="/r">reefs</a>; '
          'see <a href="/d">Lighthouse (disambiguation)</a>.</p>';
      final doc = await ContentNormaliser.normalise(html, ContentType.html);
      expect(
        doc.allWords.join(' '),
        'Hazardous shoals, reefs; see Lighthouse (disambiguation).',
      );
    });

    test('prefers og:title, falls back to <title>', () {
      expect(ContentNormaliser.htmlTitle(page), 'Lighthouse');
      expect(ContentNormaliser.htmlTitle('<title>A &amp; B</title>'), 'A & B');
      expect(ContentNormaliser.htmlTitle('<p>none</p>'), isNull);
    });

    test('a title keeps the other kind of quote it contains', () {
      // The value used to end at the first quote of either kind: "Don".
      expect(
        ContentNormaliser.htmlTitle(
          '<meta property="og:title" content="Don\'t Panic">',
        ),
        "Don't Panic",
      );
      expect(
        ContentNormaliser.htmlTitle(
          "<meta property='og:title' content='The \"Tall\" One'>"
          '<title>Fallback</title>',
        ),
        'The "Tall" One',
      );
    });

    Future<String> textOf(String html) async =>
        (await ContentNormaliser.normalise(
          html,
          ContentType.html,
        )).allWords.join(' ');

    test('superscripts that are text stay; note markers go', () async {
      // Every <sup> used to be removed with its text: "the 21 century".
      expect(
        await textOf(
          '<p>In the 21<sup>st</sup> century, M<sup>lle</sup> Dupont '
          'counted 10<sup>6</sup> cells in 3 km<sup>2</sup>.</p>',
        ),
        'In the 21st century, Mlle Dupont counted 10^6 cells in 3 km2.',
      );
      expect(
        await textOf(
          '<p>Ships came<sup><a href="#fn1">1</a></sup> and '
          'went<sup class="footnote-ref">a</sup> at night'
          '<sup>[<a href="#c">citation needed</a>]</sup>.</p>',
        ),
        'Ships came and went at night.',
      );
    });

    test('an article goes on after something embedded in it', () async {
      // An embedded card or comment is an <article> too. The post used to
      // end at the first closing tag: everything after the card was lost.
      final text = await textOf(
        '<article><h1>The crossing</h1><p>The first part of the post.</p>'
        '<article class="card"><p>An embedded card.</p></article>'
        '<p>The second part, after the card.</p></article>'
        '<article><p>A short comment.</p></article>',
      );
      expect(text, contains('The first part of the post.'));
      expect(text, contains('The second part, after the card.'));
      expect(text, isNot(contains('A short comment.')));
    });

    test('a page wrapped in a form or a layout table keeps its text', () async {
      // Every ASP.NET WebForms page is one <form> around the body, and old
      // sites lay the page out in a table. Both came out empty.
      const body =
          '<h1>Council news</h1><p>The council met on Tuesday evening. It '
          'voted to repair the old bridge before winter.</p>';
      expect(
        await textOf(
          '<html><body><form method="post" id="form1"><div>$body'
          '<input type="submit" value="Go"></div></form></body></html>',
        ),
        'Council news The council met on Tuesday evening. It voted to '
        'repair the old bridge before winter.',
      );
      expect(
        await textOf(
          '<html><body><table><tr><td>$body</td></tr></table></body></html>',
        ),
        contains('It voted to repair the old bridge before winter.'),
      );
    });

    test(
      'a form or table that is a small part of the page still goes',
      () async {
        final text = await textOf(
          '<main><p>The council met on Tuesday evening. It voted to repair '
          'the old bridge before winter.</p>'
          '<form><label>Your email</label><button>Subscribe</button></form>'
          '<table><tr><td>Votes</td><td>7</td></tr></table></main>',
        );
        expect(
          text,
          'The council met on Tuesday evening. It voted to repair the old '
          'bridge before winter.',
        );
      },
    );
  });

  group('ContentNormaliser — output contract', () {
    test('output is ExtractedDocument with sentences', () async {
      final doc = await ContentNormaliser.normalise(
        'A sentence. Another one.',
        ContentType.plainText,
      );

      expect(doc, isA<ExtractedDocument>());
      expect(doc.sentences, isNotEmpty);
    });

    test('output has page boundaries', () async {
      final doc = await ContentNormaliser.normalise(
        'Some text with words.',
        ContentType.plainText,
      );

      expect(doc.pageBoundaries, isNotEmpty);
      expect(doc.pageBoundaries.first.pageNumber, 0);
    });

    test('allWords returns flat word list', () async {
      final doc = await ContentNormaliser.normalise(
        'Hello world. Foo bar.',
        ContentType.plainText,
      );

      expect(doc.allWords, isNotEmpty);
      expect(doc.allWords.first, 'Hello');
    });
  });

  group('ContentNormaliser — large input', () {
    test('processes large input without error', () async {
      // Generate >10KB of text to trigger isolate path.
      final largeInput = List.generate(
        2000,
        (i) => 'Word$i is here.',
      ).join(' ');
      expect(largeInput.length, greaterThan(10 * 1024));

      final doc = await ContentNormaliser.normalise(
        largeInput,
        ContentType.plainText,
      );

      expect(doc.sentences, isNotEmpty);
      expect(doc.totalWords, greaterThan(0));
    });
  });

  group('ContentNormaliser — LLM markdown patterns', () {
    test('strips fenced code block with language tag', () async {
      const input =
          'Here is a solution:\n\n```python\ndef calculate():\n    return 42\n```\n\nUse it wisely.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('solution'));
      expect(allText, contains('wisely'));
      expect(allText, isNot(contains('```')));
      expect(allText, isNot(contains('def')));
      expect(allText, isNot(contains('calculate')));
      expect(allText, isNot(contains('return')));
      expect(allText, isNot(contains('python')));
    });

    test('strips fenced code block without language tag', () async {
      const input =
          'Before code.\n\n```\nsome raw code\nmore code\n```\n\nAfter code.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('Before'));
      expect(allText, contains('After'));
      expect(allText, isNot(contains('```')));
      expect(allText, isNot(contains('raw')));
    });

    test('strips multi-line fenced code block', () async {
      final codeLines = List.generate(15, (i) => '    line_$i = $i;');
      final input =
          'Intro text.\n\n```javascript\n${codeLines.join('\n')}\n```\n\nConclusion here.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('Intro'));
      expect(allText, contains('Conclusion'));
      expect(allText, isNot(contains('line_')));
      expect(allText, isNot(contains('javascript')));
    });

    test('strips markdown table', () async {
      const input = '''Summary of results:

| Model | Accuracy | Speed |
|-------|----------|-------|
| GPT-4 | 92% | Fast |
| Claude | 95% | Medium |
| Gemini | 90% | Fast |

The best model is Claude.''';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('Summary'));
      expect(allText, contains('Claude')); // in prose sentence, not table
      expect(allText, isNot(contains('|')));
      expect(allText, isNot(contains('---')));
      expect(allText, isNot(contains('92%')));
    });

    test('strips indented code block after blank line', () async {
      const input =
          'See this example:\n\n    const x = 42;\n    console.log(x);\n\nThat prints 42.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('example'));
      expect(allText, contains('prints'));
      expect(allText, isNot(contains('const')));
      expect(allText, isNot(contains('console')));
    });

    test('removes escape backslashes', () async {
      const input = r'This is \*not italic\* and \[not a link\].';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('*not'));
      expect(allText, isNot(contains(r'\*')));
      expect(allText, isNot(contains(r'\[')));
    });

    test('strips footnote markers and definitions', () async {
      const input =
          'RSVP improves comprehension[^1] significantly.\n\n[^1]: According to Smith et al., 2023.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('comprehension'));
      expect(allText, isNot(contains('[^1]')));
      expect(allText, isNot(contains('Smith')));
    });

    test('real-world ChatGPT response produces clean tokens', () async {
      const input = '''# How to Sort a List in Python

There are several ways to sort a list:

## Using sorted()

The `sorted()` function returns a new sorted list:

```python
numbers = [3, 1, 4, 1, 5, 9]
result = sorted(numbers)
print(result)  # [1, 1, 3, 4, 5, 9]
```

## Using .sort()

The `.sort()` method sorts **in place**:

```python
numbers = [3, 1, 4, 1, 5, 9]
numbers.sort()
```

## Performance Comparison

| Method | Time Complexity | In-Place |
|--------|----------------|----------|
| sorted() | O(n log n) | No |
| .sort() | O(n log n) | Yes |

Both methods use **Timsort** under the hood[^1].

[^1]: Timsort was invented by Tim Peters in 2002.''';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      // Prose survives
      expect(allText, contains('Sort'));
      expect(allText, contains('several'));
      expect(allText, contains('sorted()')); // inline code becomes text
      expect(allText, contains('Timsort'));
      // Code and tables removed
      expect(allText, isNot(contains('```')));
      expect(allText, isNot(contains('numbers')));
      expect(allText, isNot(contains('print(')));
      expect(allText, isNot(contains('|')));
      expect(allText, isNot(contains('O(n')));
      expect(allText, isNot(contains('[^1]')));
    });

    test('real-world Claude response with mixed formatting', () async {
      const input =
          "Here's what you need to know about **async/await** in Dart:\n\n"
          '1. Mark functions with `async`\n'
          '2. Use `await` before futures\n'
          '3. Handle errors with `try`/`catch`\n\n'
          '```dart\n'
          'Future<String> fetchData() async {\n'
          '  try {\n'
          "    final response = await http.get(Uri.parse('https://api.example.com'));\n"
          '    return response.body;\n'
          '  } catch (e) {\n'
          "    return 'Error: \$e';\n"
          '  }\n'
          '}\n'
          '```\n\n'
          '> **Note**: Always handle errors in production code.\n\n'
          'The key takeaway is that ~~callbacks are obsolete~~ async/await is cleaner.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      // Prose and inline formatting cleaned
      expect(allText, contains('async/await'));
      expect(allText, contains('Dart'));
      expect(allText, contains('takeaway'));
      expect(allText, contains('cleaner'));
      // Code block removed
      expect(allText, isNot(contains('fetchData')));
      expect(allText, isNot(contains('http.get')));
      expect(allText, isNot(contains('```')));
      // Formatting markers stripped
      expect(allText, isNot(contains('**')));
      expect(allText, isNot(contains('~~')));
    });

    test('existing markdown tests still pass — headings', () async {
      const input = '# Heading One\n\n## Heading Two\n\nBody text here.';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('Heading'));
      expect(allText, isNot(contains('#')));
    });

    test('existing markdown tests still pass — bold and links', () async {
      const input = 'This is **bold** and visit [Google](https://google.com).';
      final doc = await ContentNormaliser.normalise(
        input,
        ContentType.markdown,
      );

      final allText = doc.allWords.join(' ');
      expect(allText, contains('bold'));
      expect(allText, contains('Google'));
      expect(allText, isNot(contains('**')));
      expect(allText, isNot(contains('https://')));
    });
  });
}
