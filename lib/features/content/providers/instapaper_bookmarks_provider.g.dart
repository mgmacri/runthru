// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instapaper_bookmarks_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$instapaperArticleImportHash() =>
    r'9648289a9b582979128dd157e1e88aef763d2a7c';

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
    r'8f6c36c850f62d159cbaf8a77a9d4bd1e862b120';

/// Fetches the user's Instapaper bookmarks when authenticated.
///
/// Returns an empty list if not authenticated. Automatically refreshes
/// when the auth state changes.
///
/// Copied from [InstapaperBookmarks].
@ProviderFor(InstapaperBookmarks)
final instapaperBookmarksProvider =
    AutoDisposeAsyncNotifierProvider<
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

typedef _$InstapaperBookmarks =
    AutoDisposeAsyncNotifier<List<InstapaperBookmark>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
