// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reading_progress_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$readingProgressHash() => r'c8bdad7e96dd39407853f8f146a813d7517bbac0';

/// Notifier managing the per-item progress store.
///
/// Persists to SharedPreferences as a JSON list. All mutations are
/// synchronised to prevent concurrent read-modify-write data loss.
///
/// TODO(background-sync): Reconcile Instapaper items against the server-side
/// `progress` / `progress_timestamp` fields when background sync lands.
/// Local store is authoritative for now; last-write-wins with the server
/// timestamp as the tiebreaker once reconciliation is implemented.
///
/// Copied from [ReadingProgress].
@ProviderFor(ReadingProgress)
final readingProgressProvider =
    AutoDisposeAsyncNotifierProvider<
      ReadingProgress,
      List<ProgressRecord>
    >.internal(
      ReadingProgress.new,
      name: r'readingProgressProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$readingProgressHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ReadingProgress = AutoDisposeAsyncNotifier<List<ProgressRecord>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
