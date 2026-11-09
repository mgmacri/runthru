import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/screens/privacy_policy_screen.dart';

void main() {
  group('parsePolicyMarkdown', () {
    test('maps headings, bullets and paragraphs; drops title and rules', () {
      const md = '''
# RunThru Privacy Policy

**Effective date: June 10, 2026**

---

## What stays on your device

### Clipboard text
When you paste text, the app reads it
locally.

- **No ads.** RunThru shows no advertising
  and shares nothing.
- second

<!-- TODO: add support contact -->
''';
      expect(parsePolicyMarkdown(md), const [
        PolicyBlock(PolicyBlockKind.paragraph, 'Effective date: June 10, 2026'),
        PolicyBlock(PolicyBlockKind.heading, 'What stays on your device'),
        PolicyBlock(PolicyBlockKind.subheading, 'Clipboard text'),
        PolicyBlock(
          PolicyBlockKind.paragraph,
          'When you paste text, the app reads it locally.',
        ),
        PolicyBlock(
          PolicyBlockKind.bullet,
          'No ads. RunThru shows no advertising and shares nothing.',
        ),
        PolicyBlock(PolicyBlockKind.bullet, 'second'),
      ]);
    });

    test('the bundled policy parses and is registered as an asset', () {
      final source = File(privacyPolicyAsset).readAsStringSync();
      final blocks = parsePolicyMarkdown(source);
      expect(
        blocks.where((b) => b.kind == PolicyBlockKind.heading),
        isNotEmpty,
      );
      expect(blocks.any((b) => b.text.contains('**')), isFalse);
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('- $privacyPolicyAsset'),
      );
    });
  });

  testWidgets('screen renders headings as semantic headers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyPolicyScreen(
          loader: () async => '## Contact\n\nQuestions are welcome.\n',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('Questions are welcome.'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Contact')),
      matchesSemantics(label: 'Contact', isHeader: true),
    );
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
  });
}
