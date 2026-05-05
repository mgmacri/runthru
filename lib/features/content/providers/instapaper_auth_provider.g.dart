// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instapaper_auth_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$instapaperAuthHash() => r'40762c359fb6fdb381e57763fb9f8af2a24c7a64';

/// Manages Instapaper authentication lifecycle.
///
/// Persists OAuth tokens in flutter_secure_storage. On [build], checks
/// for existing tokens and attempts session restoration. Use [login] to
/// authenticate and [logout] to clear tokens.
///
/// Copied from [InstapaperAuth].
@ProviderFor(InstapaperAuth)
final instapaperAuthProvider =
    NotifierProvider<InstapaperAuth, InstapaperAuthState>.internal(
      InstapaperAuth.new,
      name: r'instapaperAuthProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$instapaperAuthHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$InstapaperAuth = Notifier<InstapaperAuthState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
