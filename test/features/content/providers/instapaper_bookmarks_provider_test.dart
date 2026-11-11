import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:runthru/features/content/models/instapaper_bookmark.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/providers/instapaper_bookmarks_provider.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
import 'package:runthru/features/content/services/instapaper_sync_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHttpClient extends Mock implements http.Client {}

/// Fake auth notifier that exposes a controllable client.
class FakeInstapaperAuth extends Notifier<InstapaperAuthState>
    implements InstapaperAuth {
  FakeInstapaperAuth({this.initialState, this.testClient});

  final InstapaperAuthState? initialState;
  final InstapaperClient? testClient;

  @override
  InstapaperAuthState build() =>
      initialState ?? const InstapaperAuthUnauthenticated();

  @override
  InstapaperClient? get client => testClient;

  @override
  Future<void> login({
    required String username,
    required String password,
  }) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> connect() async {}

  int sessionExpiredCalls = 0;
  int checkSessionCalls = 0;
  final updatedUsers = <InstapaperUser>[];

  @override
  Future<void> sessionExpired() async {
    sessionExpiredCalls++;
    state = const InstapaperAuthError(
      kind: InstapaperFailureKind.unauthorized,
      message: 'Instapaper needs you to sign in again.',
    );
  }

  @override
  Future<void> checkSession() async => checkSessionCalls++;

  @override
  void updateUser(InstapaperUser user) => updatedUsers.add(user);

  @override
  void dismissError() {}
}

