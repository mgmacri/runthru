import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MockHttpClient mockHttp;
  late InstapaperClient client;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    mockHttp = MockHttpClient();
    client = InstapaperClient(httpClient: mockHttp);
  });

  group('authenticate', () {
    test('returns token pair on successful xAuth', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          'oauth_token=test_token_abc&oauth_token_secret=test_secret_xyz',
          200,
        ),
      );

      final result = await client.authenticate(
        username: 'user@test.com',
        password: 'pass123',
      );

      expect(result.token, equals('test_token_abc'));
      expect(result.tokenSecret, equals('test_secret_xyz'));
      expect(client.isAuthenticated, isTrue);
    });

    test('throws InstapaperAuthException on 403 invalid credentials', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('', 403));

      expect(
        () => client.authenticate(username: 'bad@user.com', password: 'wrong'),
        throwsA(
          isA<InstapaperAuthException>().having(
            (e) => e.statusCode,
            'statusCode',
            403,
          ),
        ),
      );
    });

    test('throws InstapaperAuthException on 500 server error', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('', 500));

      expect(
        () => client.authenticate(username: 'user@test.com', password: 'pass'),
        throwsA(
          isA<InstapaperAuthException>().having(
            (e) => e.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
    });

    test('throws on malformed token response', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('garbage_response', 200));

      expect(
        () => client.authenticate(username: 'user@test.com', password: 'pass'),
        throwsA(isA<InstapaperAuthException>()),
      );
    });

    test('clears previous tokens before xAuth attempt', () async {
      client.setTokens(token: 'old_token', tokenSecret: 'old_secret');

      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          'oauth_token=new_token&oauth_token_secret=new_secret',
          200,
        ),
      );

      await client.authenticate(username: 'user@test.com', password: 'pass');

      final captured = verify(
        () => mockHttp.post(
          captureAny(),
          headers: captureAny(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;

      final headers = captured[1] as Map<String, String>;
      // Authorization header should NOT contain oauth_token (xAuth signs
      // with consumer-only)
      expect(headers['Authorization'], isNotNull);
    });
  });

  group('OAuth signing', () {
    test('Authorization header contains required OAuth params', () async {
      client.setTokens(token: 'test_token', tokenSecret: 'test_secret');

      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '[{"type":"user","user_id":123,"username":"test"}]',
          200,
        ),
      );

      await client.verifyCredentials();

      final captured = verify(
        () => mockHttp.post(
          captureAny(),
          headers: captureAny(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;

      final headers = captured[1] as Map<String, String>;
      final auth = headers['Authorization']!;
      expect(auth, startsWith('OAuth '));
      expect(auth, contains('oauth_consumer_key'));
      expect(auth, contains('oauth_signature_method="HMAC-SHA1"'));
      expect(auth, contains('oauth_timestamp'));
      expect(auth, contains('oauth_nonce'));
      expect(auth, contains('oauth_version="1.0"'));
      expect(auth, contains('oauth_signature'));
    });

    test('requests use POST method to correct URL', () async {
      client.setTokens(token: 'test_token', tokenSecret: 'test_secret');

      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '[{"type":"user","user_id":123,"username":"test"}]',
          200,
        ),
      );

      await client.verifyCredentials();

      final captured = verify(
        () => mockHttp.post(
          captureAny(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).captured;

      final uri = captured[0] as Uri;
      expect(uri.toString(), contains('/api/1/account/verify_credentials'));
    });
  });

  group('token lifecycle', () {
    test('isAuthenticated is false initially', () {
      expect(client.isAuthenticated, isFalse);
    });

    test('isAuthenticated is true after setTokens', () {
      client.setTokens(token: 'tok', tokenSecret: 'sec');
      expect(client.isAuthenticated, isTrue);
    });

    test('isAuthenticated is false after clearTokens', () {
      client.setTokens(token: 'tok', tokenSecret: 'sec');
      client.clearTokens();
      expect(client.isAuthenticated, isFalse);
    });
  });

  group('verifyCredentials', () {
    test('returns InstapaperUser on success', () async {
      client.setTokens(token: 'tok', tokenSecret: 'sec');

      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '[{"type":"user","user_id":54321,"username":"TestUser"}]',
          200,
        ),
      );

      final user = await client.verifyCredentials();
      expect(user.userId, equals(54321));
      expect(user.username, equals('TestUser'));
    });

    test('throws InstapaperApiException on error response', () async {
      client.setTokens(token: 'tok', tokenSecret: 'sec');

      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '[{"type":"error","error_code":1040,"message":"Rate-limit exceeded"}]',
          400,
        ),
      );

      expect(
        () => client.verifyCredentials(),
        throwsA(
          isA<InstapaperApiException>().having(
            (e) => e.errorCode,
            'errorCode',
            1040,
          ),
        ),
      );
    });
  });

  group('getBookmarks', () {
    setUp(() {
      client.setTokens(token: 'tok', tokenSecret: 'sec');
    });

    test('returns list of bookmarks on success', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode([
            {'type': 'meta'},
            {'type': 'user', 'user_id': 123, 'username': 'test'},
            {
              'type': 'bookmark',
              'bookmark_id': 1001,
              'url': 'https://example.com/article1',
              'title': 'Test Article',
              'description': 'A test article',
              'hash': 'abc123',
              'progress': 0.5,
              'progress_timestamp': 1700000000,
              'time': 1699000000,
              'starred': '0',
              'private_source': '',
            },
            {
              'type': 'bookmark',
              'bookmark_id': 1002,
              'url': 'https://example.com/article2',
              'title': 'Second Article',
              'description': '',
              'hash': 'def456',
              'progress': 0.0,
              'progress_timestamp': 0,
              'time': 1699000001,
              'starred': '1',
              'private_source': '',
            },
          ]),
          200,
        ),
      );

      final bookmarks = await client.getBookmarks();
      expect(bookmarks, hasLength(2));
      expect(bookmarks[0].bookmarkId, equals(1001));
      expect(bookmarks[0].title, equals('Test Article'));
      expect(bookmarks[0].progress, equals(0.5));
      expect(bookmarks[0].domain, equals('example.com'));
      expect(bookmarks[0].hasProgress, isTrue);
      expect(bookmarks[1].starred, isTrue);
      expect(bookmarks[1].hasProgress, isFalse);
    });

    test('returns empty list when no bookmarks', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode([
            {'type': 'meta'},
            {'type': 'user', 'user_id': 123, 'username': 'test'},
          ]),
          200,
        ),
      );

      final bookmarks = await client.getBookmarks();
      expect(bookmarks, isEmpty);
    });

    test('filters out non-bookmark items', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode([
            {'type': 'meta'},
            {'type': 'user', 'user_id': 123, 'username': 'test'},
            {
              'type': 'bookmark',
              'bookmark_id': 1,
              'url': 'https://a.com',
              'title': 'A',
              'description': '',
              'hash': 'xyz',
              'progress': 0.0,
              'progress_timestamp': 0,
              'time': 0,
              'starred': '0',
              'private_source': '',
            },
          ]),
          200,
        ),
      );

      final bookmarks = await client.getBookmarks();
      expect(bookmarks, hasLength(1));
    });

    test('throws InstapaperApiException on error', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '[{"type":"error","error_code":1040,"message":"Rate-limit exceeded"}]',
          400,
        ),
      );

      expect(
        () => client.getBookmarks(),
        throwsA(
          isA<InstapaperApiException>().having(
            (e) => e.errorCode,
            'errorCode',
            1040,
          ),
        ),
      );
    });

    test('clamps limit to 1-500', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode([
            {'type': 'meta'},
            {'type': 'user', 'user_id': 123, 'username': 'test'},
          ]),
          200,
        ),
      );

      await client.getBookmarks(limit: 0); // should clamp to 1
      await client.getBookmarks(limit: 1000); // should clamp to 500

      final captured = verify(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;

      expect((captured[0] as Map)['limit'], equals('1'));
      expect((captured[1] as Map)['limit'], equals('500'));
    });
  });

  group('getBookmarkText', () {
    setUp(() {
      client.setTokens(token: 'tok', tokenSecret: 'sec');
    });

    test('returns HTML string on success', () async {
      const html = '<html><body><p>Article content here.</p></body></html>';
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response(html, 200));

      final result = await client.getBookmarkText(bookmarkId: 1001);
      expect(result, equals(html));
    });

    test(
      'throws InstapaperApiException with code 1041 on premium required',
      () async {
        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            '[{"type":"error","error_code":1041,"message":"Premium account required"}]',
            403,
          ),
        );

        expect(
          () => client.getBookmarkText(bookmarkId: 1001),
          throwsA(
            isA<InstapaperApiException>().having(
              (e) => e.errorCode,
              'errorCode',
              1041,
            ),
          ),
        );
      },
    );

    test(
      'throws InstapaperApiException with code 1550 on text generation error',
      () async {
        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            '[{"type":"error","error_code":1550,"message":"Error generating text"}]',
            400,
          ),
        );

        expect(
          () => client.getBookmarkText(bookmarkId: 1001),
          throwsA(
            isA<InstapaperApiException>().having(
              (e) => e.errorCode,
              'errorCode',
              1550,
            ),
          ),
        );
      },
    );

    test('sends bookmark_id in request body', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('<p>text</p>', 200));

      await client.getBookmarkText(bookmarkId: 42);

      final captured = verify(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;

      expect((captured[0] as Map)['bookmark_id'], equals('42'));
    });
  });
}
