// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reading_mode_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$readingModeNotifierHash() =>
    r'3f96d173e2054242f6aaf03e53d487aa9d6c7745';

/// Provides the current reading mode. Auto-disposed when the reading
/// screen is unmounted (session-only, not persisted in AppConfig).
///
/// Copied from [ReadingModeNotifier].
@ProviderFor(ReadingModeNotifier)
final readingModeNotifierProvider =
    AutoDisposeNotifierProvider<ReadingModeNotifier, ReadingMode>.internal(
      ReadingModeNotifier.new,
      name: r'readingModeNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$readingModeNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ReadingModeNotifier = AutoDisposeNotifier<ReadingMode>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
