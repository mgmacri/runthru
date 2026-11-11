/// Riverpod providers for Instapaper articles: the list, opening one, and
/// the queue that sends reading positions and archives back.
library;

import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/models/instapaper_bookmark.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/services/content_normaliser.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
import 'package:runthru/features/content/services/instapaper_sync_queue.dart';
import 'package:runthru/services/models.dart';

part 'instapaper_bookmarks_provider.g.dart';

/// What to tell the reader when the article list could not be loaded.
String instapaperListFailureMessage(Object error) {
  final kind = error is InstapaperApiException
      ? error.kind
      : InstapaperFailureKind.unknown;
  return switch (kind) {
    InstapaperFailureKind.network =>
      "Can't reach Instapaper. Check your connection.",
    InstapaperFailureKind.rateLimited =>
      'Instapaper is busy. Try again in a few minutes.',
    InstapaperFailureKind.serviceUnavailable ||
    InstapaperFailureKind.unexpectedResponse =>
      'Instapaper is having trouble right now. Try again in a while.',
    InstapaperFailureKind.clockSkew =>
      "Check this device's date and time, then try again.",
    InstapaperFailureKind.unauthorized =>
      'Instapaper needs you to sign in again.',
    InstapaperFailureKind.suspended =>
      'Instapaper is not available to RunThru for this account right now.',
    _ => 'Could not load your articles.',
  };
}

/// What to tell the reader when an article could not be opened.
String instapaperArticleFailureMessage(InstapaperFailureKind kind) {
  return switch (kind) {
    InstapaperFailureKind.network =>
      "Can't reach Instapaper. Check your connection and try again.",
    InstapaperFailureKind.textUnavailable =>
      'Instapaper has no readable text for this article.',
    InstapaperFailureKind.textAccessDenied =>
      'Instapaper is not giving RunThru the text of articles right now.',
    InstapaperFailureKind.premiumRequired =>
      'This article needs Instapaper Premium.',
    InstapaperFailureKind.bookmarkNotFound =>
      'This article is no longer in your Instapaper account.',
    InstapaperFailureKind.unauthorized =>
      'Instapaper needs you to sign in again.',
    InstapaperFailureKind.rateLimited =>
      'Instapaper is busy. Try again in a few minutes.',
    InstapaperFailureKind.serviceUnavailable ||
    InstapaperFailureKind.unexpectedResponse =>
      'Instapaper is having trouble right now. Try again in a while.',
    InstapaperFailureKind.clockSkew =>
      "Check this device's date and time, then try again.",
    InstapaperFailureKind.suspended =>
      'Instapaper is not available to RunThru for this account right now.',
    _ => 'Could not open this article. Try again.',
  };
}

/// Import state for tracking article fetch progress.
///
/// Stored separately from the bookmark list to avoid blocking list display.
sealed class ArticleImportState {
  /// Base constructor for article import states.
  const ArticleImportState();
}

/// No import in progress.
class ArticleImportIdle extends ArticleImportState {
  /// Creates an idle import state.
  const ArticleImportIdle();
}

/// Fetching and normalising article content.
class ArticleImportLoading extends ArticleImportState {
  /// Creates a loading state for the given bookmark.
  const ArticleImportLoading({required this.bookmarkId, required this.title});

  /// The bookmark being imported.
  final int bookmarkId;

  /// Article title for display.
  final String title;
}

/// Article ready for reading.
class ArticleImportDone extends ArticleImportState {
  /// Creates a done state with the normalised document.
  const ArticleImportDone({
    required this.bookmarkId,
    required this.title,
    required this.document,
    this.initialProgress = 0.0,
    this.progressTimestamp = 0,
  });

  /// The bookmark that was imported.
  final int bookmarkId;

  /// Article title.
  final String title;

  /// Normalised document ready for paced reading.
  final ExtractedDocument document;

  /// Instapaper’s stored reading progress (0.0–1.0) at import time.
  final double initialProgress;

  /// When [initialProgress] was recorded (Unix seconds), so the reader can
  /// tell it from an older or newer position kept on this device.
  final int progressTimestamp;
}

/// Article import failed.
class ArticleImportError extends ArticleImportState {
  /// Creates an error state with a user-friendly message.
  const ArticleImportError({
    required this.message,
    this.kind = InstapaperFailureKind.unknown,
  });

  /// Human-readable error message.
  final String message;

  /// What went wrong, for callers that react to it.
  final InstapaperFailureKind kind;
}

/// Manages article import lifecycle — fetch HTML, normalise, signal ready.
@riverpod
class InstapaperArticleImport extends _$InstapaperArticleImport {
  bool _disposed = false;

