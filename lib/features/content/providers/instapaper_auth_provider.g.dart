// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instapaper_auth_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$instapaperAuthHash() => r'9db22c262a070de715ba61288854a8a6fcce2409';

/// Manages Instapaper authentication lifecycle.
///
/// Uses [InstapaperAuthService] to keep secure storage, credential exchange,
/// and API verification outside UI state management.
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
