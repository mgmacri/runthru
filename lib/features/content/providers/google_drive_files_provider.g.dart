// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'google_drive_files_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$googleDriveClientHash() => r'fb9e9139a80a109960f76fec06580cd824073845';

/// Google Drive client dependency.
///
/// Copied from [googleDriveClient].
@ProviderFor(googleDriveClient)
final googleDriveClientProvider = Provider<GoogleDriveClient>.internal(
  googleDriveClient,
  name: r'googleDriveClientProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$googleDriveClientHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GoogleDriveClientRef = ProviderRef<GoogleDriveClient>;
String _$googleDrivePdfExtractorHash() =>
    r'4a3115ddfa91d0f88eedf3304d6fba0859cbe606';

/// PDF extractor dependency for Drive imports.
///
/// Copied from [googleDrivePdfExtractor].
@ProviderFor(googleDrivePdfExtractor)
final googleDrivePdfExtractorProvider =
    AutoDisposeProvider<DocumentFileExtractor>.internal(
      googleDrivePdfExtractor,
      name: r'googleDrivePdfExtractorProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$googleDrivePdfExtractorHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GoogleDrivePdfExtractorRef =
    AutoDisposeProviderRef<DocumentFileExtractor>;
String _$googleDriveEpubExtractorHash() =>
    r'dbab0a58fc06569419757beeec9455793150e560';

/// EPUB extractor dependency for Drive imports.
///
/// Copied from [googleDriveEpubExtractor].
@ProviderFor(googleDriveEpubExtractor)
final googleDriveEpubExtractorProvider =
    AutoDisposeProvider<DocumentFileExtractor>.internal(
      googleDriveEpubExtractor,
      name: r'googleDriveEpubExtractorProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$googleDriveEpubExtractorHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GoogleDriveEpubExtractorRef =
    AutoDisposeProviderRef<DocumentFileExtractor>;
String _$googleDriveTempDirectoryHash() =>
    r'be0027770f5f1c337010c0882b9d869eed820b70';

/// Temporary directory dependency for downloaded Drive files.
///
/// Copied from [googleDriveTempDirectory].
@ProviderFor(googleDriveTempDirectory)
final googleDriveTempDirectoryProvider =
    AutoDisposeFutureProvider<Directory>.internal(
      googleDriveTempDirectory,
      name: r'googleDriveTempDirectoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$googleDriveTempDirectoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GoogleDriveTempDirectoryRef = AutoDisposeFutureProviderRef<Directory>;
String _$googleDriveFilesHash() => r'bd606cdde05d0587ace4d734f7d34fc17b0aed37';

/// Fetches and refreshes supported Google Drive files.
///
/// Copied from [GoogleDriveFiles].
@ProviderFor(GoogleDriveFiles)
final googleDriveFilesProvider =
    NotifierProvider<GoogleDriveFiles, GoogleDriveFileListState>.internal(
      GoogleDriveFiles.new,
      name: r'googleDriveFilesProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$googleDriveFilesHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$GoogleDriveFiles = Notifier<GoogleDriveFileListState>;
String _$googleDriveImportHash() => r'ab541eea16e463bbbcd804868317e708bc5b2e1a';

/// Imports supported Google Drive files into RunThru documents.
///
/// Copied from [GoogleDriveImport].
@ProviderFor(GoogleDriveImport)
final googleDriveImportProvider =
    AutoDisposeNotifierProvider<
      GoogleDriveImport,
      GoogleDriveImportState
    >.internal(
      GoogleDriveImport.new,
      name: r'googleDriveImportProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$googleDriveImportHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$GoogleDriveImport = AutoDisposeNotifier<GoogleDriveImportState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