void main() {
  const testConfig = InstapaperClientConfig(
    consumerKey: 'consumer_key',
    consumerSecret: 'consumer_secret',
  );
  late MockHttpClient mockHttp;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    mockHttp = MockHttpClient();
    SharedPreferences.setMockInitialValues({});
  });

  group('InstapaperBookmarks', () {
    test('returns empty list when not authenticated', () async {
      final container = ProviderContainer(
        overrides: [
          instapaperAuthProvider.overrideWith(
            () => FakeInstapaperAuth(
              initialState: const InstapaperAuthUnauthenticated(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final bookmarks = await container.read(
        instapaperBookmarksProvider.future,
      );
      expect(bookmarks, isEmpty);
    });

    test('fetches bookmarks when authenticated', () async {
      final client = InstapaperClient(httpClient: mockHttp, config: testConfig);
      client.setTokens(token: 'tok', tokenSecret: 'sec');

      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode([
            {'type': 'user', 'user_id': 123, 'username': 'test'},
            {
              'type': 'bookmark',
              'bookmark_id': 1001,
              'url': 'https://example.com/article',
              'title': 'Test Article',
            },
            {
              'type': 'bookmark',
              'bookmark_id': 1002,
              'url': 'https://example.com/article2',
              'title': 'Second Article',
            },
          ]),
          200,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          instapaperAuthProvider.overrideWith(
            () => FakeInstapaperAuth(
              initialState: const InstapaperAuthAuthenticated(
                user: InstapaperUser(userId: 123, username: 'test'),
              ),
              testClient: client,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final bookmarks = await container.read(
        instapaperBookmarksProvider.future,
      );
      expect(bookmarks, hasLength(2));
      expect(bookmarks[0].bookmarkId, equals(1001));
      expect(bookmarks[1].bookmarkId, equals(1002));
    });

    test(
      'syncProgress updates local bookmark list state optimistically',
      () async {
        final client = InstapaperClient(
          httpClient: mockHttp,
          config: testConfig,
        );
        client.setTokens(token: 'tok', tokenSecret: 'sec');

        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((invocation) async {
          final uri = invocation.positionalArguments.first as Uri;
          if (uri.path == '/api/1/bookmarks/list') {
            return http.Response(
              jsonEncode([
                {'type': 'user', 'user_id': 123, 'username': 'test'},
                {
                  'type': 'bookmark',
                  'bookmark_id': 1001,
                  'url': 'https://example.com/article',
                  'title': 'Test Article',
                  'progress': 0.10,
                },
              ]),
              200,
            );
          }
          return http.Response('', 200);
        });

        final container = ProviderContainer(
          overrides: [
            instapaperAuthProvider.overrideWith(
              () => FakeInstapaperAuth(
                initialState: const InstapaperAuthAuthenticated(
                  user: InstapaperUser(userId: 123, username: 'test'),
                ),
                testClient: client,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(instapaperBookmarksProvider.future);

        await container
            .read(instapaperBookmarksProvider.notifier)
            .syncProgress(bookmarkId: 1001, progress: 0.42);

        final bookmarks = container
            .read(instapaperBookmarksProvider)
            .valueOrNull;
        expect(bookmarks, isNotNull);
        expect(bookmarks!.single.progress, equals(0.42));
        expect(bookmarks.single.progressLabel, equals('42%'));
      },
    );

    test('syncProgress keeps local progress when remote drain fails', () async {
      final client = InstapaperClient(httpClient: mockHttp, config: testConfig);
      client.setTokens(token: 'tok', tokenSecret: 'sec');

      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        if (uri.path == '/api/1/bookmarks/list') {
          return http.Response(
            jsonEncode([
              {'type': 'user', 'user_id': 123, 'username': 'test'},
              {
                'type': 'bookmark',
                'bookmark_id': 1001,
                'url': 'https://example.com/article',
                'title': 'Test Article',
                'progress': 0.10,
              },
            ]),
            200,
          );
        }
        throw Exception('network down');
      });

      final container = ProviderContainer(
        overrides: [
          instapaperAuthProvider.overrideWith(
            () => FakeInstapaperAuth(
              initialState: const InstapaperAuthAuthenticated(
                user: InstapaperUser(userId: 123, username: 'test'),
              ),
              testClient: client,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(instapaperBookmarksProvider.future);

      await container
          .read(instapaperBookmarksProvider.notifier)
          .syncProgress(bookmarkId: 1001, progress: 0.37);

      final bookmarks = container.read(instapaperBookmarksProvider).valueOrNull;
      expect(bookmarks, isNotNull);
      expect(bookmarks!.single.progress, equals(0.37));

      final pending = await container
          .read(instapaperSyncQueueProvider)
          .pendingOps();
      expect(pending, hasLength(1));
      expect(pending.single, isA<ProgressOp>());
      expect((pending.single as ProgressOp).progress, equals(0.37));
    });
  });

  group('sync (B-46)', () {
    InstapaperBookmark bookmark(
      int id, {
      double progress = 0,
      int progressTimestamp = 0,
    }) => InstapaperBookmark(
      bookmarkId: id,
      url: 'https://example.com/$id',
      title: 'Article $id',
      progress: progress,
      progressTimestamp: progressTimestamp,
    );

    ProviderContainer signedIn(InstapaperClient client) {
      final container = ProviderContainer(
        overrides: [
          instapaperAuthProvider.overrideWith(
            () => FakeInstapaperAuth(
              initialState: const InstapaperAuthAuthenticated(
                user: InstapaperUser(userId: 123, username: 'test'),
              ),
              testClient: client,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('an article waiting to be archived is left out of the list', () {
      final result = InstapaperBookmarks.overlayPendingOps(
        [bookmark(1), bookmark(2)],
        const [ArchiveOp(bookmarkId: 1)],
      );

      expect(result.map((b) => b.bookmarkId), [2]);
    });

    test('a pending position replaces an older one from the server', () {
      final result = InstapaperBookmarks.overlayPendingOps(
        [bookmark(1, progress: 0.2, progressTimestamp: 100)],
        const [ProgressOp(bookmarkId: 1, progress: 0.6, timestamp: 200)],
      );

      expect(result.single.progress, 0.6);
      expect(result.single.progressTimestamp, 200);
    });

    test('a newer position from another device is not overwritten', () {
      final result = InstapaperBookmarks.overlayPendingOps(
        [bookmark(1, progress: 0.9, progressTimestamp: 300)],
        const [ProgressOp(bookmarkId: 1, progress: 0.3, timestamp: 200)],
      );

      expect(result.single.progress, 0.9);
      expect(result.single.progressTimestamp, 300);
    });

    test('of two pending positions for an article the later one counts', () {
      final result = InstapaperBookmarks.overlayPendingOps(
        [bookmark(1)],
        const [
          ProgressOp(bookmarkId: 1, progress: 0.7, timestamp: 20),
          ProgressOp(bookmarkId: 1, progress: 0.4, timestamp: 10),
        ],
      );

      expect(result.single.progress, 0.7);
    });

    test(
      'an archive that goes out during a refresh does not bring the article back',
      () async {
        SharedPreferences.setMockInitialValues({
          'instapaper_sync_queue_v1': jsonEncode([
            {'type': 'archive', 'bookmark_id': 1001},
          ]),
        });
        final client = InstapaperClient(
          httpClient: mockHttp,
          config: testConfig,
        )..setTokens(token: 'tok', tokenSecret: 'sec');
        final archived = Completer<void>();

        when(
          () => mockHttp.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((invocation) async {
          final uri = invocation.positionalArguments.first as Uri;
          if (uri.path == '/api/1/bookmarks/archive') {
            archived.complete();
            return http.Response('[]', 200);
          }
          // The list was built before the archive arrived, and is delivered
          // after the archive has left the queue.
          await archived.future;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response(
            jsonEncode([
              {'type': 'bookmark', 'bookmark_id': 1001, 'title': 'Finished'},
              {'type': 'bookmark', 'bookmark_id': 1002, 'title': 'Unread'},
            ]),
            200,
          );
        });

        final container = signedIn(client);
        final bookmarks = await container.read(
          instapaperBookmarksProvider.future,
        );

        expect(bookmarks.map((b) => b.bookmarkId), [1002]);
        expect(
          await container.read(instapaperSyncQueueProvider).pendingOps(),
          isEmpty,
        );
      },
    );

    test('saving a position does not wait for the network', () async {
      final client = InstapaperClient(httpClient: mockHttp, config: testConfig)
        ..setTokens(token: 'tok', tokenSecret: 'sec');
      final neverAnswered = Completer<http.Response>();
      addTearDown(() => neverAnswered.complete(http.Response('[]', 200)));

      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((invocation) {
        final uri = invocation.positionalArguments.first as Uri;
        if (uri.path == '/api/1/bookmarks/list') {
          return Future.value(
            http.Response(
              jsonEncode([
                {'type': 'bookmark', 'bookmark_id': 1001, 'title': 'A'},
              ]),
              200,
            ),
          );
        }
        return neverAnswered.future;
      });

      final container = signedIn(client);
      await container.read(instapaperBookmarksProvider.future);
      final notifier = container.read(instapaperBookmarksProvider.notifier);

      await notifier
          .syncProgress(bookmarkId: 1001, progress: 0.5)
          .timeout(const Duration(seconds: 2));
      await notifier
          .archive(bookmarkId: 1001)
          .timeout(const Duration(seconds: 2));

      expect(container.read(instapaperBookmarksProvider).value, isEmpty);
      final pending = await container
          .read(instapaperSyncQueueProvider)
          .pendingOps();
      expect(pending.single, isA<ArchiveOp>());
    });

    test('finishing an article queues 100% and then the archive', () async {
      final client = InstapaperClient(httpClient: mockHttp, config: testConfig)
        ..setTokens(token: 'tok', tokenSecret: 'sec');
      final sent = <String>[];
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        final body = invocation.namedArguments[#body] as Map<String, String>;
        if (uri.path == '/api/1/bookmarks/list') {
          return http.Response(
            jsonEncode([
              {'type': 'bookmark', 'bookmark_id': 1001, 'title': 'A'},
            ]),
            200,
          );
        }
        sent.add(
          '${uri.pathSegments.last}:${body['bookmark_id']}'
          '${body['progress'] == null ? '' : ':${body['progress']}'}',
        );
        return http.Response('[]', 200);
      });

      final container = signedIn(client);
      await container.read(instapaperBookmarksProvider.future);
      await container
          .read(instapaperBookmarksProvider.notifier)
          .archive(bookmarkId: 1001, finished: true);
      await container.read(instapaperSyncQueueProvider).drain();

      expect(sent, ['update_read_progress:1001:1.0000', 'archive:1001']);
      expect(container.read(instapaperBookmarksProvider).value, isEmpty);
    });

    test('a position that could not be sent offline is kept', () async {
      final client = InstapaperClient(httpClient: mockHttp, config: testConfig)
        ..setTokens(token: 'tok', tokenSecret: 'sec');

      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        if (uri.path == '/api/1/bookmarks/list') {
          return http.Response(
            jsonEncode([
              {'type': 'bookmark', 'bookmark_id': 1001, 'title': 'A'},
            ]),
            200,
          );
        }
        // What the device reports with no connection.
        throw http.ClientException('Failed host lookup');
      });

      final container = signedIn(client);
      await container.read(instapaperBookmarksProvider.future);
      await container
          .read(instapaperBookmarksProvider.notifier)
          .syncProgress(bookmarkId: 1001, progress: 0.37);
      final queue = container.read(instapaperSyncQueueProvider);
      await queue.drain();

      final pending = await queue.pendingOps();
      expect(pending.single, isA<ProgressOp>());
      expect((pending.single as ProgressOp).progress, 0.37);
    });
  });

  group('list (B-48)', () {
    late FakeInstapaperAuth auth;
    late InstapaperClient client;
    late String listBody;
    late int listStatus;
    late int listCalls;

    ProviderContainer signedIn() {
      client = InstapaperClient(httpClient: mockHttp, config: testConfig)
        ..setTokens(token: 'tok', tokenSecret: 'sec');
      auth = FakeInstapaperAuth(
        initialState: const InstapaperAuthAuthenticated(
          user: InstapaperUser(userId: 123, username: 'old-name'),
        ),
        testClient: client,
      );
      final container = ProviderContainer(
        overrides: [instapaperAuthProvider.overrideWith(() => auth)],
      );
      addTearDown(container.dispose);
      return container;
    }

    String listOf(List<int> ids) => jsonEncode([
      {'type': 'user', 'user_id': 123, 'username': 'new-name'},
      for (final id in ids)
        {'type': 'bookmark', 'bookmark_id': id, 'title': 'Article $id'},
    ]);

    setUp(() {
      listBody = listOf([1, 2]);
      listStatus = 200;
      listCalls = 0;
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        if (uri.path == '/api/1/bookmarks/list') {
          listCalls++;
          return http.Response(listBody, listStatus);
        }
        return http.Response('[]', 200);
      });
    });

    test('a refresh that fails keeps the list that was there', () async {
      final container = signedIn();
      await container.read(instapaperBookmarksProvider.future);
      final notifier = container.read(instapaperBookmarksProvider.notifier);

      listStatus = 503;
      final problem = await notifier.refresh();

      expect(
        problem,
        'Instapaper is having trouble right now. Try again in a while.',
      );
      final state = container.read(instapaperBookmarksProvider);
      expect(state.hasError, isTrue);
      expect(state.valueOrNull?.map((b) => b.bookmarkId), [1, 2]);
    });

    test('a refresh brings in what was saved since', () async {
      final container = signedIn();
      await container.read(instapaperBookmarksProvider.future);

      listBody = listOf([3, 1, 2]);
      final problem = await container
          .read(instapaperBookmarksProvider.notifier)
          .refresh();

      expect(problem, isNull);
      expect(
        container
            .read(instapaperBookmarksProvider)
            .valueOrNull
            ?.map((b) => b.bookmarkId),
        [3, 1, 2],
      );
    });

    test('refreshIfStale leaves a fresh list alone', () async {
      final container = signedIn();
      await container.read(instapaperBookmarksProvider.future);
      final notifier = container.read(instapaperBookmarksProvider.notifier);

      await notifier.refreshIfStale(maxAge: const Duration(minutes: 5));
      expect(listCalls, 1);

      await notifier.refreshIfStale(maxAge: Duration.zero);
      expect(listCalls, 2);
    });

    test('refreshIfStale retries a list that never loaded', () async {
      listStatus = 503;
      final container = signedIn();
      await expectLater(
        container.read(instapaperBookmarksProvider.future),
        throwsA(isA<InstapaperApiException>()),
      );

      listStatus = 200;
      await container
          .read(instapaperBookmarksProvider.notifier)
          .refreshIfStale(maxAge: const Duration(minutes: 5));

      expect(
        container.read(instapaperBookmarksProvider).valueOrNull,
        hasLength(2),
      );
    });

    test('a refused token signs the reader out', () async {
      listStatus = 403;
      listBody = '';
      final container = signedIn();
      final sub = container.listen(instapaperBookmarksProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(auth.sessionExpiredCalls, 1);
      // Signed out: an empty list, not an error left over.
      expect(container.read(instapaperBookmarksProvider).valueOrNull, isEmpty);
    });

    test(
      'trouble on Instapaper\'s side does not sign the reader out',
      () async {
        listStatus = 503;
        final container = signedIn();
        await expectLater(
          container.read(instapaperBookmarksProvider.future),
          throwsA(isA<InstapaperApiException>()),
        );

        expect(auth.sessionExpiredCalls, 0);
      },
    );

    test('the account named by the list is passed on', () async {
      final container = signedIn();
      await container.read(instapaperBookmarksProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(auth.updatedUsers.single.username, 'new-name');
      // …without fetching the list a second time for it.
      expect(listCalls, 1);
    });

    test('failure messages are written for readers', () {
      const network = InstapaperApiException(
        kind: InstapaperFailureKind.network,
        errorCode: 0,
        message: 'Network request failed',
      );
      expect(
        instapaperListFailureMessage(network),
        "Can't reach Instapaper. Check your connection.",
      );
      expect(
        instapaperListFailureMessage(Exception('x')),
        'Could not load your articles.',
      );
      for (final kind in InstapaperFailureKind.values) {
        final message = instapaperArticleFailureMessage(kind);
        expect(message, isNot(contains('Exception')), reason: kind.name);
        expect(message, isNot(contains('kind:')), reason: kind.name);
      }
    });
  });

  group('InstapaperArticleImport', () {
    test('starts in idle state', () {
      final container = ProviderContainer(
        overrides: [
          instapaperAuthProvider.overrideWith(
            () => FakeInstapaperAuth(
              initialState: const InstapaperAuthUnauthenticated(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(instapaperArticleImportProvider);
      expect(state, isA<ArticleImportIdle>());
    });

    test('transitions to loading then done on successful import', () async {
      final client = InstapaperClient(httpClient: mockHttp, config: testConfig);
      client.setTokens(token: 'tok', tokenSecret: 'sec');

      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '<html><body><p>This is a test article with enough words.</p></body></html>',
          200,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          instapaperAuthProvider.overrideWith(
            () => FakeInstapaperAuth(
              initialState: const InstapaperAuthAuthenticated(
                user: InstapaperUser(userId: 123, username: 'test'),
              ),
              testClient: client,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(instapaperArticleImportProvider.notifier);

      const bookmark = InstapaperBookmark(
        bookmarkId: 1001,
        url: 'https://example.com/article',
        title: 'Test Article',
      );

      await notifier.importArticle(bookmark);

      final state = container.read(instapaperArticleImportProvider);
      expect(state, isA<ArticleImportDone>());
      final done = state as ArticleImportDone;
      expect(done.bookmarkId, equals(1001));
      expect(done.title, equals('Test Article'));
      expect(done.document.totalWords, greaterThan(0));
    });

    test('transitions to error on API failure', () async {
      final client = InstapaperClient(httpClient: mockHttp, config: testConfig);
      client.setTokens(token: 'tok', tokenSecret: 'sec');

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

      final container = ProviderContainer(
        overrides: [
          instapaperAuthProvider.overrideWith(
            () => FakeInstapaperAuth(
              initialState: const InstapaperAuthAuthenticated(
                user: InstapaperUser(userId: 123, username: 'test'),
              ),
              testClient: client,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(instapaperArticleImportProvider.notifier);

      const bookmark = InstapaperBookmark(
        bookmarkId: 1001,
        url: 'https://example.com/article',
        title: 'Test Article',
      );

      await notifier.importArticle(bookmark);

      final state = container.read(instapaperArticleImportProvider);
      expect(state, isA<ArticleImportError>());
      final error = state as ArticleImportError;
      expect(error.message, contains('Premium'));
    });

    test('clear resets to idle', () async {
      final client = InstapaperClient(httpClient: mockHttp, config: testConfig);
      client.setTokens(token: 'tok', tokenSecret: 'sec');

      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async =>
            http.Response('<p>Some article text for reading.</p>', 200),
      );

      final container = ProviderContainer(
        overrides: [
          instapaperAuthProvider.overrideWith(
            () => FakeInstapaperAuth(
              initialState: const InstapaperAuthAuthenticated(
                user: InstapaperUser(userId: 123, username: 'test'),
              ),
              testClient: client,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(instapaperArticleImportProvider.notifier);

      const bookmark = InstapaperBookmark(
        bookmarkId: 1001,
        url: 'https://example.com/article',
        title: 'Test',
      );

      await notifier.importArticle(bookmark);
      expect(
        container.read(instapaperArticleImportProvider),
        isA<ArticleImportDone>(),
      );

      notifier.clear();
      expect(
        container.read(instapaperArticleImportProvider),
        isA<ArticleImportIdle>(),
      );
    });

    test('normalises HTML through ContentNormaliser', () async {
      final client = InstapaperClient(httpClient: mockHttp, config: testConfig);
      client.setTokens(token: 'tok', tokenSecret: 'sec');

      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '<html><body>'
          '<h1>Title</h1>'
          '<p>First sentence of the article. Second sentence here.</p>'
          '<p>Another paragraph with more words to read.</p>'
          '</body></html>',
          200,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          instapaperAuthProvider.overrideWith(
            () => FakeInstapaperAuth(
              initialState: const InstapaperAuthAuthenticated(
                user: InstapaperUser(userId: 123, username: 'test'),
              ),
              testClient: client,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(instapaperArticleImportProvider.notifier);

      const bookmark = InstapaperBookmark(
        bookmarkId: 2001,
        url: 'https://example.com/real-article',
        title: 'Real Article',
      );

      await notifier.importArticle(bookmark);

      final state = container.read(instapaperArticleImportProvider);
      expect(state, isA<ArticleImportDone>());
      final done = state as ArticleImportDone;
      expect(done.document.sentences, isNotEmpty);
      expect(done.document.totalWords, greaterThan(5));
    });

    // ── B-48 ────────────────────────────────────────────────────────────

    ProviderContainer signedInWith(FakeInstapaperAuth auth) {
      final container = ProviderContainer(
        overrides: [instapaperAuthProvider.overrideWith(() => auth)],
      );
      addTearDown(container.dispose);
      return container;
    }

    FakeInstapaperAuth authFor(InstapaperClient client) => FakeInstapaperAuth(
      initialState: const InstapaperAuthAuthenticated(
        user: InstapaperUser(userId: 123, username: 'test'),
      ),
      testClient: client,
    );

    InstapaperClient newClient() =>
        InstapaperClient(httpClient: mockHttp, config: testConfig)
          ..setTokens(token: 'tok', tokenSecret: 'sec');

    void stubText(Future<http.Response> Function() answer) {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) => answer());
    }

    const article = InstapaperBookmark(
      bookmarkId: 1001,
      url: 'https://example.com/a',
      title: 'An Article',
    );

    Future<ArticleImportError> failureFor(http.Response response) async {
      stubText(() async => response);
      final container = signedInWith(authFor(newClient()));
      final sub = container.listen(instapaperArticleImportProvider, (_, __) {});
      addTearDown(sub.close);

      await container
          .read(instapaperArticleImportProvider.notifier)
          .importArticle(article);

      return container.read(instapaperArticleImportProvider)
          as ArticleImportError;
    }

    test('an article with no text is an error, not a blank reader', () async {
      final failure = await failureFor(
        http.Response(
          '<html><head><title>T</title></head><body></body></html>',
          200,
        ),
      );

      expect(failure.kind, InstapaperFailureKind.textUnavailable);
      expect(
        failure.message,
        'Instapaper has no readable text for this article.',
      );
    });

    test('says when Instapaper has no text version (1550)', () async {
      final failure = await failureFor(
        http.Response(
          '[{"type":"error","error_code":1550,"message":"x"}]',
          400,
        ),
      );

      expect(
        failure.message,
        'Instapaper has no readable text for this article.',
      );
    });

    test(
      'says when Instapaper will not hand the text to the app (1044)',
      () async {
        final failure = await failureFor(
          http.Response(
            '[{"type":"error","error_code":1044,"message":"x"}]',
            400,
          ),
        );

        expect(failure.kind, InstapaperFailureKind.textAccessDenied);
        expect(
          failure.message,
          'Instapaper is not giving RunThru the text of articles right now.',
        );
      },
    );

    test('says when there is no connection', () async {
      stubText(() async => throw http.ClientException('Failed host lookup'));
      final container = signedInWith(authFor(newClient()));
      final sub = container.listen(instapaperArticleImportProvider, (_, __) {});
      addTearDown(sub.close);

      await container
          .read(instapaperArticleImportProvider.notifier)
          .importArticle(article);

      expect(
        (container.read(instapaperArticleImportProvider) as ArticleImportError)
            .message,
        "Can't reach Instapaper. Check your connection and try again.",
      );
    });

    test('a second request while one is loading is ignored', () async {
      final gate = Completer<http.Response>();
      var requests = 0;
      stubText(() {
        requests++;
        return gate.future;
      });
      final container = signedInWith(authFor(newClient()));
      final sub = container.listen(instapaperArticleImportProvider, (_, __) {});
      addTearDown(sub.close);
      final notifier = container.read(instapaperArticleImportProvider.notifier);

      final first = notifier.importArticle(article);
      await Future<void>.delayed(Duration.zero);
      await notifier.importArticle(
        const InstapaperBookmark(bookmarkId: 2002, url: '', title: 'Other'),
      );

      expect(requests, 1);
      final loading = container.read(instapaperArticleImportProvider);
      expect((loading as ArticleImportLoading).bookmarkId, 1001);

      gate.complete(http.Response('<p>Some words to read here.</p>', 200));
      await first;
      final done = container.read(instapaperArticleImportProvider);
      expect((done as ArticleImportDone).bookmarkId, 1001);
    });

    test(
      'carries the position Instapaper has and when it was recorded',
      () async {
        stubText(() async => http.Response('<p>Some words to read.</p>', 200));
        final container = signedInWith(authFor(newClient()));
        final sub = container.listen(
          instapaperArticleImportProvider,
          (_, __) {},
        );
        addTearDown(sub.close);

        await container
            .read(instapaperArticleImportProvider.notifier)
            .importArticle(
              const InstapaperBookmark(
                bookmarkId: 5,
                url: '',
                title: '',
                progress: 0.4,
                progressTimestamp: 1700000000,
              ),
            );

        final done =
            container.read(instapaperArticleImportProvider)
                as ArticleImportDone;
        expect(done.initialProgress, 0.4);
        expect(done.progressTimestamp, 1700000000);
        // No title from Instapaper: something to show all the same.
        expect(done.title, 'Untitled article');
      },
    );

    test('a bookmark that is gone leaves the list', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        if (uri.path == '/api/1/bookmarks/list') {
          return http.Response(
            jsonEncode([
              {'type': 'bookmark', 'bookmark_id': 1001, 'title': 'Gone'},
              {'type': 'bookmark', 'bookmark_id': 1002, 'title': 'Here'},
            ]),
            200,
          );
        }
        return http.Response(
          '[{"type":"error","error_code":1241,"message":"x"}]',
          400,
        );
      });
      final container = signedInWith(authFor(newClient()));
      await container.read(instapaperBookmarksProvider.future);
      final sub = container.listen(instapaperArticleImportProvider, (_, __) {});
      addTearDown(sub.close);

      await container
          .read(instapaperArticleImportProvider.notifier)
          .importArticle(article);

      expect(
        (container.read(instapaperArticleImportProvider) as ArticleImportError)
            .message,
        'This article is no longer in your Instapaper account.',
      );
      expect(
        container
            .read(instapaperBookmarksProvider)
            .valueOrNull
            ?.map((b) => b.bookmarkId),
        [1002],
      );
    });

    test('signed out: says to connect, asks nothing of Instapaper', () async {
      final container = signedInWith(
        FakeInstapaperAuth(initialState: const InstapaperAuthUnauthenticated()),
      );
      final sub = container.listen(instapaperArticleImportProvider, (_, __) {});
      addTearDown(sub.close);

      await container
          .read(instapaperArticleImportProvider.notifier)
          .importArticle(article);

      final failure =
          container.read(instapaperArticleImportProvider) as ArticleImportError;
      expect(
        failure.message,
        'Connect Instapaper in Sources to read this article.',
      );
      verifyNever(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });
  });
}
