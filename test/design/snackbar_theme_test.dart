import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/app.dart';
import 'package:runthru/design/tokens.dart';
import 'package:runthru/design/typography.dart';
import 'package:runthru/widgets/error_snack_bar.dart';

/// Locks the central SnackBar styling and the per-call error SnackBar styling
/// against the RunThru design tokens. See `lib/app.dart` (buildRunThruTheme)
/// and `lib/features/content/services/library_import.dart` (_showError).
void main() {
  final theme = buildRunThruTheme();

  group('Central SnackBarThemeData (normal SnackBars)', () {
    final snackTheme = theme.snackBarTheme;

    test('floating behavior with rounded shape', () {
      expect(snackTheme.behavior, SnackBarBehavior.floating);
      expect(snackTheme.shape, isA<RoundedRectangleBorder>());
    });

    test('background is shellInk', () {
      expect(snackTheme.backgroundColor, RunThruTokens.shellInk);
    });

    test('content text is RunThruTypography.body in shellCream', () {
      final style = snackTheme.contentTextStyle!;
      expect(style.color, RunThruTokens.shellCream);
      expect(style.fontFamily, RunThruTypography.body.fontFamily);
      expect(style.fontSize, RunThruTypography.body.fontSize);
      expect(style.fontWeight, RunThruTypography.body.fontWeight);
    });

    test('action color is shellReady (chosen interactive token)', () {
      expect(snackTheme.actionTextColor, RunThruTokens.shellReady);
    });
  });

  group('Rendered normal SnackBar resolves the theme', () {
    testWidgets('content uses themed style, not root textTheme', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Hello'),
                    action: SnackBarAction(label: 'Undo', onPressed: () {}),
                  ),
                ),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('Hello'));
      // SnackBar applies its content text style as the DefaultTextStyle; the
      // Text widget itself carries no explicit style, proving it inherits the
      // themed contentTextStyle rather than a widget-level override.
      expect(text.style, isNull);

      final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
      expect(action.label, 'Undo');
    });
  });

  group('errorSnackBar (per-call error styling)', () {
    test('uses the dark shellInk surface, never full-coral shellError', () {
      final bar = errorSnackBar(message: 'Boom');
      expect(bar.backgroundColor, RunThruTokens.shellInk);
      expect(bar.backgroundColor, isNot(RunThruTokens.shellError));
    });

    test('action uses shellError accent when supplied', () {
      final bar = errorSnackBar(
        message: 'Boom',
        action: SnackBarAction(
          label: 'Retry',
          textColor: RunThruTokens.shellError,
          onPressed: () {},
        ),
      );
      expect(bar.action, isNotNull);
      expect(bar.action!.textColor, RunThruTokens.shellError);
    });

    testWidgets('renders cream body text and a coral accent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(errorSnackBar(message: 'Could not open file.')),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();

      // Body text: RunThruTypography.body resolved in shellCream.
      final text = tester.widget<Text>(find.text('Could not open file.'));
      expect(text.style!.color, RunThruTokens.shellCream);
      expect(text.style!.fontSize, RunThruTypography.body.fontSize);
      expect(text.style!.fontFamily, RunThruTypography.body.fontFamily);
      expect(text.style!.fontWeight, RunThruTypography.body.fontWeight);

      // Coral error icon accent.
      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.color, RunThruTokens.shellError);

      // Coral left-edge accent bar.
      final coralBar = find.byWidgetPredicate(
        (w) => w is Container && w.color == RunThruTokens.shellError,
      );
      expect(coralBar, findsOneWidget);
    });
  });
}
