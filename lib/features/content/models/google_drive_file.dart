/// Google Drive file metadata used by the RunThru import flow.
library;

/// Google Drive MIME type for Google Docs documents.
const String googleDocsMimeType = 'application/vnd.google-apps.document';

/// Google Drive MIME type for folders.
const String googleDriveFolderMimeType = 'application/vnd.google-apps.folder';

/// PDF MIME type.
const String pdfMimeType = 'application/pdf';

/// EPUB MIME type.
const String epubMimeType = 'application/epub+zip';

/// Plain text MIME type.
const String plainTextMimeType = 'text/plain';

/// HTML MIME type.
const String htmlMimeType = 'text/html';

/// Stable Drive file metadata safe for UI display.
class GoogleDriveFile {
  /// Creates a Drive file metadata object.
  const GoogleDriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    this.modifiedTime,
    this.sizeBytes,
  });

  /// Builds metadata from a Drive API v3 file resource.
  factory GoogleDriveFile.fromJson(Map<String, Object?> json) {
    final rawSize = json['size'];
    return GoogleDriveFile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      mimeType: json['mimeType'] as String? ?? '',
      modifiedTime: json['modifiedTime'] is String
          ? DateTime.tryParse(json['modifiedTime']! as String)
          : null,
      sizeBytes: rawSize is String ? int.tryParse(rawSize) : null,
    );
  }

  /// Drive file ID.
  final String id;

  /// User-visible Drive file name.
  final String name;

  /// Drive MIME type.
  final String mimeType;

  /// Last modified timestamp, if returned by Drive.
  final DateTime? modifiedTime;

  /// Blob size in bytes for downloadable files. Google Docs omit this.
  final int? sizeBytes;

  /// Stable source ID used for local RunThru reading progress.
  String get sourceId => 'drive://$id';

  /// Whether RunThru can import this file.
  bool get isSupported => supportedDriveMimeTypes.contains(mimeType);

  /// Whether this item is a Drive folder.
  bool get isFolder => mimeType == googleDriveFolderMimeType;

  /// Whether this file must be exported instead of downloaded.
  bool get isGoogleDoc => mimeType == googleDocsMimeType;

  /// Preferred file extension for temporary local storage.
  String get extension => switch (mimeType) {
    googleDocsMimeType => 'txt',
    pdfMimeType => 'pdf',
    epubMimeType => 'epub',
    htmlMimeType => 'html',
    _ => 'txt',
  };
}

/// MIME types displayed and importable from Drive.
const Set<String> supportedDriveMimeTypes = {
  googleDocsMimeType,
  pdfMimeType,
  epubMimeType,
  plainTextMimeType,
  htmlMimeType,
};

/// Drive search query fragment for supported RunThru file types.
String supportedDriveMimeQuery() {
  return supportedDriveMimeTypes
      .map((type) => "mimeType = '$type'")
      .join(' or ');
}
