import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:runthru/features/content/services/instapaper_auth_service.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';

class MockHttpClient extends Mock implements http.Client {}

class MemoryTokenStore implements InstapaperTokenStore {
  InstapaperTokenPair? tokens;
  final writes = <InstapaperTokenPair>[];

  @override
  Future<InstapaperTokenPair?> loadTokens() async => tokens;

  @override
  Future<void> saveTokens(InstapaperTokenPair tokens) async {
    this.tokens = tokens;
    writes.add(tokens);
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

  late MockHttpClient mockHttp;
  late MemoryTokenStore store;
  late InstapaperAuthService service;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    mockHttp = MockHttpClient();
    store = MemoryTokenStore();
    service = InstapaperAuthService(
      client: InstapaperClient(httpClient: mockHttp, config: testConfig),
      tokenStore: store,
    );
  });

  test('save, load, and delete token store values', () async {
    const tokens = InstapaperTokenPair(token: 'tok', tokenSecret: 'sec');

    await store.saveTokens(tokens);
    expect(await store.loadTokens(), same(tokens));

    await store.deleteTokens();
    expect(await store.loadTokens(), isNull);
  });

  test('password is exchanged but never persisted', () async {
    when(
      () => mockHttp.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((invocation) async {
      final uri = invocation.positionalArguments.first as Uri;
      if (uri.path == '/api/1/oauth/access_token') {
        return http.Response(
          'oauth_token=new_token&oauth_token_secret=new_secret',
          200,
        );
      }
      return http.Response(
        '[{"type":"user","user_id":123,"username":"TestUser"}]',
        200,
      );
    });

    final user = await service.connectWithLegacyCredentials(
      username: 'user@test.com',
      password: 'raw-password',
    );

    expect(user.userId, equals(123));
    expect(store.tokens?.token, equals('new_token'));
    expect(store.tokens?.tokenSecret, equals('new_secret'));
    expect(store.writes, hasLength(1));
    expect(
      '${store.tokens?.token}${store.tokens?.tokenSecret}',
      isNot(contains('raw-password')),
    );
  });

  test(
    'restore verifies stored tokens and returns authenticated user',
    () async {
      store.tokens = const InstapaperTokenPair(
        token: 'tok',
        tokenSecret: 'sec',
      );
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '[{"type":"user","user_id":456,"username":"Restored"}]',
          200,
        ),
      );

      final user = await service.restoreSession();

      expect(user?.userId, equals(456));
      expect(service.client.isAuthenticated, isTrue);
    },
  );

  test('restore deletes invalid stored tokens', () async {
    store.tokens = const InstapaperTokenPair(token: 'tok', tokenSecret: 'sec');
    when(
      () => mockHttp.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async => http.Response('', 401));

    final user = await service.restoreSession();

    expect(user, isNull);
    expect(store.tokens, isNull);
    expect(service.client.isAuthenticated, isFalse);
  });

  test(
    'restore does not delete tokens when consumer config is missing',
    () async {
      final tokenStore = MemoryTokenStore()
        ..tokens = const InstapaperTokenPair(token: 'tok', tokenSecret: 'sec');
      final missingConfigService = InstapaperAuthService(
        client: InstapaperClient(
          httpClient: mockHttp,
          config: const InstapaperClientConfig(
            consumerKey: '',
            consumerSecret: '',
          ),
        ),
        tokenStore: tokenStore,
      );

      expect(
        missingConfigService.restoreSession,
        throwsA(
          isA<InstapaperAuthException>().having(
            (e) => e.kind,
            'kind',
            InstapaperFailureKind.missingConfiguration,
          ),
        ),
      );
      expect(tokenStore.tokens?.token, equals('tok'));
    },
  );
}
