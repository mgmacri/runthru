import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/widgets/paged_tile_well.dart';
import 'package:runthru/widgets/runthru_shell_widgets.dart';

/// A scrolling page with a well of [count] book rows, as the Library has.
Widget _harness({
  required int count,
  bool reduced = false,
  double textScale = 1,
  String Function(int index)? titleOf,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(400, 900),
        disableAnimations: reduced,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: PagedTileWell(
              label: 'Books',
              itemCount: count,
              itemBuilder: (context, index) => RunThruShellRow(
                key: ValueKey('tile-$index'),
                title: titleOf?.call(index) ?? 'Book $index',
                metadata: 'Local file',
                icon: Icons.menu_book_rounded,
                divider: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

PagedTileWellState _state(WidgetTester tester) =>
    tester.state<PagedTileWellState>(find.byType(PagedTileWell));

double _wellHeight(WidgetTester tester) =>
    tester.getSize(find.byType(PagedTileWell)).height;

Future<void> _setUp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('shows four tiles a page and says which page it is on', (
    tester,
  ) async {
    await _setUp(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_harness(count: 10));

    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('tile-$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('tile-4')), findsNothing);
    expect(_state(tester).pageCount, 3);

    final indicator = tester.getSemantics(
      find.byKey(PagedTileWell.indicatorKey),
    );
    expect(indicator.label, 'Books pages');
    expect(indicator.value, 'Page 1 of 3');
    expect(
      indicator.getSemanticsData().hasAction(SemanticsAction.increase),
      isTrue,
    );
    expect(
      indicator.getSemanticsData().hasAction(SemanticsAction.decrease),
      isFalse,
    );
    handle.dispose();
  });

  testWidgets('a single page has no indicator and does not take swipes', (
    tester,
  ) async {
    await _setUp(tester);
    await tester.pumpWidget(_harness(count: 3));
    expect(find.byKey(PagedTileWell.indicatorKey), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('tile-1')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    expect(_state(tester).page, 0);
    expect(find.byKey(const ValueKey('tile-0')), findsOneWidget);
  });

  testWidgets('swiping turns the page, forward and back', (tester) async {
    await _setUp(tester);
    await tester.pumpWidget(_harness(count: 10));

    await tester.drag(
      find.byKey(const ValueKey('tile-1')),
      const Offset(-220, 0),
    );
    await tester.pumpAndSettle();
    expect(_state(tester).page, 1);
    expect(find.byKey(const ValueKey('tile-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-0')), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('tile-5')),
      const Offset(220, 0),
    );
    await tester.pumpAndSettle();
    expect(_state(tester).page, 0);
    expect(find.byKey(const ValueKey('tile-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-4')), findsNothing);
  });

  testWidgets('a short drag falls back; a quick flick turns', (tester) async {
    await _setUp(tester);
    await tester.pumpWidget(_harness(count: 10));

    await tester.drag(
      find.byKey(const ValueKey('tile-1')),
      const Offset(-50, 0),
    );
    await tester.pumpAndSettle();
    expect(_state(tester).page, 0);
    expect(find.byKey(const ValueKey('tile-4')), findsNothing);

    await tester.fling(
      find.byKey(const ValueKey('tile-1')),
      const Offset(-60, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(_state(tester).page, 1);
  });

  testWidgets('the first and last page do not turn the wrong way', (
    tester,
  ) async {
    await _setUp(tester);
    await tester.pumpWidget(_harness(count: 6));

    await tester.drag(
      find.byKey(const ValueKey('tile-1')),
      const Offset(300, 0),
    );
    await tester.pumpAndSettle();
    expect(_state(tester).page, 0);

    _state(tester).showPage(1);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('tile-4')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    expect(_state(tester).page, 1);
    expect(find.byKey(const ValueKey('tile-5')), findsOneWidget);
  });

  testWidgets('the indicator is a full tap target that pages either way', (
    tester,
  ) async {
    await _setUp(tester);
    await tester.pumpWidget(_harness(count: 10));

    final indicator = find.byKey(PagedTileWell.indicatorKey);
    final box = tester.getRect(indicator);
    expect(box.height, greaterThanOrEqualTo(RunThruA11y.minTapTarget));

    // Right of the current dot: next page. Twice, to the last page.
    await tester.tapAt(box.center + const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(_state(tester).page, 1);
    await tester.tapAt(box.center + const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(_state(tester).page, 2);
    // The last page is shorter, but the indicator has not moved from under
    // the reader's finger.
    expect(tester.getRect(indicator), box);
    // Nothing further that way.
    await tester.tapAt(box.center + const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(_state(tester).page, 2);

    await tester.tapAt(box.center - const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(_state(tester).page, 1);
  });

  testWidgets('a screen reader can step through the pages', (tester) async {
    await _setUp(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_harness(count: 10, reduced: true));

    tester.semantics.increase(find.semantics.byLabel('Books pages'));
    await tester.pump();
    expect(_state(tester).page, 1);
    expect(
      tester.getSemantics(find.byKey(PagedTileWell.indicatorKey)).value,
      'Page 2 of 3',
    );
    handle.dispose();
  });

  testWidgets('the well grows to a taller page and does not shrink back', (
    tester,
  ) async {
    await _setUp(tester);
    // Page one: short titles. Page two: titles that wrap to two lines.
    await tester.pumpWidget(
      _harness(
        count: 10,
        titleOf: (i) => i < 4
            ? 'Book $i'
            : 'A Much Longer Title That Wraps Onto A Second Line $i',
      ),
    );
    final short = _wellHeight(tester);

    _state(tester).showPage(1);
    await tester.pumpAndSettle();
    final tall = _wellHeight(tester);
    expect(tall, greaterThan(short));
    expect(tester.takeException(), isNull);

    // Back on the short page, and on the last one (two tiles): same height.
    _state(tester).showPage(0);
    await tester.pumpAndSettle();
    expect(_wellHeight(tester), tall);
    _state(tester).showPage(2);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tile-9')), findsOneWidget);
    expect(_wellHeight(tester), tall);
  });

  testWidgets('long titles at large text sizes never overflow', (tester) async {
    await _setUp(tester);
    for (final scale in const [1.0, 1.3, 2.0, 3.0]) {
      await tester.pumpWidget(
        _harness(
          count: 8,
          textScale: scale,
          titleOf: (i) => 'Moby Dick; Or, The Whale, and Other Long Titles $i',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at ${scale}x');
      // Every row of the page is inside the well, whole.
      final well = tester.getRect(find.byType(PagedTileWell));
      for (var i = 0; i < 4; i++) {
        final tile = tester.getRect(find.byKey(ValueKey('tile-$i')));
        expect(tile.top, greaterThanOrEqualTo(well.top), reason: '$scale/$i');
        expect(
          tile.bottom,
          lessThanOrEqualTo(well.bottom),
          reason: '$scale/$i',
        );
      }
    }
  });

  testWidgets('reduced motion: pages change at once', (tester) async {
    await _setUp(tester);
    await tester.pumpWidget(_harness(count: 10, reduced: true));

    _state(tester).showPage(1);
    await tester.pump();
    expect(_state(tester).page, 1);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byKey(const ValueKey('tile-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-0')), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('tile-5')),
      const Offset(-220, 0),
    );
    await tester.pump();
    expect(_state(tester).page, 2);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a large library keeps a short row of dots', (tester) async {
    await _setUp(tester);
    // 200 books: 50 pages.
    await tester.pumpWidget(_harness(count: 200, reduced: true));
    expect(tester.takeException(), isNull);
    expect(_state(tester).pageCount, 50);

    int dots() => tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byKey(PagedTileWell.indicatorKey),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .length;
    expect(dots(), 7);

    _state(tester).showPage(25);
    await tester.pump();
    expect(dots(), 7);
    expect(find.byKey(const ValueKey('tile-100')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('losing tiles while on the last page steps back to a real one', (
    tester,
  ) async {
    await _setUp(tester);
    await tester.pumpWidget(_harness(count: 10, reduced: true));
    _state(tester).showPage(2);
    await tester.pump();
    expect(_state(tester).page, 2);

    await tester.pumpWidget(_harness(count: 5, reduced: true));
    await tester.pump();
    expect(_state(tester).page, 1);
    expect(find.byKey(const ValueKey('tile-4')), findsOneWidget);

    await tester.pumpWidget(_harness(count: 2, reduced: true));
    await tester.pump();
    expect(_state(tester).page, 0);
    expect(find.byKey(PagedTileWell.indicatorKey), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
