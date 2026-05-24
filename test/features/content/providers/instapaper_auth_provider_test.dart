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
  }) {
    final service = InstapaperAuthService(
      client: InstapaperClient(httpClient: httpClient, config: config),
      tokenStore: tokenStore,
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
}
