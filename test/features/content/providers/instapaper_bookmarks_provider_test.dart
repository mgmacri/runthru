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
  });
}
