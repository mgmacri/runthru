import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/services/instapaper_auth_service.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';

class MockHttpClient extends Mock implements http.Client {}

class MemoryTokenStore implements InstapaperTokenStore {
  InstapaperTokenPair? tokens;

  @override
  Future<InstapaperTokenPair?> loadTokens() async => tokens;

  @override
  Future<void> saveTokens(InstapaperTokenPair tokens) async {
    this.tokens = tokens;
  }

  @override
  Future<void> deleteTokens() async {
    tokens = null;
  }
}

class MemoryAccountStore implements InstapaperAccountStore {
  InstapaperUser? user;

  @override
  Future<InstapaperUser?> loadUser() async => user;

  @override
  Future<void> saveUser(InstapaperUser user) async => this.user = user;

  @override
  Future<void> deleteUser() async => user = null;
}

/// A token store that records whether it was ever read.
class WatchedTokenStore extends MemoryTokenStore {
  int loads = 0;

  @override
  Future<InstapaperTokenPair?> loadTokens() async {
    loads++;
    return super.loadTokens();
  }
}

void main() {
  const testConfig = InstapaperClientConfig(
    consumerKey: 'consumer_key',
    consumerSecret: 'consumer_secret',
  );

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  ProviderContainer containerFor({
    required http.Client httpClient,
    required MemoryTokenStore tokenStore,
    InstapaperClientConfig config = testConfig,
    Future<InstapaperUser> Function()? officialSignIn,
    InstapaperAccountStore? accountStore,
  }) {
    final service = InstapaperAuthService(
      client: InstapaperClient(httpClient: httpClient, config: config),
      tokenStore: tokenStore,
      accountStore: accountStore,
      officialSignIn: officialSignIn,
    );
    return ProviderContainer(
      overrides: [instapaperAuthServiceProvider.overrideWithValue(service)],
    );
  }

  test('starts unauthenticated when no secure tokens exist', () async {
    final container = containerFor(
      httpClient: MockHttpClient(),
      tokenStore: MemoryTokenStore(),
    );
    addTearDown(container.dispose);

    expect(
      container.read(instapaperAuthProvider),
      isA<InstapaperAuthChecking>(),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(instapaperAuthProvider),
      isA<InstapaperAuthUnauthenticated>(),
    );
  });

  test('transitions to authenticated after successful login', () async {
    final mockHttp = MockHttpClient();
    when(
      () => mockHttp.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((invocation) async {
      final uri = invocation.positionalArguments.first as Uri;
      if (uri.path == '/api/1/oauth/access_token') {
        return http.Response('oauth_token=tok&oauth_token_secret=sec', 200);
      }
      return http.Response(
        '[{"type":"user","user_id":123,"username":"TestUser"}]',
        200,
      );
    });
    final tokenStore = MemoryTokenStore();
    final container = containerFor(
      httpClient: mockHttp,
      tokenStore: tokenStore,
    );
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    await container
        .read(instapaperAuthProvider.notifier)
        .login(username: 'user@test.com', password: 'password');

    final state = container.read(instapaperAuthProvider);
    expect(state, isA<InstapaperAuthAuthenticated>());
    expect((state as InstapaperAuthAuthenticated).user.userId, equals(123));
    expect(tokenStore.tokens?.token, equals('tok'));
  });

  test('connect attempts official auth before legacy fallback', () async {
    var officialAttempts = 0;
    final container = containerFor(
      httpClient: MockHttpClient(),
      tokenStore: MemoryTokenStore(),
      officialSignIn: () async {
        officialAttempts++;
        throw const InstapaperAuthException(
          kind: InstapaperFailureKind.officialAuthUnavailable,
          message: 'unavailable',
        );
      },
    );
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    await container.read(instapaperAuthProvider.notifier).connect();

    expect(officialAttempts, 1);
    expect(
      container.read(instapaperAuthProvider),
      isA<InstapaperAuthLegacyFallbackRequired>(),
    );
  });

  test(
    'official auth success authenticates without legacy credentials',
    () async {
      final container = containerFor(
        httpClient: MockHttpClient(),
        tokenStore: MemoryTokenStore(),
        officialSignIn: () async =>
            const InstapaperUser(userId: 9, username: 'OfficialUser'),
      );
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero);

      await container.read(instapaperAuthProvider.notifier).connect();

      final state = container.read(instapaperAuthProvider);
      expect(state, isA<InstapaperAuthAuthenticated>());
      expect(
        (state as InstapaperAuthAuthenticated).user.username,
        'OfficialUser',
      );
    },
  );

  test(
    'missing consumer config becomes setup error, not invalid credentials',
    () async {
      final mockHttp = MockHttpClient();
      final container = containerFor(
        httpClient: mockHttp,
        tokenStore: MemoryTokenStore(),
        config: const InstapaperClientConfig(
          consumerKey: '',
          consumerSecret: '',
        ),
      );
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(instapaperAuthProvider.notifier)
          .login(username: 'user@test.com', password: 'password');

      final state = container.read(instapaperAuthProvider);
      expect(state, isA<InstapaperAuthError>());
      expect(
        (state as InstapaperAuthError).kind,
        InstapaperFailureKind.missingConfiguration,
      );
      expect(state.message, contains('dart-define'));
      verifyNever(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    },
  );

  test('logout deletes local tokens and clears auth state', () async {
    final tokenStore = MemoryTokenStore()
      ..tokens = const InstapaperTokenPair(token: 'tok', tokenSecret: 'sec');
    final mockHttp = MockHttpClient();
    when(
      () => mockHttp.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer(
      (_) async => http.Response(
        '[{"type":"user","user_id":123,"username":"TestUser"}]',
        200,
      ),
    );
    final container = containerFor(
      httpClient: mockHttp,
      tokenStore: tokenStore,
    );
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    await container.read(instapaperAuthProvider.notifier).logout();

    expect(tokenStore.tokens, isNull);
    expect(
      container.read(instapaperAuthProvider),
      isA<InstapaperAuthUnauthenticated>(),
    );
  });

  // ── B-47 ──────────────────────────────────────────────────────────────────

  group('saved connection', () {
    const savedTokens = InstapaperTokenPair(token: 'tok', tokenSecret: 'sec');

    test('launching offline shows the connection, not an error', () async {
      final mockHttp = MockHttpClient();
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenThrow(http.ClientException('Failed host lookup'));
      final container = containerFor(
        httpClient: mockHttp,
        tokenStore: MemoryTokenStore()..tokens = savedTokens,
        accountStore: MemoryAccountStore()
          ..user = const InstapaperUser(userId: 7, username: 'reader'),
      );
      addTearDown(container.dispose);

      container.read(instapaperAuthProvider);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(instapaperAuthProvider);
      expect(state, isA<InstapaperAuthAuthenticated>());
      expect((state as InstapaperAuthAuthenticated).user.username, 'reader');
      expect(container.read(instapaperAuthProvider.notifier).client, isNotNull);
      verifyNever(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });

    test(
      'launching offline before any account was remembered still connects',
      () async {
        final mockHttp = MockHttpClient();
        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenThrow(http.ClientException('Failed host lookup'));
        final container = containerFor(
          httpClient: mockHttp,
          tokenStore: MemoryTokenStore()..tokens = savedTokens,
          accountStore: MemoryAccountStore(),
        );
        addTearDown(container.dispose);

        container.read(instapaperAuthProvider);
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(instapaperAuthProvider),
          isA<InstapaperAuthAuthenticated>(),
        );
      },
    );

    test('a refused connection signs out and says why', () async {
      final tokenStore = MemoryTokenStore()..tokens = savedTokens;
      final accounts = MemoryAccountStore()
        ..user = const InstapaperUser(userId: 7, username: 'reader');
      final container = containerFor(
        httpClient: MockHttpClient(),
        tokenStore: tokenStore,
        accountStore: accounts,
      );
      addTearDown(container.dispose);
      container.read(instapaperAuthProvider);
      await Future<void>.delayed(Duration.zero);

      await container.read(instapaperAuthProvider.notifier).sessionExpired();

      final state = container.read(instapaperAuthProvider);
      expect(state, isA<InstapaperAuthError>());
      expect(
        (state as InstapaperAuthError).kind,
        InstapaperFailureKind.unauthorized,
      );
      expect(state.message, 'Instapaper needs you to sign in again.');
      expect(tokenStore.tokens, isNull);
      expect(accounts.user, isNull);
      expect(container.read(instapaperAuthProvider.notifier).client, isNull);
    });

    test(
      'checkSession signs out only when Instapaper refuses the token',
      () async {
        final mockHttp = MockHttpClient();
        var status = 502;
        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('', status));
        final tokenStore = MemoryTokenStore()..tokens = savedTokens;
        final container = containerFor(
          httpClient: mockHttp,
          tokenStore: tokenStore,
          accountStore: MemoryAccountStore()
            ..user = const InstapaperUser(userId: 7, username: 'reader'),
        );
        addTearDown(container.dispose);
        container.read(instapaperAuthProvider);
        await Future<void>.delayed(Duration.zero);
        final notifier = container.read(instapaperAuthProvider.notifier);

        // Instapaper is having trouble: that says nothing about the token.
        await notifier.checkSession();
        expect(
          container.read(instapaperAuthProvider),
          isA<InstapaperAuthAuthenticated>(),
        );
        expect(tokenStore.tokens, isNotNull);

        // Instapaper refuses the token outright.
        status = 403;
        await notifier.checkSession();
        expect(
          container.read(instapaperAuthProvider),
          isA<InstapaperAuthError>(),
        );
        expect(tokenStore.tokens, isNull);
      },
    );

    test('sessionExpired does nothing when nobody is connected', () async {
      final container = containerFor(
        httpClient: MockHttpClient(),
        tokenStore: MemoryTokenStore(),
      );
      addTearDown(container.dispose);
      container.read(instapaperAuthProvider);
      await Future<void>.delayed(Duration.zero);

      await container.read(instapaperAuthProvider.notifier).sessionExpired();

      expect(
        container.read(instapaperAuthProvider),
        isA<InstapaperAuthUnauthenticated>(),
      );
    });

    test('a changed username is shown and remembered', () async {
      final accounts = MemoryAccountStore()
        ..user = const InstapaperUser(userId: 7, username: 'old-name');
      final container = containerFor(
        httpClient: MockHttpClient(),
        tokenStore: MemoryTokenStore()..tokens = savedTokens,
        accountStore: accounts,
      );
      addTearDown(container.dispose);
      container.read(instapaperAuthProvider);
      await Future<void>.delayed(Duration.zero);

      container
          .read(instapaperAuthProvider.notifier)
          .updateUser(const InstapaperUser(userId: 7, username: 'new-name'));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(instapaperAuthProvider);
      expect((state as InstapaperAuthAuthenticated).user.username, 'new-name');
      expect(accounts.user?.username, 'new-name');
    });

    test('dismissError returns a failed sign-in to "not connected"', () async {
      final mockHttp = MockHttpClient();
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('', 401));
      final container = containerFor(
        httpClient: mockHttp,
        tokenStore: MemoryTokenStore(),
      );
      addTearDown(container.dispose);
      container.read(instapaperAuthProvider);
      await Future<void>.delayed(Duration.zero);
      final notifier = container.read(instapaperAuthProvider.notifier);

      await notifier.login(username: 'reader', password: 'wrong');
      final failed = container.read(instapaperAuthProvider);
      expect(failed, isA<InstapaperAuthError>());
      expect(
        (failed as InstapaperAuthError).kind,
        InstapaperFailureKind.invalidCredentials,
      );
      expect(notifier.client, isNull);

      notifier.dismissError();

      expect(
        container.read(instapaperAuthProvider),
        isA<InstapaperAuthUnauthenticated>(),
      );
    });
  });

  group('a build without the consumer key', () {
    const noKey = InstapaperClientConfig(consumerKey: '', consumerSecret: '');

    test('reports Instapaper as unavailable and reads no storage', () async {
      final tokenStore = WatchedTokenStore()
        ..tokens = const InstapaperTokenPair(token: 'tok', tokenSecret: 'sec');
      final container = containerFor(
        httpClient: MockHttpClient(),
        tokenStore: tokenStore,
        config: noKey,
      );
      addTearDown(container.dispose);

      expect(container.read(instapaperAvailableProvider), isFalse);
      expect(
        container.read(instapaperAuthProvider),
        isA<InstapaperAuthUnauthenticated>(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(tokenStore.loads, 0);
      // The tokens stay for a build that has the key.
      expect(tokenStore.tokens, isNotNull);
    });

    test('a build with the key reports Instapaper as available', () {
      final container = containerFor(
        httpClient: MockHttpClient(),
        tokenStore: MemoryTokenStore(),
      );
      addTearDown(container.dispose);

      expect(container.read(instapaperAvailableProvider), isTrue);
    });
  });
}
