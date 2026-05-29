/// Drive-aware selected-file picker boundary.
library;

import 'package:runthru/features/content/models/google_drive_file.dart';

/// Picks one or more user-selected Google Drive files.
abstract class GoogleDrivePicker {
  /// Opens a Drive-aware picker and returns selected Drive file IDs.
  Future<List<GoogleDrivePickedFile>> pickFiles({
    required bool allowMultiple,
    required List<String> mimeTypes,
  });
}

/// Metadata returned by a Drive-aware picker for a selected file.
class GoogleDrivePickedFile {
  /// Creates a picked Drive file reference.
  const GoogleDrivePickedFile({
    required this.id,
    required this.name,
    this.mimeType,
    this.sizeBytes,
    this.modifiedTime,
    this.webContentLink,
  });

  /// Google Drive file ID.
  final String id;

  /// User-visible file name.
  final String name;

  /// Drive MIME type, if returned by the picker.
  final String? mimeType;

  /// Blob size in bytes, if returned by the picker.
  final int? sizeBytes;

  /// Last modified time, if returned by the picker.
  final DateTime? modifiedTime;

  /// Optional Drive content link, if returned by the picker.
  final Uri? webContentLink;

  /// Whether the picked item is known to be a Drive folder.
  bool get isFolder => mimeType == googleDriveFolderMimeType;

  /// Whether the picker returned a MIME type RunThru cannot import.
  bool get hasUnsupportedMimeType =>
      mimeType != null && !supportedDriveMimeTypes.contains(mimeType);
}

/// Thrown when this build has no Drive-aware selected-file picker.
class GoogleDrivePickerUnavailableException implements Exception {
  /// Creates an unavailable picker exception.
  const GoogleDrivePickerUnavailableException([
    this.message =
        'Google Drive file picker is not available in this build yet.',
  ]);

  /// User-safe explanation.
  final String message;

  @override
  String toString() => message;
}

/// Production fallback until a native Drive picker adapter is supplied.
class UnavailableGoogleDrivePicker implements GoogleDrivePicker {
  /// Creates an unavailable picker adapter.
  const UnavailableGoogleDrivePicker();

  @override
  Future<List<GoogleDrivePickedFile>> pickFiles({
    required bool allowMultiple,
    required List<String> mimeTypes,
  }) async {
    throw const GoogleDrivePickerUnavailableException();
  }
}
