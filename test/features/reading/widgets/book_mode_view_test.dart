import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/time_left.dart';
import 'package:runthru/features/reading/widgets/book_mode_view.dart';

/// A small book: a heading, then numbered prose paragraphs so every word is
/// unique and checkable. The second chapter starts at [chapterTwo].
final List<String> _words = [
  'Chapter',
  'One',
  for (var p = 0; p < 12; p++)
    for (var w = 0; w < 30; w++) w == 29 ? 'p${p}w$w.' : 'p${p}w$w',
  'Chapter',
  'Two',
  for (var w = 0; w < 40; w++) w == 39 ? 'c2w$w.' : 'c2w$w',
];
const int _chapterTwo = 2 + 12 * 30;
final Set<int> _paragraphs = {
  0,
  2,
  for (var p = 1; p < 12; p++) 2 + p * 30,
  _chapterTwo,
  _chapterTwo + 2,
};

class _Harness extends StatefulWidget {
  const _Harness({this.onTurnLog, this.onEnd, this.wpm = 250});

  final List<int>? onTurnLog;
  final VoidCallback? onEnd;
  final int wpm;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int start = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          disableAnimations: true,
        ),
        child: Scaffold(
          body: BookModeView(
            words: _words,
            startIndex: start,
            onTurn: (i) {
              widget.onTurnLog?.add(i);
              setState(() => start = i);
            },
            onEnd: widget.onEnd,
            fontFamily: 'Roboto',
            fontSize: 20,
            letterSpacing: 0,
            wordSpacing: 0,
            wpm: widget.wpm,
            onFontSizeChanged: (_) {},
            paragraphStarts: _paragraphs,
            chapterStarts: const {_chapterTwo},
          ),
        ),
      ),
    );
  }
}

String _pageText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(BookModeView.pageKey),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data ?? '')
    .join(' ');

