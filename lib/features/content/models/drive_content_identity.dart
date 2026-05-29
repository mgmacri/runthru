/// Canonical identity model for a Google Drive file in RunThru.
library;

import 'package:runthru/features/content/models/google_drive_file.dart';

/// Stable identity and revision metadata for a Google Drive file.
///
/// All Drive import, progress, and cache paths should derive identity through
/// this model rather than constructing `drive://` strings ad-hoc.
class DriveContentIdentity {
  /// Creates a Drive content identity.
  const DriveContentIdentity({
    required this.fileId,
    required this.name,
    required this.mimeType,
    this.modifiedTime,
    this.sizeBytes,
    this.exportMimeType,
  });

  /// Builds a Drive content identity from a [GoogleDriveFile].
  ///
  /// Sets [exportMimeType] to [plainTextMimeType] for Google Docs, matching the
  /// default export format used by the Drive client.
  factory DriveContentIdentity.fromGoogleDriveFile(GoogleDriveFile file) {
    return DriveContentIdentity(
      fileId: file.id,
      name: file.name,
      mimeType: file.mimeType,
      modifiedTime: file.modifiedTime,
      sizeBytes: file.sizeBytes,
      exportMimeType: file.isGoogleDoc ? plainTextMimeType : null,
    );
  }

  /// Drive file ID.
  final String fileId;

  /// User-visible Drive file name.
  final String name;

  /// Drive MIME type.
  final String mimeType;

  /// Last modified timestamp from the Drive API, if available.
  final DateTime? modifiedTime;

  /// Blob size in bytes. Null for Google Docs, which have no download size.
  final int? sizeBytes;

  /// Export MIME type override. Non-null only when the file must be exported
  /// rather than downloaded (e.g. Google Docs → plain text).
  final String? exportMimeType;

  /// Stable source ID used for local RunThru reading progress.
  String get sourceId => 'drive://$fileId';

  /// Revision key used for cache invalidation.
  ///
  /// Uses the ISO-8601 UTC modified time when available. Returns null when
  /// Drive did not provide revision metadata so callers do not confuse a stable
  /// file identity for a content revision.
  String? get sourceRevisionKey => modifiedTime?.toUtc().toIso8601String();

  /// Two identities are equal when they refer to the same Drive file.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DriveContentIdentity && other.fileId == fileId;

  @override
  int get hashCode => fileId.hashCode;

  @override
  String toString() =>
      'DriveContentIdentity(fileId: $fileId, name: $name, mimeType: $mimeType)';
}