  @override
  ArticleImportState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    return const ArticleImportIdle();
  }

  /// Fetch article HTML and normalise for paced reading.
  ///
  /// On success, transitions to [ArticleImportDone] with the
  /// [ExtractedDocument]. The caller should listen for this state
  /// and navigate to the reading screen.
  ///
  /// One article at a time: a call made while another article is loading
  /// is ignored (a second tap on the row, say).
  Future<void> importArticle(InstapaperBookmark bookmark) async {
    if (state is ArticleImportLoading) return;

    final authNotifier = ref.read(instapaperAuthProvider.notifier);
    final client = authNotifier.client;
    if (client == null) {
      state = const ArticleImportError(
        message: 'Connect Instapaper in Sources to read this article.',
        kind: InstapaperFailureKind.unauthorized,
      );
      return;
    }

    final title = bookmark.displayTitle;
    state = ArticleImportLoading(bookmarkId: bookmark.bookmarkId, title: title);

    try {
      final html = await client.getBookmarkText(
        bookmarkId: bookmark.bookmarkId,
      );
      final document = await ContentNormaliser.normalise(
        html,
        ContentType.html,
      );
      if (_disposed) return;
      if (document.totalWords == 0) {
        // A video, a PDF, a page Instapaper parsed to nothing: there is
        // nothing to pace, and the reader would open blank.
        _fail(InstapaperFailureKind.textUnavailable);
        return;
      }
      state = ArticleImportDone(
        bookmarkId: bookmark.bookmarkId,
        title: title,
        document: document,
        initialProgress: bookmark.progress,
        progressTimestamp: bookmark.progressTimestamp,
      );
    } on InstapaperApiException catch (e) {
      appLog(
        'instapaper',
        'article text failed category=${e.kind.name} code=${e.errorCode}',
      );
      if (_disposed) return;
      if (e.kind == InstapaperFailureKind.unauthorized) {
        unawaited(authNotifier.checkSession());
      }
      if (e.kind == InstapaperFailureKind.bookmarkNotFound) {
        ref
            .read(instapaperBookmarksProvider.notifier)
            .forget(bookmark.bookmarkId);
      }
      _fail(e.kind);
    } on Object {
      appLog('instapaper', 'article text failed category=unknown');
      if (_disposed) return;
      _fail(InstapaperFailureKind.unknown);
    }
  }

  void _fail(InstapaperFailureKind kind) {
    state = ArticleImportError(
      message: instapaperArticleFailureMessage(kind),
      kind: kind,
    );
  }

  /// Reset import state after navigation.
  void clear() {
    state = const ArticleImportIdle();
  }
}

/// Fetches the user's Instapaper bookmarks when authenticated.
///
/// Returns an empty list if not authenticated. Automatically refreshes
/// when the auth state changes. Pending sync ops from
/// [instapaperSyncQueueProvider] are overlaid on the server response so
/// the user always sees their latest local progress, even when offline or
/// waiting for the queue to drain.
///
/// Kept alive so optimistic updates from the reading screen survive
/// navigation back to the library. Call [refresh] to force a re-fetch; a
/// refresh that fails leaves the list that was there (`hasValue` stays true
/// alongside the error).
@Riverpod(keepAlive: true)
class InstapaperBookmarks extends _$InstapaperBookmarks {
  DateTime? _fetchedAt;

  @override
  Future<List<InstapaperBookmark>> build() async {
    // Only whether someone is connected: the account's name changing must
    // not fetch the list again.
    final connected = ref.watch(
      instapaperAuthProvider.select((s) => s is InstapaperAuthAuthenticated),
    );
    if (!connected) {
      _fetchedAt = null;
      return [];
    }

    final auth = ref.read(instapaperAuthProvider.notifier);
    final client = auth.client;
    if (client == null) return [];

    // Send what is waiting, in the background. An op that goes out while
    // the list is on its way may or may not be reflected in it, so the ops
    // pending before the request count as much as those pending after.
    final queue = ref.read(instapaperSyncQueueProvider);
    final pendingBefore = await queue.pendingOps();
    unawaited(queue.drain());

    final InstapaperBookmarkPage page;
    try {
      page = await client.fetchBookmarks();
    } on InstapaperApiException catch (e) {
      appLog(
        'instapaper',
        'list failed category=${e.kind.name} code=${e.errorCode}',
      );
      // The list is the plainest request there is: a refused token here is
      // about the connection, not about the request.
      if (e.kind == InstapaperFailureKind.unauthorized) {
        unawaited(auth.sessionExpired());
      }
      rethrow;
    }
    _fetchedAt = DateTime.now();
    if (page.skipped > 0) {
      appLog('instapaper', 'list skipped ${page.skipped} unreadable entries');
    }
    final user = page.user;
    if (user != null) {
      // After this build, not during it.
      unawaited(Future<void>.microtask(() => auth.updateUser(user)));
    }

    return overlayPendingOps(page.bookmarks, [
      ...pendingBefore,
      ...await queue.pendingOps(),
    ]);
  }