void main() {
  testWidgets('paging forward shows every word exactly once, in order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const _Harness());
    final seen = <String>[];
    for (var guard = 0; guard < 200; guard++) {
      seen.addAll(_pageText(tester).split(' '));
      final next = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byKey(BookModeView.nextKey),
              matching: find.byType(Semantics),
            )
            .first,
      );
      if (next.properties.enabled == false) break;
      await tester.tap(find.byKey(BookModeView.nextKey));
      await tester.pump();
    }
    expect(seen, _words);
  });

  testWidgets('previous returns to the page it came from', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final turns = <int>[];
    await tester.pumpWidget(_Harness(onTurnLog: turns));
    final first = _pageText(tester);
    await tester.tap(find.byKey(BookModeView.nextKey));
    await tester.pump();
    final second = _pageText(tester);
    expect(second, isNot(first));

    await tester.tap(find.byKey(BookModeView.previousKey));
    await tester.pump();
    expect(_pageText(tester), first);
    expect(turns.last, 0);
  });

  testWidgets('a chapter starts on a fresh page', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const _Harness());
    for (var guard = 0; guard < 200; guard++) {
      final text = _pageText(tester);
      if (text.contains('Chapter Two')) {
        expect(text.startsWith('Chapter Two'), isTrue, reason: text);
        return;
      }
      await tester.tap(find.byKey(BookModeView.nextKey));
      await tester.pump();
    }
    fail('never reached chapter two');
  });

  testWidgets('short unpunctuated paragraphs are marked as headings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(const _Harness());
    final heading = tester.getSemantics(find.text('Chapter One'));
    expect(heading.getSemanticsData().flagsCollection.isHeader, isTrue);
    handle.dispose();
  });

  testWidgets('footer buttons meet the 48dp tap target', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const _Harness());
    for (final key in [BookModeView.nextKey, BookModeView.previousKey]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('the time left is worked out at the reader\'s speed, however '
      'slow', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 30 words a minute is the slowest the speed setting goes. The footer
    // used to reckon with 60 at least, and showed half the time.
    await tester.pumpWidget(const _Harness(wpm: 30));
    final shown = _pageText(tester).split(' ').length;
    final minutes = ((_words.length - shown) / 30).ceil();

    expect(
      find.textContaining(formatTimeLeft(minutes)),
      findsOneWidget,
      reason: '${_words.length - shown} words left at 30 a minute',
    );
  });

  testWidgets('on the last page the footer button finishes the book', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();

    var finished = 0;
    await tester.pumpWidget(_Harness(onEnd: () => finished++));
    for (var guard = 0; guard < 200; guard++) {
      if (find.bySemanticsLabel('Finish').evaluate().isNotEmpty) break;
      await tester.tap(find.byKey(BookModeView.nextKey));
      await tester.pump();
    }
    expect(_pageText(tester), endsWith('c2w39.'));
    expect(finished, 0);

    // The button used to be switched off here. The page's tap zones finish
    // the book too, but assistive technology cannot see them, so a
    // screen-reader user had no way to the end.
    expect(
      tester.getSemantics(find.byKey(BookModeView.nextKey)),
      matchesSemantics(
        label: 'Finish',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byKey(BookModeView.nextKey));
    expect(finished, 1);
    handle.dispose();
  });

  testWidgets('a screen reader can press the footer buttons', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();

    final turns = <int>[];
    await tester.pumpWidget(_Harness(onTurnLog: turns));
    final first = _pageText(tester);

    // The action a screen reader sends, as opposed to a touch on the glass.
    final next = tester.getSemantics(find.byKey(BookModeView.nextKey));
    next.owner!.performAction(next.id, SemanticsAction.tap);
    await tester.pump();

    expect(turns, hasLength(1));
    expect(_pageText(tester), isNot(first));

    final previous = tester.getSemantics(find.byKey(BookModeView.previousKey));
    previous.owner!.performAction(previous.id, SemanticsAction.tap);
    await tester.pump();

    expect(_pageText(tester), first);
    handle.dispose();
  });

  testWidgets('a document with no paragraph data still pages quickly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final wall = [for (var i = 0; i < 20000; i++) 'w$i'];
    var start = 0;
    late StateSetter set;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                set = setState;
                return BookModeView(
                  words: wall,
                  startIndex: start,
                  onTurn: (i) => set(() => start = i),
                  fontFamily: 'Roboto',
                  fontSize: 20,
                  letterSpacing: 0,
                  wordSpacing: 0,
                  wpm: 250,
                  onFontSizeChanged: (_) {},
                );
              },
            ),
          ),
        ),
      ),
    );
    final seen = <String>[];
    final watch = Stopwatch()..start();
    for (var page = 0; page < 5; page++) {
      seen.addAll(_pageText(tester).split(' '));
      await tester.tap(find.byKey(BookModeView.nextKey));
      await tester.pump();
    }
    watch.stop();
    expect(seen, wall.sublist(0, seen.length));
    expect(watch.elapsedMilliseconds, lessThan(5000));
    // Going back from deep in the wall lands on the previous page.
    final before = _pageText(tester);
    await tester.tap(find.byKey(BookModeView.previousKey));
    await tester.pump();
    await tester.tap(find.byKey(BookModeView.nextKey));
    await tester.pump();
    expect(_pageText(tester), before);
  });

  testWidgets('a spine boundary without a heading does not break the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final words = [
      for (var i = 0; i < 40; i++) 'a$i',
      for (var i = 0; i < 40; i++) 'b$i',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: BookModeView(
              words: words,
              startIndex: 0,
              onTurn: (_) {},
              fontFamily: 'Roboto',
              fontSize: 16,
              letterSpacing: 0,
              wordSpacing: 0,
              wpm: 250,
              onFontSizeChanged: (_) {},
              // A scanned print page boundary mid-sentence at word 40.
              chapterStarts: const {40},
            ),
          ),
        ),
      ),
    );
    expect(_pageText(tester), contains('b39'));
  });

  testWidgets('an empty document renders nothing and does not throw', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookModeView(
            words: const [],
            startIndex: 0,
            onTurn: (_) {},
            fontFamily: 'Roboto',
            fontSize: 20,
            letterSpacing: 0,
            wordSpacing: 0,
            wpm: 250,
            onFontSizeChanged: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(BookModeView.pageKey), findsNothing);
  });
}
