import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/widgets/library_source_menu.dart';

/// Builds the menu inside a full-screen [Stack] with optional reduced motion.
Widget _harness({
  required List<LibrarySourceAction> actions,
  bool reducedMotion = false,
}) {
  final menu = Scaffold(
    body: Stack(children: [LibrarySourceMenu(actions: actions)]),
  );
  return MaterialApp(
    home: reducedMotion
        ? MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: menu,
          )
        : menu,
  );
}

List<LibrarySourceAction> _actions({
  VoidCallback? onPaste,
  VoidCallback? onFolder,
  VoidCallback? onInstapaper,
}) {
  return [
    LibrarySourceAction(
      icon: Icons.content_paste,
      label: 'Paste',
      semanticsLabel: 'Paste from clipboard',
      onTap: onPaste ?? () {},
    ),
    LibrarySourceAction(
      icon: Icons.folder_outlined,
      label: 'Folder',
      semanticsLabel: 'Import from folder',
      onTap: onFolder ?? () {},
    ),
    LibrarySourceAction(
      icon: Icons.bookmark_outline,
      label: 'Instapaper',
      semanticsLabel: 'Add Instapaper',
      onTap: onInstapaper ?? () {},
    ),
  ];
}

void main() {
  group('LibrarySourceMenu', () {
    testWidgets('renders the + button (closed state) on the screen',
        (tester) async {
      await tester.pumpWidget(_harness(actions: _actions()));

      expect(find.bySemanticsLabel('Open reading sources'), findsOneWidget);
      // Closed: no action labels visible.
      expect(find.text('Paste'), findsNothing);
      expect(find.text('Folder'), findsNothing);
      expect(find.text('Instapaper'), findsNothing);
    });

    testWidgets('tapping + opens the cascading source stack with all actions',
        (tester) async {
      await tester.pumpWidget(_harness(actions: _actions()));

      await tester.tap(find.bySemanticsLabel('Open reading sources'));
      await tester.pumpAndSettle();

      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Folder'), findsOneWidget);
      expect(find.text('Instapaper'), findsOneWidget);
      // Button semantics flip to close.
      expect(find.bySemanticsLabel('Close reading sources'), findsOneWidget);
    });

    testWidgets('source actions appear in order Paste, Folder, Instapaper',
        (tester) async {
      await tester.pumpWidget(_harness(actions: _actions()));

      await tester.tap(find.bySemanticsLabel('Open reading sources'));
      await tester.pumpAndSettle();

      // Higher cards (later in order) sit higher on the screen → smaller dy.
      final pasteY = tester.getCenter(find.text('Paste')).dy;
      final folderY = tester.getCenter(find.text('Folder')).dy;
      final instaY = tester.getCenter(find.text('Instapaper')).dy;

      expect(folderY, lessThan(pasteY));
      expect(instaY, lessThan(folderY));

      // And lean right: each card's right edge sits further right.
      final pasteX = tester.getCenter(find.text('Paste')).dx;
      final instaX = tester.getCenter(find.text('Instapaper')).dx;
      expect(instaX, greaterThan(pasteX));
    });

    testWidgets('tapping outside closes the stack', (tester) async {
      await tester.pumpWidget(_harness(actions: _actions()));

      await tester.tap(find.bySemanticsLabel('Open reading sources'));
      await tester.pumpAndSettle();
      expect(find.text('Paste'), findsOneWidget);

      // Tap top-left corner, away from the cards/button.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Paste'), findsNothing);
      expect(find.bySemanticsLabel('Open reading sources'), findsOneWidget);
    });

    testWidgets('tapping an action invokes its callback and closes the stack',
        (tester) async {
      var pasteTapped = false;
      await tester.pumpWidget(
        _harness(actions: _actions(onPaste: () => pasteTapped = true)),
      );

      await tester.tap(find.bySemanticsLabel('Open reading sources'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      expect(pasteTapped, isTrue);
      expect(find.text('Paste'), findsNothing);
    });

    testWidgets('each action invokes the correct callback', (tester) async {
      var folder = false;
      var insta = false;
      await tester.pumpWidget(
        _harness(
          actions: _actions(
            onFolder: () => folder = true,
            onInstapaper: () => insta = true,
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Open reading sources'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Folder'));
      await tester.pumpAndSettle();
      expect(folder, isTrue);

      await tester.tap(find.bySemanticsLabel('Open reading sources'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instapaper'));
      await tester.pumpAndSettle();
      expect(insta, isTrue);
    });

    testWidgets('reduced motion still opens to a fully visible stack',
        (tester) async {
      await tester.pumpWidget(
        _harness(actions: _actions(), reducedMotion: true),
      );

      await tester.tap(find.bySemanticsLabel('Open reading sources'));
      // No stagger to settle — a single pump reveals everything.
      await tester.pump();

      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Folder'), findsOneWidget);
      expect(find.text('Instapaper'), findsOneWidget);
    });

    testWidgets('semantics labels are present for all actions',
        (tester) async {
      await tester.pumpWidget(_harness(actions: _actions()));

      await tester.tap(find.bySemanticsLabel('Open reading sources'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Paste from clipboard'), findsOneWidget);
      expect(find.bySemanticsLabel('Import from folder'), findsOneWidget);
      expect(find.bySemanticsLabel('Add Instapaper'), findsOneWidget);
      expect(find.bySemanticsLabel('Close reading sources'), findsOneWidget);
    });
  });
}
