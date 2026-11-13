import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  const testConfig = InstapaperClientConfig(
    consumerKey: 'consumer_key',
    consumerSecret: 'consumer_secret',
  );
  late MockHttpClient mockHttp;
  late InstapaperClient client;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    mockHttp = MockHttpClient();
    client = InstapaperClient(httpClient: mockHttp, config: testConfig);
  });

  group('authenticate', () {
    test(
      'throws setup error before token exchange when consumer config missing',
      () async {
        final missingConfigClient = InstapaperClient(httpClient: mockHttp);

        expect(
          () => missingConfigClient.authenticate(
            username: 'user@test.com',
            password: 'pass123',
          ),
          throwsA(
            isA<InstapaperAuthException>().having(
              (e) => e.kind,
              'kind',
              InstapaperFailureKind.missingConfiguration,
            ),
          ),
        );
        verifyNever(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        );
      },
    );

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

    test('parses URL-encoded token response robustly', () {
      final result = InstapaperClient.parseOAuthTokenResponse(
        'oauth_token=test%20token&oauth_token_secret=test%2Bsecret',
      );

      expect(result.token, equals('test token'));
      expect(result.tokenSecret, equals('test+secret'));
    });

    test('rejects token response missing token secret', () {
      expect(
        () => InstapaperClient.parseOAuthTokenResponse('oauth_token=abc'),
        throwsA(
          isA<InstapaperAuthException>().having(
            (e) => e.kind,
            'kind',
            InstapaperFailureKind.unexpectedResponse,
          ),
        ),
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
      expect(headers['Authorization'], isNot(contains('old_token')));
    });
  });

  group('redaction', () {
    test('redacts credentials, tokens, and Authorization headers', () {
      final redacted = InstapaperRedactor.redact(
        'username=user@test.com password=secret '
        'oauth_token=tokenValue oauth_token_secret=secretValue '
        'Authorization: OAuth oauth_token="headerValue", oauth_signature="sig"',
      );

      expect(redacted, isNot(contains('user@test.com')));
      expect(redacted, isNot(contains(' secret ')));
      expect(redacted, isNot(contains('tokenValue')));
      expect(redacted, isNot(contains('secretValue')));
      expect(redacted, isNot(contains('headerValue')));
      expect(redacted, isNot(contains('sig')));
      expect(redacted, contains('[REDACTED]'));
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

  // ── Regression tests for B-45 (checked against the live API) ─────────────

  /// 1700000000 seconds after the epoch.
  final fixedNow = DateTime.utc(2023, 11, 14, 22, 13, 20);

  InstapaperClient fixedClient({Duration? requestTimeout}) => InstapaperClient(
    httpClient: mockHttp,
    config: testConfig,
    now: () => fixedNow,
    nonce: () => 'testnonce',
    requestTimeout: requestTimeout ?? const Duration(seconds: 20),
  );

  void stubPost(FutureOr<http.Response> Function(Invocation) answer) {
    when(
      () => mockHttp.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((invocation) async => answer(invocation));
  }

  /// Authorization headers of every POST made so far, in order.
  List<String> sentAuthHeaders() {
    final captured = verify(
      () => mockHttp.post(
        any(),
        headers: captureAny(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).captured;
    return [
      for (final headers in captured)
        (headers as Map<String, String>)['Authorization']!,
    ];
  }

  /// Form bodies of every POST made so far, in order.
  List<Map<String, String>> sentBodies() {
    final captured = verify(
      () => mockHttp.post(
        any(),
        headers: any(named: 'headers'),
        body: captureAny(named: 'body'),
      ),
    ).captured;
    return [for (final body in captured) body as Map<String, String>];
  }

  String oauthParam(String header, String name) {
    final match = RegExp('$name="([^"]*)"').firstMatch(header);
    return Uri.decodeComponent(match!.group(1)!);
  }

  const userJson = '[{"type":"user","user_id":123,"username":"test"}]';

  group('OAuth 1.0a encoding and signature', () {
    test('percentEncode leaves only RFC 3986 unreserved characters', () {
      expect(InstapaperClient.percentEncode("!*'()"), '%21%2A%27%28%29');
      expect(InstapaperClient.percentEncode('a b+c'), 'a%20b%2Bc');
      expect(InstapaperClient.percentEncode('A-z_0.9~'), 'A-z_0.9~');
      expect(InstapaperClient.percentEncode('é€'), '%C3%A9%E2%82%AC');
      expect(
        InstapaperClient.percentEncode('a@b.co/x?y=z&w'),
        'a%40b.co%2Fx%3Fy%3Dz%26w',
      );
    });

    test('matches the published OAuth 1.0a signature example', () {
      // The worked example from Twitter's "Creating a signature" guide.
      final base = InstapaperClient.signatureBaseString(
        method: 'post',
        url: 'https://api.twitter.com/1.1/statuses/update.json',
        params: const {
          'status': 'Hello Ladies + Gentlemen, a signed OAuth request!',
          'include_entities': 'true',
          'oauth_consumer_key': 'xvz1evFS4wEEPTGEFPHBog',
          'oauth_nonce': 'kYjzVBB8Y0ZFabxSWbWovY3uYSQ2pTgmZeNu2VS4cg',
          'oauth_signature_method': 'HMAC-SHA1',
          'oauth_timestamp': '1318622958',
          'oauth_token': '370773112-GmHxMAgYyLbNEtIKZeRNFsMKPR9EyMZeS9weJAEb',
          'oauth_version': '1.0',
        },
      );
      expect(base, endsWith('a%2520signed%2520OAuth%2520request%2521'));
      expect(
        InstapaperClient.sign(
          baseString: base,
          consumerSecret: 'kAcSOqF21Fu85e7zjz7ZN2U4ZRhfV3WpwPAoE3Z7kBw',
          tokenSecret: 'LswwdoUaIvS8ltyTt5jkRh4J50vUPVVHtR2YPi5kE',
        ),
        'hCtSmYh+iHYCEqBWrE7C7hYmtUk=',
      );
    });

    test(
      'a password with ! * \' ( ) is signed the way Instapaper expects',
      () async {
        // Instapaper answered 403 "Invalid signature" for this password while
        // the signature left those characters unencoded.
        stubPost(
          (_) => http.Response('oauth_token=t&oauth_token_secret=s', 200),
        );

        await fixedClient().authenticate(
          username: 'reader@example.com',
          password: "pa!ss*(1)'",
        );

        final header = sentAuthHeaders().single;
        expect(oauthParam(header, 'oauth_timestamp'), '1700000000');
        expect(oauthParam(header, 'oauth_nonce'), 'testnonce');
        // Computed independently (Python hmac) from the base string
        // …x_auth_password%3Dpa%2521ss%252A%25281%2529%2527%26x_auth_username…
        expect(
          oauthParam(header, 'oauth_signature'),
          'OXV0mGk0frXzCmAtXyoKumCH158=',
        );
      },
    );

    test('a signed call includes the token and both secrets', () async {
      stubPost((_) => http.Response('[]', 200));
      final c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');

      await c.getBookmarks();

      final header = sentAuthHeaders().single;
      expect(oauthParam(header, 'oauth_token'), 'tok');
      expect(
        oauthParam(header, 'oauth_signature'),
        'DxMetF2+z8dlMDzUIdm7d0b3rA0=',
      );
    });

    test('a refused xAuth never keeps the response body', () async {
      // On a bad signature the server echoes the signed parameters.
      stubPost(
        (_) => http.Response(
          '<html><title>403: Invalid signature. Expected signature base '
          'string: x_auth_password%3Dhunter2</title></html>',
          403,
        ),
      );

      Object? caught;
      try {
        await fixedClient().authenticate(username: 'u', password: 'hunter2');
      } on InstapaperAuthException catch (e) {
        caught = e;
      }
      expect(caught, isA<InstapaperAuthException>());
      expect(caught.toString(), isNot(contains('hunter2')));
      expect(
        (caught! as InstapaperAuthException).kind,
        InstapaperFailureKind.unexpectedResponse,
      );
    });
  });

  group('xAuth failures', () {
    Future<InstapaperFailureKind> kindFor(http.Response response) async {
      stubPost((_) => response);
      try {
        await fixedClient().authenticate(username: 'u', password: 'p');
      } on InstapaperAuthException catch (e) {
        return e.kind;
      }
      fail('expected an InstapaperAuthException');
    }

    test('401 is wrong credentials', () async {
      expect(
        await kindFor(
          http.Response('<html><title>401: Unauthorized</title></html>', 401),
        ),
        InstapaperFailureKind.invalidCredentials,
      );
    });

    test('403 for an old timestamp is the clock, not the password', () async {
      expect(
        await kindFor(
          http.Response(
            '<html><title>403: Expired timestamp: given 1 and now 2 has a '
            'greater difference than threshold 300</title></html>',
            403,
          ),
        ),
        InstapaperFailureKind.clockSkew,
      );
    });

    test('403 for an unapproved application is not the password', () async {
      expect(
        await kindFor(
          http.Response(
            '<html><title>403: Application is not approved</title></html>',
            403,
          ),
        ),
        InstapaperFailureKind.suspended,
      );
    });

    test('a bare 403 is not reported as wrong credentials', () async {
      expect(
        await kindFor(http.Response('', 403)),
        InstapaperFailureKind.unknown,
      );
    });
  });

  group('device clock', () {
    const expired =
        '<html><title>403: Expired timestamp: given 1 and now 2 has a '
        'greater difference than threshold 300</title></html>';
    // The server's clock is a day ahead of the device's.
    const serverDate = 'Wed, 15 Nov 2023 22:13:20 GMT';
    const serverSeconds = 1700000000 + 86400;

    test(
      'a request refused for its timestamp is retried on server time',
      () async {
        var calls = 0;
        stubPost((_) {
          calls++;
          return calls == 1
              ? http.Response(expired, 403, headers: {'date': serverDate})
              : http.Response(userJson, 200, headers: {'date': serverDate});
        });
        final c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');

        final user = await c.verifyCredentials();

        expect(user.userId, 123);
        final headers = sentAuthHeaders();
        expect(headers, hasLength(2));
        expect(oauthParam(headers[0], 'oauth_timestamp'), '1700000000');
        expect(oauthParam(headers[1], 'oauth_timestamp'), '$serverSeconds');
      },
    );

    test(
      'the learned clock applies to later calls and to progress times',
      () async {
        var calls = 0;
        stubPost((_) {
          calls++;
          return calls == 1
              ? http.Response(expired, 403, headers: {'date': serverDate})
              : http.Response('[]', 200, headers: {'date': serverDate});
        });
        final c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');
        await c.getBookmarks();

        await c.updateReadProgress(
          bookmarkId: 7,
          progress: 0.5,
          timestampSeconds: 1700000000 - 60,
        );

        expect(calls, 3);
        final headers = sentAuthHeaders();
        expect(oauthParam(headers[2], 'oauth_timestamp'), '$serverSeconds');
      },
    );

    test('a refusal with the right clock is not retried', () async {
      var calls = 0;
      stubPost((_) {
        calls++;
        return http.Response(
          '',
          403,
          headers: {'date': 'Tue, 14 Nov 2023 22:13:25 GMT'},
        );
      });
      final c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');

      await expectLater(
        c.verifyCredentials(),
        throwsA(
          isA<InstapaperApiException>().having(
            (e) => e.kind,
            'kind',
            InstapaperFailureKind.unauthorized,
          ),
        ),
      );
      expect(calls, 1);
    });

    test('a slow clock is not mistaken for a revoked token', () async {
      // No usable Date header, so no retry: the failure must still not be
      // "unauthorized", which signs the reader out.
      stubPost((_) => http.Response(expired, 403));
      final c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');

      await expectLater(
        c.verifyCredentials(),
        throwsA(
          isA<InstapaperApiException>()
              .having((e) => e.kind, 'kind', InstapaperFailureKind.clockSkew)
              .having((e) => e.isTransient, 'isTransient', isTrue),
        ),
      );
    });

    test('a bad signature is not a clock problem, though its page quotes the '
        'timestamp', () async {
      // The page as Instapaper sends it: the whole signature base string,
      // oauth_timestamp and oauth_nonce included. The fixtures above stop
      // short of those, which hid that "timestamp" was matched first.
      const invalidSignature =
          '<html><title>403: Invalid signature. Expected signature base '
          'string: POST&amp;https%3A%2F%2Fwww.instapaper.com%2Fapi%2F1%2F'
          'account%2Fverify_credentials&amp;oauth_consumer_key%3Dk%26'
          'oauth_nonce%3Dabc%26oauth_signature_method%3DHMAC-SHA1%26'
          'oauth_timestamp%3D1700000000%26oauth_token%3Dtok%26'
          'oauth_version%3D1.0</title></html>';
      stubPost((_) => http.Response(invalidSignature, 403));
      final c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');

      await expectLater(
        c.verifyCredentials(),
        throwsA(
          isA<InstapaperApiException>().having(
            (e) => e.kind,
            'kind',
            InstapaperFailureKind.unexpectedResponse,
          ),
        ),
      );

      // And at sign-in, where the wrong answer told the reader to fix
      // their date and time.
      Object? caught;
      try {
        await fixedClient().authenticate(username: 'u', password: 'p');
      } on InstapaperAuthException catch (e) {
        caught = e;
      }
      expect(
        (caught! as InstapaperAuthException).kind,
        InstapaperFailureKind.unexpectedResponse,
      );
    });

    test(
      'a 403 page that is not Instapaper\'s is not a revoked token',
      () async {
        // A filter or proxy in between answering for Instapaper. Reading it
        // as "unauthorized" signed the reader out and deleted the tokens.
        stubPost(
          (_) => http.Response(
            '<html><head><title>403 Forbidden</title></head>'
            '<body>Access to this site is blocked.</body></html>',
            403,
          ),
        );
        final c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');

        await expectLater(
          c.verifyCredentials(),
          throwsA(
            isA<InstapaperApiException>()
                .having(
                  (e) => e.kind,
                  'kind',
                  InstapaperFailureKind.unexpectedResponse,
                )
                .having((e) => e.isTransient, 'isTransient', isTrue),
          ),
        );
      },
    );

    test('a bad signature is not mistaken for a revoked token', () async {
      stubPost(
        (_) => http.Response(
          '<html><title>403: Invalid signature. Expected signature base '
          'string: POST&amp;https%3A%2F%2F...</title></html>',
          403,
        ),
      );
      final c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');

      await expectLater(
        c.verifyCredentials(),
        throwsA(
          isA<InstapaperApiException>().having(
            (e) => e.kind,
            'kind',
            isNot(InstapaperFailureKind.unauthorized),
          ),
        ),
      );
    });
  });

  group('transport failures', () {
    Future<InstapaperApiException> failureOf(Future<Object?> call) async {
      try {
        await call;
      } on InstapaperApiException catch (e) {
        return e;
      }
      fail('expected an InstapaperApiException');
    }

    test(
      'a request that never answers times out as a network failure',
      () async {
        final never = Completer<http.Response>();
        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) => never.future);
        final c = fixedClient(requestTimeout: const Duration(milliseconds: 20))
          ..setTokens(token: 'tok', tokenSecret: 'sec');

        final failure = await failureOf(c.verifyCredentials());

        expect(failure.kind, InstapaperFailureKind.network);
        expect(failure.isTransient, isTrue);
      },
    );

    test('socket, TLS and client errors are network failures', () async {
      final c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');
      for (final error in <Object>[
        const SocketException('unreachable'),
        const HandshakeException('bad certificate'),
        http.ClientException('connection closed'),
      ]) {
        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenThrow(error);

        final failure = await failureOf(c.getBookmarks());

        expect(failure.kind, InstapaperFailureKind.network, reason: '$error');
        expect(failure.errorCode, 0);
      }
    });
  });

  group('text encoding', () {
    test('article text is read as UTF-8 whatever the header says', () async {
      const article = '<p>“Café” — naïve façade… 日本語</p>';
      stubPost(
        (_) => http.Response.bytes(
          utf8.encode(article),
          200,
          // No charset: package:http would decode this as Latin-1.
          headers: {'content-type': 'text/html'},
        ),
      );
      final c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');

      expect(await c.getBookmarkText(bookmarkId: 1), article);
    });

    test('bookmark titles are read as UTF-8', () async {
      stubPost(
        (_) => http.Response.bytes(
          utf8.encode(
            '[{"type":"bookmark","bookmark_id":1,"title":"Señor “Ünïcode”"}]',
          ),
          200,
          headers: {'content-type': 'text/html'},
        ),
      );
      final c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');

      expect((await c.getBookmarks()).single.title, 'Señor “Ünïcode”');
    });
  });

  group('bookmark list', () {
    late InstapaperClient c;
    setUp(() {
      c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');
    });

    test('asks for the most the API allows by default', () async {
      stubPost((_) => http.Response('[]', 200));

      await c.getBookmarks();

      expect(sentBodies().single, {'limit': '500', 'folder_id': 'unread'});
    });

    test('reads fields whatever type they arrive in', () async {
      stubPost(
        (_) => http.Response(
          jsonEncode([
            {
              'type': 'bookmark',
              'bookmark_id': '42',
              'url': 'https://www.example.com/a',
              'title': null,
              'progress': '0.25',
              'progress_timestamp': 1700000000.0,
              'time': '1699000000',
              'starred': 1,
            },
          ]),
          200,
        ),
      );

      final bookmark = (await c.getBookmarks()).single;

      expect(bookmark.bookmarkId, 42);
      expect(bookmark.title, '');
      expect(bookmark.progress, 0.25);
      expect(bookmark.progressTimestamp, 1700000000);
      expect(bookmark.time, 1699000000);
      expect(bookmark.starred, isTrue);
    });

    test('one unreadable entry does not fail the list', () async {
      stubPost(
        (_) => http.Response(
          jsonEncode([
            {'type': 'meta'},
            {'type': 'user', 'user_id': 9, 'username': 'reader'},
            {'type': 'bookmark', 'bookmark_id': 1, 'title': 'First'},
            {'type': 'bookmark', 'title': 'No id'},
            'not an object',
            {'type': 'highlight', 'highlight_id': 5, 'bookmark_id': 1},
            {'type': 'bookmark', 'bookmark_id': 2, 'title': 'Second'},
          ]),
          200,
        ),
      );

      final page = await c.fetchBookmarks();

      expect(page.bookmarks.map((b) => b.title), ['First', 'Second']);
      expect(page.skipped, 1);
      expect(page.user?.userId, 9);
      expect(page.user?.username, 'reader');
    });

    test('reads the object form with the list under "bookmarks"', () async {
      stubPost(
        (_) => http.Response(
          jsonEncode({
            'user': {'type': 'user', 'user_id': 9, 'username': 'reader'},
            'bookmarks': [
              {'type': 'bookmark', 'bookmark_id': 1, 'title': 'First'},
            ],
            'highlights': <Object>[],
            'delete_ids': <Object>[],
          }),
          200,
        ),
      );

      final page = await c.fetchBookmarks();

      expect(page.bookmarks.single.bookmarkId, 1);
      expect(page.user?.username, 'reader');
    });

    test('a page that is not JSON is a temporary failure', () async {
      stubPost((_) => http.Response('<html>Bad gateway</html>', 200));

      await expectLater(
        c.getBookmarks(),
        throwsA(
          isA<InstapaperApiException>()
              .having(
                (e) => e.kind,
                'kind',
                InstapaperFailureKind.unexpectedResponse,
              )
              .having((e) => e.isTransient, 'isTransient', isTrue),
        ),
      );
    });
  });

  group('reading progress', () {
    late InstapaperClient c;
    setUp(() {
      c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');
      stubPost((_) => http.Response('[]', 200));
    });

    test('is sent with the time it was recorded', () async {
      await c.updateReadProgress(
        bookmarkId: 7,
        progress: 0.4567891,
        timestampSeconds: 1699990000,
      );

      expect(sentBodies().single, {
        'bookmark_id': '7',
        'progress': '0.4568',
        'progress_timestamp': '1699990000',
      });
    });

    test('falls back to now when no time is given', () async {
      await c.updateReadProgress(bookmarkId: 7, progress: 2);

      final body = sentBodies().single;
      expect(body['progress'], '1.0000');
      expect(body['progress_timestamp'], '1700000000');
    });
  });

  group('error codes', () {
    late InstapaperClient c;
    setUp(() {
      c = fixedClient()..setTokens(token: 'tok', tokenSecret: 'sec');
    });

    Future<InstapaperApiException> textFailure(
      int code, {
      int status = 400,
    }) async {
      stubPost(
        (_) => http.Response(
          '[{"type":"error","error_code":$code,"message":"developer text"}]',
          status,
        ),
      );
      try {
        await c.getBookmarkText(bookmarkId: 1);
      } on InstapaperApiException catch (e) {
        return e;
      }
      fail('expected an InstapaperApiException');
    }

    test(
      'text service refusals (1044, 1045, 1046) are told apart from failures',
      () async {
        for (final code in [1044, 1045, 1046]) {
          final failure = await textFailure(code);
          expect(failure.kind, InstapaperFailureKind.textAccessDenied);
          expect(failure.errorCode, code);
          expect(failure.isTransient, isFalse);
        }
      },
    );

    test('1550 means Instapaper has no text for the article', () async {
      final failure = await textFailure(1550);
      expect(failure.kind, InstapaperFailureKind.textUnavailable);
      expect(failure.isTransient, isFalse);
    });

    test('rate limits (1040, 1047) and 1500 are temporary', () async {
      for (final code in [1040, 1047, 1500]) {
        final failure = await textFailure(code);
        expect(failure.isTransient, isTrue, reason: '$code');
        expect(failure.isPermanent, isFalse, reason: '$code');
      }
    });

    test('1241 means the bookmark is gone, for good', () async {
      final failure = await textFailure(1241);
      expect(failure.kind, InstapaperFailureKind.bookmarkNotFound);
      expect(failure.isPermanent, isTrue);
    });

    test('1041 is the Premium requirement', () async {
      expect(
        (await textFailure(1041, status: 403)).kind,
        InstapaperFailureKind.premiumRequired,
      );
    });

    test("the API's developer message is not passed on", () async {
      expect(
        (await textFailure(1550)).toString(),
        isNot(contains('developer')),
      );
    });

    test('server errors without a code are temporary', () async {
      stubPost((_) => http.Response('<html>502</html>', 502));

      await expectLater(
        c.archiveBookmark(bookmarkId: 1),
        throwsA(
          isA<InstapaperApiException>()
              .having(
                (e) => e.kind,
                'kind',
                InstapaperFailureKind.serviceUnavailable,
              )
              .having((e) => e.errorCode, 'errorCode', 502),
        ),
      );
    });
  });
}
