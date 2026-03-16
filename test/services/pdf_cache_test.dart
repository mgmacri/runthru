import 'package:flutter_test/flutter_test.dart';

// TODO: Import PdfCache and set up temp directory for tests.

void main() {
  group('PdfCache', () {
    test('save and load round-trip produces identical document', () {
      // TODO: Implement
    }, skip: 'Shell test — implementation pending');

    test('load returns null for missing cache entry', () {
      // TODO: Implement
    }, skip: 'Shell test — implementation pending');

    test('cache key changes when file is modified', () {
      // TODO: Implement
    }, skip: 'Shell test — implementation pending');

    test('LRU eviction removes oldest entries when budget exceeded', () {
      // TODO: Implement
    }, skip: 'Shell test — implementation pending');

    test('handles corrupt JSON gracefully (returns null, does not throw)', () {
      // TODO: Implement
    }, skip: 'Shell test — implementation pending');
  });
}
