/// Riverpod provider for fetching Instapaper bookmarks.
///
/// Watches the auth provider and fetches bookmarks when authenticated.
/// Auto-disposes when no longer listened to.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:runthru/features/content/models/instapaper_bookmark.dart';
import 'package:runthru/features/content/providers/instapaper_auth_provider.dart';
import 'package:runthru/features/content/services/content_normaliser.dart';
import 'package:runthru/features/content/services/instapaper_client.dart';
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
  });

  /// The bookmark that was imported.
  final int bookmarkId;

  /// Article title.
  final String title;

  /// Normalised document ready for paced reading.
  final ExtractedDocument document;
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
/// when the auth state changes.
@riverpod
class InstapaperBookmarks extends _$InstapaperBookmarks {
  @override
  Future<List<InstapaperBookmark>> build() async {
    final authState = ref.watch(instapaperAuthProvider);
    if (authState is! InstapaperAuthAuthenticated) {
      return [];
    }

    final client = ref.read(instapaperAuthProvider.notifier).client;
    if (client == null) return [];

    return client.getBookmarks();
  }

  /// Force refresh the bookmarks list.
  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}
