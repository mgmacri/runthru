import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/book_structure.dart';
import 'package:runthru/features/reading/widgets/book_mode_view.dart';

/// Two chapters with real headings, a sub-heading, and a short line that
/// only looks like a heading ("Author: A. Tester").
///
/// * 0..1    "Chapter One" (heading)
/// * 2..4    "Author: A. Tester" (a short unpunctuated paragraph, not a heading)
/// * 5..     ten paragraphs of 30 words
/// * [_sub]  "A Smaller Heading" (heading, inside chapter one)
/// * then two more paragraphs
/// * [_two]  "Chapter Two The Storm" (heading), then 40 words.
final List<String> _words = [
  'Chapter',
  'One',
  'Author:',
  'A.',
  'Tester',
  for (var p = 0; p < 10; p++)
    for (var w = 0; w < 30; w++) w == 29 ? 'p${p}w$w.' : 'p${p}w$w',
  'A',
  'Smaller',
  'Heading',
  for (var p = 10; p < 12; p++)
    for (var w = 0; w < 30; w++) w == 29 ? 'p${p}w$w.' : 'p${p}w$w',
  'Chapter',
  'Two',
  'The',
  'Storm',
  for (var w = 0; w < 40; w++) w == 39 ? 'c2w$w.' : 'c2w$w',
];
const int _sub = 5 + 10 * 30;
const int _two = _sub + 3 + 2 * 30;
final Set<int> _paragraphs = {
  0,
  2,
  for (var p = 0; p < 10; p++) 5 + p * 30,
  _sub,
  for (var p = 0; p < 2; p++) _sub + 3 + p * 30,
  _two,
  _two + 4,
};
const Set<int> _headings = {0, _sub, _two};

final BookStructure _structure = BookStructure(
  totalWords: _words.length,
  sections: [
    const BookSection(
      index: 0,
      kind: SectionKind.body,
      role: SectionRole.chapter,
      start: 0,
      end: _two,
      label: 'Chapter One',
      headingWords: 2,
    ),
    BookSection(
      index: 1,
      kind: SectionKind.body,
      role: SectionRole.chapter,
      start: _two,
      end: _words.length,
      label: 'Chapter Two',
      title: 'The Storm',
      headingWords: 4,
    ),
  ],
  subHeadings: const [
    SubHeading(start: _sub, wordCount: 3, text: 'A Smaller Heading'),
  ],
);

class _Harness extends StatefulWidget {
  const _Harness({super.key, this.start = 0, this.onEnd, this.reduced = true});

  final int start;
  final VoidCallback? onEnd;
  final bool reduced;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late int start = widget.start;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          disableAnimations: widget.reduced,
        ),
        child: Scaffold(
          body: BookModeView(
            words: _words,
            startIndex: start,
            onTurn: (i) => setState(() => start = i),
            onEnd: widget.onEnd,
            fontFamily: 'Roboto',
            fontSize: 20,
            letterSpacing: 0,
            wordSpacing: 0,
            wpm: 250,
            onFontSizeChanged: (_) {},
            paragraphStarts: _paragraphs,
            headingStarts: _headings,
            structure: _structure,
          ),
        ),
      ),
    );
  }
}

/// Texts on the page, in order (opener lines included).
List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(BookModeView.pageKey),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data ?? '')
    .toList();

Future<void> _setUp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(BookModeView.nextKey));
  await tester.pump();
}

