// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instapaper_bookmarks_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$instapaperSyncQueueHash() =>
    r'4521b5371953860b4e2219f0c55299df974b090b';

/// Singleton sync queue for Instapaper write operations. Kept alive so
/// pending ops survive widget tree disposal (e.g. leaving the library
/// screen) and continue draining as long as the app is running.
///
/// Copied from [instapaperSyncQueue].
@ProviderFor(instapaperSyncQueue)
final instapaperSyncQueueProvider = Provider<InstapaperSyncQueue>.internal(
  instapaperSyncQueue,
  name: r'instapaperSyncQueueProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$instapaperSyncQueueHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef InstapaperSyncQueueRef = ProviderRef<InstapaperSyncQueue>;
String _$instapaperArticleImportHash() =>
    r'fb11506ab6acd4d69feaa1a4ab574a9578f8dabe';

/// Manages article import lifecycle — fetch HTML, normalise, signal ready.
///
/// Copied from [InstapaperArticleImport].
@ProviderFor(InstapaperArticleImport)
final instapaperArticleImportProvider =
    AutoDisposeNotifierProvider<
      InstapaperArticleImport,
      ArticleImportState
    >.internal(
      InstapaperArticleImport.new,
      name: r'instapaperArticleImportProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$instapaperArticleImportHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$InstapaperArticleImport = AutoDisposeNotifier<ArticleImportState>;
String _$instapaperBookmarksHash() =>
    r'57a71eb1b02f28f4a9048d8c50cf28959db89a51';

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
///
/// Copied from [InstapaperBookmarks].
@ProviderFor(InstapaperBookmarks)
final instapaperBookmarksProvider =
    AsyncNotifierProvider<
      InstapaperBookmarks,
      List<InstapaperBookmark>
    >.internal(
      InstapaperBookmarks.new,
      name: r'instapaperBookmarksProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$instapaperBookmarksHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$InstapaperBookmarks = AsyncNotifier<List<InstapaperBookmark>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
