/// Model representing content shared into RunThru from external sources.
///
/// Distinguishes between content types so the ingestion pipeline can route
/// each to the appropriate extractor. Content stays on-device only.
library;

/// The type of content received via share intent or file picker.
enum SharedContentType {
  /// Plain text (clipboard paste, ACTION_SEND text/plain).
  text,

  /// A URL to fetch and normalise (ACTION_VIEW http/https).
  url,

  /// A PDF file path in app-private storage.
  pdfFile,

  /// An EPUB file path in app-private storage.
  epubFile,

  /// HTML text (ACTION_SEND text/html).
  htmlText,
}

/// The action to perform with shared content.
enum ShareAction {
  /// Open the reading screen immediately (RSVP pacing).
  readNow,

  /// Import to the library for later reading.
  import_,
}

/// Immutable model for content shared into the app.
///
/// Created by the share intent handler or file picker, then routed through
/// the content extraction pipeline to produce an [ExtractedDocument].
class SharedContent {
  /// Creates a [SharedContent] instance.
  const SharedContent({
    required this.type,
    required this.data,
    this.title,
    this.mimeType,
    this.receivedAt,
    this.action = ShareAction.readNow,
  });

  /// Creates a [SharedContent] for plain text.
  factory SharedContent.text(String text, {String? title}) => SharedContent(
    type: SharedContentType.text,
    data: text,
    title: title,
    mimeType: 'text/plain',
  );

  /// Creates a [SharedContent] for a URL.
  factory SharedContent.url(String url, {String? title}) =>
      SharedContent(type: SharedContentType.url, data: url, title: title);

  /// Creates a [SharedContent] for a PDF file path.
  factory SharedContent.pdfFile(String filePath, {String? title}) =>
      SharedContent(
        type: SharedContentType.pdfFile,
        data: filePath,
        title: title,
        mimeType: 'application/pdf',
      );

  /// Creates a [SharedContent] for an EPUB file path.
  factory SharedContent.epubFile(String filePath, {String? title}) =>
      SharedContent(
        type: SharedContentType.epubFile,
        data: filePath,
        title: title,
        mimeType: 'application/epub+zip',
      );

  /// Creates a [SharedContent] for HTML text.
  factory SharedContent.htmlText(String html, {String? title}) => SharedContent(
    type: SharedContentType.htmlText,
    data: html,
    title: title,
    mimeType: 'text/html',
  );

  /// Deserialises from a map (e.g. from platform channel or App Group JSON).
  factory SharedContent.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String? ?? 'text';
    final type = SharedContentType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => SharedContentType.text,
    );
    return SharedContent(
      type: type,
      data: map['data'] as String? ?? '',
      title: map['title'] as String?,
      mimeType: map['mimeType'] as String?,
      receivedAt: map['receivedAt'] != null
          ? DateTime.tryParse(map['receivedAt'] as String)
          : null,
      action: (map['action'] as String?) == 'import'
          ? ShareAction.import_
          : ShareAction.readNow,
    );
  }

  /// The type of shared content for routing.
  final SharedContentType type;

  /// The content payload — text string, URL string, or file path.
  final String data;

  /// Optional display title (e.g. filename, page title).
  final String? title;

  /// Original MIME type from the share intent, if available.
  final String? mimeType;

  /// When this content was received. Null uses [DateTime.now] on access.
  final DateTime? receivedAt;

  /// The action to perform: read immediately or import for later.
  final ShareAction action;

  /// Convenience: timestamp of receipt.
  DateTime get timestamp => receivedAt ?? DateTime.now();

  /// Serialises to a map for platform channel or App Group JSON.
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'data': data,
    if (title != null) 'title': title,
    if (mimeType != null) 'mimeType': mimeType,
    'receivedAt': (receivedAt ?? DateTime.now()).toIso8601String(),
    'action': action == ShareAction.import_ ? 'import' : 'readNow',
  };
}