  /// Fetch the list again. The list on screen stays until the new one
  /// arrives, and stays for good if it does not.
  ///
  /// Returns null when the list was updated, or what to tell the reader.
  Future<String?> refresh() async {
    if (ref.read(instapaperAuthProvider) is! InstapaperAuthAuthenticated) {
      return null;
    }
    ref.invalidateSelf();
    try {
      await future;
      return null;
    } on Object catch (e) {
      return instapaperListFailureMessage(e);
    }
  }

  /// [refresh], unless the list was fetched less than [maxAge] ago or is
  /// being fetched now. For coming back to the app: an article saved from
  /// the browser a moment ago should be there.
  Future<void> refreshIfStale({
    Duration maxAge = const Duration(seconds: 30),
  }) async {
    if (state.isLoading) return;
    final fetchedAt = _fetchedAt;
    if (fetchedAt != null && DateTime.now().difference(fetchedAt) < maxAge) {
      return;
    }
    await refresh();
  }

  /// Drop a bookmark that turned out to be gone from the account.
  void forget(int bookmarkId) => _applyOptimisticArchive(bookmarkId);

  /// Optimistically apply a reading-progress update locally and enqueue
  /// the change for delivery to Instapaper. Completes once the change is
  /// saved on the device; sending happens afterwards and is retried until
  /// Instapaper has it.
  Future<void> syncProgress({
    required int bookmarkId,
    required double progress,
  }) async {
    final clamped = progress.clamp(0.0, 1.0);
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _applyOptimisticProgress(
      bookmarkId: bookmarkId,
      progress: clamped,
      timestamp: ts,
    );
    await ref
        .read(instapaperSyncQueueProvider)
        .enqueueProgress(
          bookmarkId: bookmarkId,
          progress: clamped,
          timestampSeconds: ts,
        );
  }

  /// Optimistically remove the bookmark from the local list and enqueue
  /// an archive op for Instapaper.
  Future<void> archive({required int bookmarkId}) async {
    _applyOptimisticArchive(bookmarkId);
    await ref
        .read(instapaperSyncQueueProvider)
        .enqueueArchive(bookmarkId: bookmarkId);
  }

  void _applyOptimisticProgress({
    required int bookmarkId,
    required double progress,
    required int timestamp,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final b in current)
        if (b.bookmarkId == bookmarkId)
          b.copyWith(progress: progress, progressTimestamp: timestamp)
        else
          b,
    ]);
  }

  void _applyOptimisticArchive(int bookmarkId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final b in current)
        if (b.bookmarkId != bookmarkId) b,
    ]);
  }

  /// Overlay pending queue ops on a freshly-fetched bookmark list: an
  /// article waiting to be archived is left out, and a position waiting to
  /// be sent replaces the server's unless the server's is newer (read
  /// further on another device since).
  static List<InstapaperBookmark> overlayPendingOps(
    List<InstapaperBookmark> bookmarks,
    List<InstapaperSyncOp> ops,
  ) {
    if (ops.isEmpty) return bookmarks;
    final archivedIds = <int>{
      for (final o in ops)
        if (o is ArchiveOp) o.bookmarkId,
    };
    final pendingProgress = <int, ProgressOp>{};
    for (final o in ops) {
      if (o is! ProgressOp) continue;
      final known = pendingProgress[o.bookmarkId];
      if (known == null || o.timestamp >= known.timestamp) {
        pendingProgress[o.bookmarkId] = o;
      }
    }
    return [
      for (final b in bookmarks)
        if (!archivedIds.contains(b.bookmarkId))
          if (pendingProgress[b.bookmarkId] case final ProgressOp p
              when p.timestamp >= b.progressTimestamp)
            b.copyWith(progress: p.progress, progressTimestamp: p.timestamp)
          else
            b,
    ];
  }
}

/// Singleton sync queue for Instapaper write operations. Kept alive so
/// pending ops survive widget tree disposal (e.g. leaving the library
/// screen) and continue draining as long as the app is running.
@Riverpod(keepAlive: true)
InstapaperSyncQueue instapaperSyncQueue(Ref ref) {
  final queue = InstapaperSyncQueue(
    clientResolver: () => ref.read(instapaperAuthProvider.notifier).client,
    // A refused write may mean the connection was revoked: ask Instapaper.
    onAuthFailure: (_) =>
        unawaited(ref.read(instapaperAuthProvider.notifier).checkSession()),
  );
  ref.onDispose(queue.dispose);
  // Drain whenever auth becomes authenticated (e.g. login, app resume).
  ref.listen<InstapaperAuthState>(instapaperAuthProvider, (prev, next) {
    if (next is InstapaperAuthAuthenticated) {
      unawaited(queue.drain());
    } else if (prev is InstapaperAuthAuthenticated &&
        next is InstapaperAuthUnauthenticated) {
      unawaited(queue.clear());
    }
  }, fireImmediately: true);
  return queue;
}
