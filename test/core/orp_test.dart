import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_boy/core/orp.dart';

void main() {
  group('orpIndex', () {
    test('single character → 1', () {
      expect(orpIndex('a'), 1);
      expect(orpIndex('I'), 1);
    });

    test('2-3 characters → 1', () {
      expect(orpIndex('the'), 1);
      expect(orpIndex('an'), 1);
      expect(orpIndex('if'), 1);
    });

    test('4-5 characters → 2', () {
      expect(orpIndex('reads'), 2);
      expect(orpIndex('word'), 2);
      expect(orpIndex('speed'), 2);
    });

    test('6-9 characters → 3', () {
      expect(orpIndex('reading'), 3);
      expect(orpIndex('display'), 3);
      expect(orpIndex('beautiful'), 3);
    });

    test('10-13 characters → 4', () {
      expect(orpIndex('understand'), 4);
      expect(orpIndex('recognition'), 4);
    });

    test('14+ characters → 5', () {
      expect(orpIndex('transformation'), 5);
      expect(orpIndex('internationalize'), 5);
    });

    test('strips leading/trailing punctuation', () {
      // "hello" → strips to hello (5 chars) → 2
      expect(orpIndex('"hello"'), 2);
      // (test) → strips to test (4 chars) → 2
      expect(orpIndex('(test)'), 2);
    });

    test('empty string → 1', () {
      expect(orpIndex(''), 1);
    });

    test('punctuation only → 1', () {
      expect(orpIndex('...'), 1);
    });
  });

  group('orpIndexInOriginal', () {
    test('no punctuation', () {
      expect(orpIndexInOriginal('reading'), 3);
    });

    test('with leading punctuation', () {
      // "hello" → leading " is 1 char, hello is 5 chars → orp 2
      // original index = 1 + 2 = 3
      expect(orpIndexInOriginal('"hello"'), 3);
    });
  });
}
