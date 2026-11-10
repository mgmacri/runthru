import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/document_title.dart';

void main() {
  test('cleans file names into titles', () {
    expect(prettyFileTitle('lighthouse.epub'), 'lighthouse');
    expect(prettyFileTitle('/a/b/my_notes (1).pdf'), 'my notes');
    expect(prettyFileTitle('Report  2026 (12).PDF'), 'Report 2026');
    expect(prettyFileTitle('.hidden'), '.hidden');
  });
}
