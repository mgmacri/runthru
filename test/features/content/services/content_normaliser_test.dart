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
