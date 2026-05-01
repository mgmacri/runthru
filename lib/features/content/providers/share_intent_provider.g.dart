// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'share_intent_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$shareIntentHash() => r'02a77dbad6794ac76246e74f16a599830efee462';

/// Manages incoming share intents from Android and iOS.
///
/// Listens for shared content via platform channel (Android) and
/// App Group container (iOS). Routes content through the appropriate
/// extractor to produce an [ExtractedDocument].
///
/// All content stays on-device only — no cloud upload.
///
/// Copied from [ShareIntent].
@ProviderFor(ShareIntent)
final shareIntentProvider =
    NotifierProvider<ShareIntent, ShareIntentState>.internal(
      ShareIntent.new,
      name: r'shareIntentProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$shareIntentHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ShareIntent = Notifier<ShareIntentState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
