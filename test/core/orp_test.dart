import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/core/orp.dart';

void main() {
  group('orpIndex (center letter)', () {
    test('single character → 1', () {
      expect(orpIndex('a'), 1);
      expect(orpIndex('I'), 1);
    });

    test('2 characters → 1', () {
      expect(orpIndex('an'), 1);
      expect(orpIndex('if'), 1);
    });

    test('3 characters → 2 (center)', () {
      expect(orpIndex('the'), 2);
    });

    test('4 characters → 2 (left of center)', () {
      expect(orpIndex('word'), 2);
    });

    test('5 characters → 3 (center)', () {
      expect(orpIndex('reads'), 3);
      expect(orpIndex('speed'), 3);
    });

    test('7 characters → 4 (center)', () {
      expect(orpIndex('reading'), 4);
      expect(orpIndex('display'), 4);
    });

    test('9 characters → 5 (center)', () {
      expect(orpIndex('beautiful'), 5);
    });

    test('10 characters → 5', () {
      expect(orpIndex('understand'), 5);
    });

    test('11 characters → 6', () {
      expect(orpIndex('recognition'), 6);
    });

    test('14 characters → 7', () {
      expect(orpIndex('transformation'), 7);
    });

    test('strips leading/trailing punctuation', () {
      // "hello" → strips to hello (5 chars) → center = 3
      expect(orpIndex('"hello"'), 3);
      // (test) → strips to test (4 chars) → center = 2
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
      // reading = 7 chars → center = 4
      expect(orpIndexInOriginal('reading'), 4);
    });

    test('with leading punctuation', () {
      // "hello" → leading " is 1 char, hello is 5 chars → center 3
      // original index = 1 + 3 = 4
      expect(orpIndexInOriginal('"hello"'), 4);
    });
  });
}
