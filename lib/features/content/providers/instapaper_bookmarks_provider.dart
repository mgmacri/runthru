/// Riverpod provider for fetching Instapaper bookmarks.
///
/// Watches the auth provider and fetches bookmarks when authenticated.
/// Auto-disposes when no longer listened to.
library;

import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:runthru/features/content/models/instapaper_bookmark.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/services/content_normaliser.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
import 'package:runthru/features/content/services/instapaper_sync_queue.dart';
import 'package:runthru/services/models.dart';

part 'instapaper_bookmarks_provider.g.dart';

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
  });

  /// The bookmark that was imported.
  final int bookmarkId;

  /// Article title.
  final String title;

  /// Normalised document ready for paced reading.
  final ExtractedDocument document;

  /// Instapaper’s stored reading progress (0.0–1.0) at import time.
  final double initialProgress;
}

/// Article import failed.
class ArticleImportError extends ArticleImportState {
  /// Creates an error state with a user-friendly message.
  const ArticleImportError({required this.message});

  /// Human-readable error message.
  final String message;
}

/// Manages article import lifecycle — fetch HTML, normalise, signal ready.
@riverpod
class InstapaperArticleImport extends _$InstapaperArticleImport {
  @override
  ArticleImportState build() => const ArticleImportIdle();

  /// Fetch article HTML and normalise for paced reading.
  ///
  /// On success, transitions to [ArticleImportDone] with the
  /// [ExtractedDocument]. The caller should listen for this state
  /// and navigate to the reading screen.
  Future<void> importArticle(InstapaperBookmark bookmark) async {
    final authNotifier = ref.read(instapaperAuthProvider.notifier);
    final client = authNotifier.client;
    if (client == null) {
      state = const ArticleImportError(message: 'Not signed in to Instapaper');
      return;
    }

    state = ArticleImportLoading(
      bookmarkId: bookmark.bookmarkId,
      title: bookmark.title,
    );

    try {
      final html = await client.getBookmarkText(
        bookmarkId: bookmark.bookmarkId,
      );
      final document = await ContentNormaliser.normalise(
        html,
        ContentType.html,
      );
      state = ArticleImportDone(
        bookmarkId: bookmark.bookmarkId,
        title: bookmark.title,
        document: document,
        initialProgress: bookmark.progress,
      );
    } on InstapaperApiException catch (e) {
      state = ArticleImportError(
        message: e.errorCode == 1041
            ? 'This article requires Instapaper Premium'
            : 'Could not load article. Please try again.',
      );
    } catch (_) {
      state = const ArticleImportError(
        message: 'Could not load article. Please try again.',
      );
    }
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
/// navigation back to the library. Call [refresh] to force a re-fetch.
@Riverpod(keepAlive: true)
class InstapaperBookmarks extends _$InstapaperBookmarks {
  @override
  Future<List<InstapaperBookmark>> build() async {
    final authState = ref.watch(instapaperAuthProvider);
    if (authState is! InstapaperAuthAuthenticated) {
      return [];
    }

    final client = ref.read(instapaperAuthProvider.notifier).client;
    if (client == null) return [];

    // Kick off a drain in the background (fire-and-forget). The queue
    // provider also drains on auth change, so this is non-blocking.
    final queue = ref.read(instapaperSyncQueueProvider);
    unawaited(queue.drain());

    final bookmarks = await client.getBookmarks();
    return _overlayPendingOps(bookmarks, await queue.pendingOps());
  }

  /// Force refresh the bookmarks list.
  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  /// Optimistically apply a reading-progress update locally and enqueue
  /// the change for delivery to Instapaper. Eventual consistency: the
  /// queue retries on failure until the op is sent or auth is revoked.
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

  /// Overlay pending queue ops on a freshly-fetched bookmark list.
  static List<InstapaperBookmark> _overlayPendingOps(
    List<InstapaperBookmark> bookmarks,
    List<InstapaperSyncOp> ops,
  ) {
    if (ops.isEmpty) return bookmarks;
    final archivedIds = <int>{
      for (final o in ops)
        if (o is ArchiveOp) o.bookmarkId,
    };
    final pendingProgress = <int, ProgressOp>{
      for (final o in ops)
        if (o is ProgressOp) o.bookmarkId: o,
    };
    return [
      for (final b in bookmarks)
        if (!archivedIds.contains(b.bookmarkId))
          if (pendingProgress[b.bookmarkId] case final ProgressOp p)
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
  );
  // Drain whenever auth becomes authenticated (e.g. login, app resume).
  ref.listen<InstapaperAuthState>(instapaperAuthProvider, (prev, next) {
    if (next is InstapaperAuthAuthenticated) {
      queue.drain();
    }
  }, fireImmediately: true);
  return queue;
}
