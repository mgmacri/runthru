// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_picker_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$filePickerNotifierHash() =>
    r'6a6b9eda51b9fc3aa2eeac41a476e69f90fe6f78';

/// Manages file picking and content extraction.
///
/// Uses the `file_picker` package to open the system file picker filtered
/// to supported formats. Routes the selected file to the appropriate
/// extractor and reports progress via provider state.
///
/// Files are copied to app-private storage before extraction.
/// Content stays on-device only — no cloud upload.
///
/// Copied from [FilePickerNotifier].
@ProviderFor(FilePickerNotifier)
final filePickerNotifierProvider =
    AutoDisposeNotifierProvider<FilePickerNotifier, FilePickerState>.internal(
      FilePickerNotifier.new,
      name: r'filePickerNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$filePickerNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$FilePickerNotifier = AutoDisposeNotifier<FilePickerState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
