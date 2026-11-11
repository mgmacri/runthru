import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/screens/range_picker_screen.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeConfigNotifier extends AsyncNotifier<AppConfig>
    implements ConfigNotifier {
  @override
  Future<AppConfig> build() async =>
      const AppConfig(hasSeenReadingGoalOnboarding: true);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Regression (B-02): dispose() used `ref.read`, which Riverpod forbids once
  // the element is unmounting. That threw, skipped the rest of dispose, and
  // leaked the animation controller and notifiers.
  testWidgets('unmounting the range picker does not throw', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [configProvider.overrideWith(_FakeConfigNotifier.new)],
        child: const MaterialApp(
          home: RangePickerScreen(filePath: 'clipboard://test'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });

  group('wordIndexOnPage', () {
    // Extracted text of two pages; page two starts at word 6.
    const words = [
      'The',
      'harbour',
      'master',
      'counted',
      'the',
      'lanterns.',
      'His',
      'father',
      'had',
      'kept',
      'the',
      'first',
      'office,',
      'too.',
    ];

    test('finds the word picked on the page', () {
      expect(wordIndexOnPage(words, 0, 6, 'master'), 2);
      expect(wordIndexOnPage(words, 6, 14, 'kept'), 3);
      // Positions are counted from the start of the page.
      expect(wordIndexOnPage(words, 6, 14, 'the'), 4);
    });

    test('punctuation and capitals on either side do not matter', () {
      expect(wordIndexOnPage(words, 0, 6, 'lanterns'), 5);
      expect(wordIndexOnPage(words, 0, 6, 'HARBOUR,'), 1);
      expect(wordIndexOnPage(words, 6, 14, '(office'), 6);
    });

    test('a ligature on the page matches the letters in the text', () {
      expect(wordIndexOnPage(words, 6, 14, '\uFB01rst'), 5);
      expect(wordIndexOnPage(words, 6, 14, 'o\uFB03ce,'), 6);
    });

    test('half of a word the page hyphenates finds the whole word', () {
      // The page breaks "father" as "fa-" / "ther".
      expect(wordIndexOnPage(words, 6, 14, 'fa-'), 1);
      expect(wordIndexOnPage(words, 6, 14, 'fa\u0002'), 1);
      // An exact word still wins over a longer one that starts the same.
      expect(wordIndexOnPage(const ['there', 'then', 'the'], 0, 3, 'the-'), 2);
    });

    test('a word that is not on the page falls back to its start', () {
      expect(wordIndexOnPage(words, 0, 6, 'whale'), 0);
      // Without a break mark, a fragment is not guessed at.
      expect(wordIndexOnPage(words, 6, 14, 'fa'), 0);
      expect(wordIndexOnPage(words, 6, 14, '...'), 0);
      expect(wordIndexOnPage(const [], 0, 0, 'the'), 0);
      // A page range past the end of the text is clamped.
      expect(wordIndexOnPage(words, 6, 99, 'too'), 7);
    });
  });
}
