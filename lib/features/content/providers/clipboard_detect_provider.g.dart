// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clipboard_detect_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$clipboardDetectHash() => r'71bb5a297294aa5eb4da6b978d4486cc3e16564a';

/// Detects readable text on the system clipboard on app foreground resume.
///
/// Rule 28 compliance: clipboard is only READ (not imported) on foreground.
/// Actual import requires an explicit user tap on the clipboard prompt.
/// Clipboard contents are never logged or transmitted.
///
/// Copied from [ClipboardDetect].
@ProviderFor(ClipboardDetect)
final clipboardDetectProvider =
    AutoDisposeNotifierProvider<ClipboardDetect, ClipboardDetectState>.internal(
      ClipboardDetect.new,
      name: r'clipboardDetectProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$clipboardDetectHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ClipboardDetect = AutoDisposeNotifier<ClipboardDetectState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