void main() {
  testWidgets('a chapter opens with its designed heading, not a bold line', (
    tester,
  ) async {
    await _setUp(tester);
    await tester.pumpWidget(const _Harness());

    final texts = _texts(tester);
    // "Chapter One" has no other title: it is the headline, shown once.
    expect(texts.first, 'Chapter One');
    expect(texts.where((t) => t.contains('Chapter One')), hasLength(1));
    // The heading words are not also laid out as body text.
    expect(texts[1], startsWith('Author: A. Tester'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('label, title and reading text of a titled chapter', (
    tester,
  ) async {
    await _setUp(tester);
    await tester.pumpWidget(const _Harness(start: _two));

    final texts = _texts(tester);
    expect(texts[0], 'CHAPTER TWO');
    expect(texts[1], 'The Storm');
    expect(texts[2], startsWith('c2w0 c2w1'));
    // Announced as one heading to assistive technology.
    expect(
      find.bySemanticsLabel(RegExp(r'Chapter Two\. The Storm')),
      findsOneWidget,
    );
  });

  testWidgets('every text word appears exactly once across the pages', (
    tester,
  ) async {
    await _setUp(tester);
    var ended = 0;
    await tester.pumpWidget(_Harness(onEnd: () => ended++));

    final seen = <String>[];
    var pages = 0;
    for (var guard = 0; guard < 60; guard++) {
      pages++;
      final texts = _texts(tester);
      // Opener lines are headings, not text words.
      final body = texts.where(
        (t) => t != 'Chapter One' && t != 'CHAPTER TWO' && t != 'The Storm',
      );
      seen.addAll(body.expand((t) => t.split(' ')));
      final next = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byKey(BookModeView.nextKey),
              matching: find.byType(Semantics),
            )
            .first,
      );
      // The last page: the button now offers to finish (B-73) where it
      // used to be switched off.
      if (next.properties.label == 'Finish') break;
      await _next(tester);
    }
    final expected = [
      for (var i = 0; i < _words.length; i++)
        // The two chapters' heading words are shown by the openers.
        if (!(i < 2) && !(i >= _two && i < _two + 4)) _words[i],
    ];
    expect(seen, expected);
    expect(pages, greaterThan(2));
    expect(ended, 0);
  });

  testWidgets('chapter two starts on a fresh page', (tester) async {
    await _setUp(tester);
    await tester.pumpWidget(const _Harness());
    for (var guard = 0; guard < 60; guard++) {
      final texts = _texts(tester);
      if (texts.contains('CHAPTER TWO')) {
        // The opener is the first thing on its page.
        expect(texts.first, 'CHAPTER TWO');
        return;
      }
      // No page mixes the end of chapter one with chapter two's text.
      expect(texts.join(' '), isNot(contains('c2w0')));
      await _next(tester);
    }
    fail('chapter two never appeared');
  });

  testWidgets('only recorded headings are styled as headings', (tester) async {
    await _setUp(tester);
    await tester.pumpWidget(const _Harness());
    // "Author: A. Tester" is short and unpunctuated, but not a heading.
    final author = tester.widget<Text>(
      find.textContaining('Author: A. Tester'),
    );
    expect(author.style!.fontWeight, FontWeight.w400);

    // The real sub-heading inside the chapter is.
    for (var guard = 0; guard < 60; guard++) {
      final found = find.text('A Smaller Heading');
      if (found.evaluate().isNotEmpty) {
        expect(tester.widget<Text>(found).style!.fontWeight, FontWeight.w700);
        return;
      }
      await _next(tester);
    }
    fail('sub-heading never appeared');
  });

  testWidgets('turning past the last page reports the end', (tester) async {
    await _setUp(tester);
    var ended = 0;
    await tester.pumpWidget(_Harness(start: _two, onEnd: () => ended++));
    // The last chapter fits one page here. A tap on the page's forward
    // zone asks for more, as the footer's "Finish" does.
    final state = tester.state<BookModeViewState>(find.byType(BookModeView));
    for (var guard = 0; guard < 10 && ended == 0; guard++) {
      state.nextPage();
      await tester.pump();
    }
    expect(ended, 1);
  });

  testWidgets('going back from a chapter opener returns to the page before', (
    tester,
  ) async {
    await _setUp(tester);
    await tester.pumpWidget(const _Harness(start: _two));
    await tester.tap(find.byKey(BookModeView.previousKey));
    await tester.pump();
    final texts = _texts(tester).join(' ');
    expect(texts, isNot(contains('CHAPTER TWO')));
    expect(texts, contains('p11w29.'));
    // And forward again lands on the opener.
    await _next(tester);
    expect(_texts(tester).first, 'CHAPTER TWO');
  });

  testWidgets('the opener animates in, and not with reduced motion', (
    tester,
  ) async {
    await _setUp(tester);
    await tester.pumpWidget(const _Harness(start: _two, reduced: false));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const _Harness(key: ValueKey('r'), start: _two));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
