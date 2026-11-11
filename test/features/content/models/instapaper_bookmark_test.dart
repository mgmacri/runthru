import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/models/instapaper_bookmark.dart';

void main() {
  group('value readers', () {
    test('instapaperInt accepts whole numbers, fractions and strings', () {
      expect(instapaperInt(7), 7);
      expect(instapaperInt(1700000000.0), 1700000000);
      expect(instapaperInt('42'), 42);
      expect(instapaperInt(' 42.9 '), 42);
      expect(instapaperInt(null), isNull);
      expect(instapaperInt('abc'), isNull);
      expect(instapaperInt(double.nan), isNull);
      expect(instapaperInt(true), isNull);
    });

    test('instapaperDouble accepts numbers and numeric strings', () {
      expect(instapaperDouble(1), 1.0);
      expect(instapaperDouble('0.5'), 0.5);
      expect(instapaperDouble(null), isNull);
      expect(instapaperDouble(double.infinity), isNull);
    });

    test('instapaperString never returns null', () {
      expect(instapaperString('a'), 'a');
      expect(instapaperString(null), '');
      expect(instapaperString(12), '12');
    });
  });

  group('InstapaperBookmark.tryFromJson', () {
    test('needs only a bookmark id', () {
      final bookmark = InstapaperBookmark.tryFromJson({'bookmark_id': 5})!;

      expect(bookmark.bookmarkId, 5);
      expect(bookmark.url, '');
      expect(bookmark.title, '');
      expect(bookmark.progress, 0.0);
      expect(bookmark.hasProgress, isFalse);
      expect(bookmark.starred, isFalse);
    });

    test('returns null without a usable id', () {
      expect(InstapaperBookmark.tryFromJson({'title': 'x'}), isNull);
      expect(InstapaperBookmark.tryFromJson({'bookmark_id': 'x'}), isNull);
      expect(
        () => InstapaperBookmark.fromJson({'title': 'x'}),
        throwsFormatException,
      );
    });

    test('keeps progress inside 0 to 1', () {
      expect(
        InstapaperBookmark.tryFromJson({
          'bookmark_id': 1,
          'progress': 1.7,
        })!.progress,
        1.0,
      );
      expect(
        InstapaperBookmark.tryFromJson({
          'bookmark_id': 1,
          'progress': -3,
        })!.progress,
        0.0,
      );
    });

    test('reads starred as "1", 1 or true', () {
      for (final value in <Object>['1', 1, true]) {
        expect(
          InstapaperBookmark.tryFromJson({
            'bookmark_id': 1,
            'starred': value,
          })!.starred,
          isTrue,
          reason: '$value',
        );
      }
      expect(
        InstapaperBookmark.tryFromJson({
          'bookmark_id': 1,
          'starred': '0',
        })!.starred,
        isFalse,
      );
    });

    test('round-trips through toJson', () {
      const original = InstapaperBookmark(
        bookmarkId: 9,
        url: 'https://example.com/a',
        title: 'A',
        description: 'd',
        hash: 'h',
        progress: 0.5,
        progressTimestamp: 10,
        time: 20,
        starred: true,
        privateSource: '',
      );

      final copy = InstapaperBookmark.fromJson(original.toJson());

      expect(copy.toJson(), original.toJson());
    });
  });

  group('display', () {
    test('domain drops "www." and is empty for private bookmarks', () {
      const web = InstapaperBookmark(
        bookmarkId: 1,
        url: 'https://www.Example.com/story?id=1',
        title: '',
      );
      const private = InstapaperBookmark(
        bookmarkId: 2,
        url: 'instapaper://private-content/123',
        title: '',
        privateSource: 'email',
      );

      expect(web.domain, 'example.com');
      expect(web.hasWebUrl, isTrue);
      expect(private.domain, '');
      expect(private.hasWebUrl, isFalse);
    });

    test('displayTitle falls back to the site, then the source', () {
      const titled = InstapaperBookmark(
        bookmarkId: 1,
        url: 'https://example.com/a',
        title: '  The Title  ',
      );
      const untitled = InstapaperBookmark(
        bookmarkId: 1,
        url: 'https://example.com/a',
        title: ' ',
      );
      const private = InstapaperBookmark(
        bookmarkId: 2,
        url: 'instapaper://private-content/123',
        title: '',
        privateSource: 'email',
      );
      const nothing = InstapaperBookmark(bookmarkId: 3, url: '', title: '');

      expect(titled.displayTitle, 'The Title');
      expect(untitled.displayTitle, 'example.com');
      expect(private.displayTitle, 'email');
      expect(nothing.displayTitle, 'Untitled article');
    });
  });
}
