import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/widgets/runthru_shell_widgets.dart';

Widget _harness(Widget child, {bool reducedMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('RunThru shell widgets', () {
    testWidgets('RunThruMark exposes semantics and stable size', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(const RunThruMark(size: 48)));

      expect(find.bySemanticsLabel('RunThru'), findsOneWidget);
      expect(tester.getSize(find.byType(RunThruMark)), const Size(48, 48));
      expect(find.text('RT'), findsOneWidget);
    });

    testWidgets('RunThruGlyphMark uses the teal designer token', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(const RunThruGlyphMark(size: 26)));

      final text = tester.widget<Text>(find.text('RT'));
      expect(text.style?.color, RunThruTokens.shellTealDeep);
      expect(text.style?.fontSize, 26);
    });

    testWidgets('segmented filter changes selection', (tester) async {
      var selected = 'All';
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return _harness(
              RunThruSegmentedFilter<String>(
                values: const ['All', 'Books'],
                selected: selected,
                labelFor: (value) => value,
                onChanged: (value) => setState(() => selected = value),
              ),
            );
          },
        ),
      );

      await tester.tap(find.text('Books'));
      await tester.pump();

      expect(selected, 'Books');
      expect(find.bySemanticsLabel('Books filter'), findsOneWidget);
    });

    testWidgets('progress ring reports percentage semantics', (tester) async {
      await tester.pumpWidget(_harness(const RunThruProgressRing(value: 0.42)));

      final semantics = tester.widget<Semantics>(
        find.descendant(
          of: find.byType(RunThruProgressRing),
          matching: find.byType(Semantics),
        ),
      );
      expect(semantics.properties.label, '42 percent read');
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('status pill and primary button render expected labels', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        _harness(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const RunThruStatusPill(
                label: 'Ready',
                tone: RunThruStatusTone.ready,
              ),
              RunThruPrimaryButton(
                label: 'Add a source',
                icon: Icons.add,
                onPressed: () => tapped = true,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Ready'), findsOneWidget);
      await tester.tap(find.text('Add a source'));
      expect(tapped, isTrue);
    });

    testWidgets('reduced motion segmented filter updates in one pump', (
      tester,
    ) async {
      var selected = 'All';
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return _harness(
              RunThruSegmentedFilter<String>(
                values: const ['All', 'Docs'],
                selected: selected,
                labelFor: (value) => value,
                onChanged: (value) => setState(() => selected = value),
              ),
              reducedMotion: true,
            );
          },
        ),
      );

      await tester.tap(find.text('Docs'));
      await tester.pump();

      expect(selected, 'Docs');
    });

    // WCAG 2.2 AA — interactive shell widgets must meet tap-target,
    // contrast, and labeling guidelines.
    testWidgets('shell controls meet accessibility guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _harness(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RunThruSegmentedFilter<String>(
                values: const ['All', 'Books'],
                selected: 'All',
                labelFor: (value) => value,
                onChanged: (_) {},
              ),
              const SizedBox(height: 12),
              RunThruPrimaryButton(
                label: 'Add a source',
                icon: Icons.add,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });
}
