import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/reading/providers/reading_mode_provider.dart';
import 'package:runthru/features/reading/widgets/mode_switcher.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('ModeSwitcher', () {
    testWidgets('mode label uses explicit RunThru typography token', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const ModeSwitcher()));
      await tester.pump();

      final label = tester.widget<Text>(find.text('Word'));
      expect(
        label.style,
        RunThruTypography.rowTitle.copyWith(
          color: RunThruTokens.shellTealDeep,
          fontSize: 14,
        ),
      );
    });

    testWidgets('visible chip text does not rely on Material default', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const ModeSwitcher()));
      await tester.pump();

      final textWidgets = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(ModeSwitcher),
          matching: find.byType(Text),
        ),
      );
      expect(textWidgets, isNotEmpty);
      for (final text in textWidgets) {
        expect(text.style, isNotNull, reason: text.data);
      }
    });

    testWidgets('opens menu and directly selects a reading mode', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const ModeSwitcher()));
      await tester.pump();

      await tester.tap(find.text('Word'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Full Page').last);
      await tester.pumpAndSettle();

      expect(find.text('Full Page'), findsOneWidget);
      final context = tester.element(find.byType(ModeSwitcher));
      final container = ProviderScope.containerOf(context);
      expect(container.read(readingModeNotifierProvider), ReadingMode.fullPage);
    });
  });
}
