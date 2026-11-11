import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/book_structure.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/widgets/contents_sheet.dart';

/// Front matter (0..100), [chapters] chapters of 300 words, an index.
BookStructure _book({int chapters = 4}) {
  final sections = <BookSection>[
    const BookSection(
      index: 0,
      kind: SectionKind.front,
      role: SectionRole.foreword,
      start: 0,
      end: 100,
      title: 'Foreword',
      headingWords: 1,
    ),
  ];
  var at = 100;
  for (var i = 1; i <= chapters; i++) {
    sections.add(
      BookSection(
        index: sections.length,
        kind: SectionKind.body,
        role: SectionRole.chapter,
        start: at,
        end: at + 300,
        label: 'Chapter $i',
        title: 'Title $i',
        headingWords: 4,
      ),
    );
    at += 300;
  }
  sections.add(
    BookSection(
      index: sections.length,
      kind: SectionKind.back,
      role: SectionRole.bookIndex,
      start: at,
      end: at + 50,
      title: 'Index',
      headingWords: 1,
    ),
  );
  return BookStructure(sections: sections, totalWords: at + 50);
}

Future<BookSection?> Function() _open(
  WidgetTester tester,
  BookStructure structure, {
  required int currentWord,
}) {
  BookSection? picked;
  var returned = false;
  return () async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await showContentsSheet(
                    context,
                    structure: structure,
                    currentWord: currentWord,
                    wpm: 300,
                    bookTitle: 'A Book',
                  );
                  returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(returned, isFalse);
    return picked;
  };
}

void main() {
  testWidgets('lists chapters with reading time and where the reader is', (
    tester,
  ) async {
    // In chapter 2 (400..700), a third of the way through.
    await _open(tester, _book(), currentWord: 500)();

    expect(find.text('Contents'), findsOneWidget);
    expect(find.text('1 of 4 chapters read'), findsOneWidget);
    expect(find.text('CHAPTER 1'), findsOneWidget);
    expect(find.text('Title 1'), findsOneWidget);
    expect(find.text('Title 4'), findsOneWidget);
    // 300 words at 300 wpm.
    expect(find.text('< 1 min'), findsWidgets);
    // Chapter 1 is ticked; front and back matter are folded away.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('Foreword'), findsNothing);
    expect(find.text('Index'), findsNothing);
    expect(find.text('BEFORE THE BOOK'), findsOneWidget);
    expect(find.text('AFTER THE BOOK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a chapter returns it', (tester) async {
    BookSection? picked;
    var done = false;
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showContentsSheet(
                  context,
                  structure: _book(),
                  currentWord: 150,
                  wpm: 300,
                  bookTitle: 'A Book',
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title 3'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(picked!.label, 'Chapter 3');
    expect(find.text('Contents'), findsNothing);
  });

  testWidgets('closing returns nothing', (tester) async {
    BookSection? picked;
    var done = false;
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showContentsSheet(
                  context,
                  structure: _book(),
                  currentWord: 150,
                  wpm: 300,
                  bookTitle: 'A Book',
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Close contents'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(picked, isNull);
  });

  testWidgets('front and back matter unfold on request, unticked', (
    tester,
  ) async {
    await _open(tester, _book(), currentWord: 500)();
    await tester.tap(find.text('BEFORE THE BOOK'));
    await tester.pumpAndSettle();
    expect(find.text('Foreword'), findsOneWidget);
    // Passed, but not marked as read: still only chapter 1 is ticked.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AFTER THE BOOK'));
    await tester.pumpAndSettle();
    expect(find.text('Index'), findsOneWidget);
  });

  testWidgets('opens on the part of the book the reader is in', (tester) async {
    // In the foreword: its group starts unfolded.
    await _open(tester, _book(), currentWord: 20)();
    expect(find.text('Foreword'), findsOneWidget);
    expect(find.text('0 of 4 chapters read'), findsOneWidget);
  });

  testWidgets('a long book scrolls to the current chapter', (tester) async {
    final book = _book(chapters: 60);
    // In chapter 40.
    final at = book.chapters[39].start + 10;
    await _open(tester, book, currentWord: at)();
    expect(find.text('Title 40'), findsOneWidget);
    expect(find.text('Title 1'), findsNothing);
    expect(find.text('39 of 60 chapters read'), findsOneWidget);
  });

  testWidgets('rows are labelled buttons at least 48dp tall', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester, _book(), currentWord: 500)();

    expect(
      find.bySemanticsLabel('Chapter 1: Title 1, < 1 min, read'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Chapter 2: Title 2, < 1 min, reading now'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Chapter 3: Title 3, < 1 min'),
      findsOneWidget,
    );
    for (final index in [1, 2, 3]) {
      final row = find.byKey(ValueKey('contents-row-$index'));
      expect(
        tester.getSize(row).height,
        greaterThanOrEqualTo(RunThruA11y.minTapTarget),
      );
    }
    expect(
      tester.getSize(find.bySemanticsLabel('Close contents')).height,
      greaterThanOrEqualTo(RunThruA11y.minTapTarget),
    );
    handle.dispose();
  });

  testWidgets('text before the first heading is called the beginning', (
    tester,
  ) async {
    // A paper: title block and abstract, then numbered sections.
    final structure = BookStructure(
      totalWords: 900,
      sections: const [
        BookSection(
          index: 0,
          kind: SectionKind.body,
          role: SectionRole.other,
          start: 0,
          end: 300,
        ),
        BookSection(
          index: 1,
          kind: SectionKind.body,
          role: SectionRole.chapter,
          start: 300,
          end: 600,
          title: 'Introduction',
          headingWords: 2,
        ),
        BookSection(
          index: 2,
          kind: SectionKind.body,
          role: SectionRole.chapter,
          start: 600,
          end: 900,
          title: 'Background',
          headingWords: 2,
        ),
      ],
    );
    await _open(tester, structure, currentWord: 10)();
    expect(find.text('Beginning'), findsOneWidget);
    expect(find.text('Untitled section'), findsNothing);
    expect(find.text('Introduction'), findsOneWidget);
  });

  testWidgets('a document with one untitled body still opens cleanly', (
    tester,
  ) async {
    final structure = BookStructure(
      totalWords: 500,
      sections: const [
        BookSection(
          index: 0,
          kind: SectionKind.front,
          role: SectionRole.other,
          start: 0,
          end: 100,
        ),
        BookSection(
          index: 1,
          kind: SectionKind.body,
          role: SectionRole.other,
          start: 100,
          end: 500,
        ),
      ],
    );
    await _open(tester, structure, currentWord: 200)();
    // No chapter count to give: the book's name stands in.
    expect(find.text('A Book'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
