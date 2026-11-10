import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/document_title.dart';

void main() {
  test('cleans file names into titles', () {
    expect(prettyFileTitle('lighthouse.epub'), 'lighthouse');
    expect(prettyFileTitle('/a/b/my_notes (1).pdf'), 'my notes');
    expect(prettyFileTitle('Report  2026 (12).PDF'), 'Report 2026');
    expect(prettyFileTitle('.hidden'), '.hidden');
  });

  test('titles shared text from its first line', () {
    expect(
      titleFromText('Morning Notes\n\nThe kettle clicked.'),
      'Morning Notes',
    );
    expect(
      titleFromText(
        'The kettle clicked off at seven while the rain thinned to mist outside.',
      ),
      'The kettle clicked off at seven…',
    );
    expect(titleFromText('\n\n  '), isNull);
    expect(titleFromText('https://example.com/post'), isNull);
  });
}
