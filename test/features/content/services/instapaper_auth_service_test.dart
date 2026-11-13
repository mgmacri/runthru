import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

class MemoryAccountStore implements InstapaperAccountStore {
  InstapaperUser? user;

  @override
  Future<InstapaperUser?> loadUser() async => user;

  @override
  Future<void> saveUser(InstapaperUser user) async => this.user = user;

  @override
  Future<void> deleteUser() async => user = null;
}

/// A token store whose writes fail, as a broken keystore would.
class UnwritableTokenStore extends MemoryTokenStore {
  @override
  Future<void> saveTokens(InstapaperTokenPair tokens) async {
    throw const InstapaperSecureStorageException('write failed');
  }
}

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

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

  // ── B-47: the saved connection ────────────────────────────────────────────

  group('restore with a remembered account', () {
    late MemoryAccountStore accounts;

    InstapaperAuthService serviceWith(MemoryTokenStore tokens) =>
        InstapaperAuthService(
          client: InstapaperClient(httpClient: mockHttp, config: testConfig),
          tokenStore: tokens,
          accountStore: accounts,
        );

    void stubPost(http.Response Function(Uri uri) answer) {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (invocation) async =>
            answer(invocation.positionalArguments.first as Uri),
      );
    }

    void verifyNoRequests() => verifyNever(
      () => mockHttp.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    );

    setUp(() {
      accounts = MemoryAccountStore();
      store.tokens = const InstapaperTokenPair(
        token: 'tok',
        tokenSecret: 'sec',
      );
    });

    test('needs no network', () async {
      accounts.user = const InstapaperUser(userId: 7, username: 'reader');
      final service = serviceWith(store);

      final user = await service.restoreSession();

      expect(user?.userId, 7);
      expect(user?.username, 'reader');
      expect(service.client.isAuthenticated, isTrue);
      verifyNoRequests();
    });

    test('asks Instapaper once when no account is remembered yet', () async {
      stubPost(
        (_) => http.Response(
          '[{"type":"user","user_id":456,"username":"Restored"}]',
          200,
        ),
      );
      final service = serviceWith(store);

      final user = await service.restoreSession();

      expect(user?.userId, 456);
      expect(accounts.user?.userId, 456);
      expect(accounts.user?.username, 'Restored');
    });

    test('stays connected when Instapaper cannot be reached', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenThrow(http.ClientException('Failed host lookup'));
      final service = serviceWith(store);

      final user = await service.restoreSession();

      expect(user, same(InstapaperAuthService.unverifiedUser));
      expect(store.tokens?.token, 'tok');
      expect(service.client.isAuthenticated, isTrue);
    });

    test('a slow device clock does not sign the reader out', () async {
      // Seen from the live API: 403 with this page for a stale timestamp.
      stubPost(
        (_) => http.Response(
          '<html><title>403: Expired timestamp: given 1 and now 2 has a '
          'greater difference than threshold 300</title></html>',
          403,
        ),
      );
      final service = serviceWith(store);

      final user = await service.restoreSession();

      expect(user, isNotNull);
      expect(store.tokens?.token, 'tok');
    });

    test('a refused token forgets the tokens and the account', () async {
      stubPost((_) => http.Response('', 403));
      final service = serviceWith(store);

      final user = await service.restoreSession();

      expect(user, isNull);
      expect(store.tokens, isNull);
      expect(accounts.user, isNull);
      expect(service.client.isAuthenticated, isFalse);
    });

    test('logout forgets the tokens and the account', () async {
      accounts.user = const InstapaperUser(userId: 7, username: 'reader');
      final service = serviceWith(store);
      await service.restoreSession();

      await service.logout();

      expect(store.tokens, isNull);
      expect(accounts.user, isNull);
      expect(service.client.isAuthenticated, isFalse);
    });

    test('signing in remembers the account', () async {
      store.tokens = null;
      stubPost(
        (uri) => uri.path == '/api/1/oauth/access_token'
            ? http.Response('oauth_token=t&oauth_token_secret=s', 200)
            : http.Response(
                '[{"type":"user","user_id":9,"username":"reader@example.com"}]',
                200,
              ),
      );
      final service = serviceWith(store);

      final user = await service.connectWithLegacyCredentials(
        username: 'reader@example.com',
        password: 'pw',
      );

      expect(user.userId, 9);
      expect(accounts.user?.userId, 9);
      expect(store.tokens?.token, 't');
    });

    test('a sign-in whose follow-up lookup fails still connects', () async {
      // The tokens were issued; making the reader type the password again
      // because the next request hiccuped would be wrong.
      store.tokens = null;
      stubPost(
        (uri) => uri.path == '/api/1/oauth/access_token'
            ? http.Response('oauth_token=t&oauth_token_secret=s', 200)
            : http.Response('<html>502</html>', 502),
      );
      final service = serviceWith(store);

      final user = await service.connectWithLegacyCredentials(
        username: 'reader@example.com',
        password: 'pw',
      );

      expect(user.username, 'reader@example.com');
      expect(store.tokens?.token, 't');
      expect(service.client.isAuthenticated, isTrue);
      // Not remembered as an account: its ID is not known yet.
      expect(accounts.user, isNull);
    });

    test('a sign-in that cannot be saved leaves nothing connected', () async {
      stubPost(
        (uri) => uri.path == '/api/1/oauth/access_token'
            ? http.Response('oauth_token=t&oauth_token_secret=s', 200)
            : http.Response(
                '[{"type":"user","user_id":9,"username":"reader"}]',
                200,
              ),
      );
      final service = serviceWith(UnwritableTokenStore());

      await expectLater(
        service.connectWithLegacyCredentials(username: 'reader', password: ''),
        throwsA(isA<InstapaperSecureStorageException>()),
      );
      expect(service.client.isAuthenticated, isFalse);
    });

    test(
      'a sign-in refused after the token exchange leaves nothing connected',
      () async {
        store.tokens = null;
        stubPost(
          (uri) => uri.path == '/api/1/oauth/access_token'
              ? http.Response('oauth_token=t&oauth_token_secret=s', 200)
              : http.Response('', 403),
        );
        final service = serviceWith(store);

        await expectLater(
          service.connectWithLegacyCredentials(
            username: 'reader',
            password: '',
          ),
          throwsA(isA<InstapaperApiException>()),
        );
        expect(service.client.isAuthenticated, isFalse);
        expect(store.tokens, isNull);
      },
    );
  });

  group('SecureInstapaperTokenStore', () {
    late MockSecureStorage storage;

    setUp(() => storage = MockSecureStorage());

    test('tokens that can no longer be decrypted are discarded', () async {
      // App data restored from a backup onto another phone: the values are
      // there, the key that encrypted them is not.
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenThrow(PlatformException(code: 'Exception', message: 'BadPadding'));
      when(
        () => storage.delete(key: any(named: 'key')),
      ).thenAnswer((_) async {});

      final tokens = await SecureInstapaperTokenStore(
        storage: storage,
      ).loadTokens();

      expect(tokens, isNull);
      verify(() => storage.delete(key: instapaperOAuthTokenKey)).called(1);
      verify(
        () => storage.delete(key: instapaperOAuthTokenSecretKey),
      ).called(1);
    });

    test(
      'the plugin\'s own report of a failed decryption is recognised',
      () async {
        // What flutter_secure_storage 9 sends from Android: the Java stack
        // trace in `details`.
        when(() => storage.read(key: any(named: 'key'))).thenThrow(
          PlatformException(
            code: 'Exception encountered',
            message: 'read',
            details:
                'javax.crypto.BadPaddingException: error:1e000065:Cipher '
                'functions:OPENSSL_internal:BAD_DECRYPT\n'
                '\tat com.android.org.conscrypt.NativeCrypto.EVP_CipherFinal_ex',
          ),
        );
        when(
          () => storage.delete(key: any(named: 'key')),
        ).thenAnswer((_) async {});

        final tokens = await SecureInstapaperTokenStore(
          storage: storage,
        ).loadTokens();

        expect(tokens, isNull);
        verify(() => storage.delete(key: instapaperOAuthTokenKey)).called(1);
      },
    );

    test('a read that fails for the moment keeps the saved tokens', () async {
      // The tokens used to be deleted on any failed read, so one bad moment
      // in secure storage made the reader type their password again.
      for (final failure in [
        // Android: the cipher could not be set up (keystore busy).
        PlatformException(
          code: 'Exception encountered',
          message: 'read',
          details:
              'java.lang.NullPointerException: Attempt to invoke interface '
              'method StorageCipher.decrypt(byte[]) on a null object reference',
        ),
        // iOS: the keychain is locked (errSecInteractionNotAllowed).
        PlatformException(
          code: 'Unexpected security result code',
          message: 'Code: -25308, Message: User interaction is not allowed.',
        ),
        StateError('anything else'),
      ]) {
        final storage = MockSecureStorage();
        when(() => storage.read(key: any(named: 'key'))).thenThrow(failure);

        await expectLater(
          SecureInstapaperTokenStore(storage: storage).loadTokens,
          throwsA(isA<InstapaperSecureStorageException>()),
          reason: '$failure',
        );
        verifyNever(() => storage.delete(key: any(named: 'key')));
      }
    });

    test('reports storage that can be neither read nor cleared', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenThrow(PlatformException(code: 'Exception', message: 'BadPadding'));
      when(
        () => storage.delete(key: any(named: 'key')),
      ).thenThrow(PlatformException(code: 'Exception'));

      expect(
        SecureInstapaperTokenStore(storage: storage).loadTokens,
        throwsA(isA<InstapaperSecureStorageException>()),
      );
    });

    test('returns the saved pair', () async {
      when(
        () => storage.read(key: instapaperOAuthTokenKey),
      ).thenAnswer((_) async => 'tok');
      when(
        () => storage.read(key: instapaperOAuthTokenSecretKey),
      ).thenAnswer((_) async => 'sec');

      final tokens = await SecureInstapaperTokenStore(
        storage: storage,
      ).loadTokens();

      expect(tokens?.token, 'tok');
      expect(tokens?.tokenSecret, 'sec');
    });
  });

  group('SecureInstapaperAccountStore', () {
    late MockSecureStorage storage;

    setUp(() => storage = MockSecureStorage());

    test('round-trips the account', () async {
      final values = <String, String>{};
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((invocation) async {
        values[invocation.namedArguments[#key] as String] =
            invocation.namedArguments[#value] as String;
      });
      when(() => storage.read(key: any(named: 'key'))).thenAnswer(
        (invocation) async => values[invocation.namedArguments[#key] as String],
      );
      final accounts = SecureInstapaperAccountStore(storage: storage);

      await accounts.saveUser(
        const InstapaperUser(userId: 42, username: 'reader@example.com'),
      );
      final user = await accounts.loadUser();

      expect(user?.userId, 42);
      expect(user?.username, 'reader@example.com');
    });

    test('never throws: an unreadable account is no account', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenThrow(PlatformException(code: 'Exception'));
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenThrow(PlatformException(code: 'Exception'));
      when(
        () => storage.delete(key: any(named: 'key')),
      ).thenThrow(PlatformException(code: 'Exception'));
      final accounts = SecureInstapaperAccountStore(storage: storage);

      expect(await accounts.loadUser(), isNull);
      await accounts.saveUser(const InstapaperUser(userId: 1, username: 'a'));
      await accounts.deleteUser();
    });
  });
}
