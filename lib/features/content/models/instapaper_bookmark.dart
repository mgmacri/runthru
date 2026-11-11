/// An integer from an Instapaper JSON value, which may arrive as a number
/// (whole or with a fraction) or as a numeric string. Null when it is neither.
int? instapaperInt(Object? value) => switch (value) {
  final int v => v,
  final double v when v.isFinite => v.toInt(),
  final String v =>
    int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.toInt(),
  _ => null,
};

/// A number from an Instapaper JSON value (number or numeric string).
double? instapaperDouble(Object? value) => switch (value) {
  final num v when v.isFinite => v.toDouble(),
  final String v => double.tryParse(v.trim()),
  _ => null,
};

/// A string from an Instapaper JSON value; empty when it is absent or null.
String instapaperString(Object? value) => switch (value) {
  final String v => v,
  null => '',
  _ => value.toString(),
};

/// An Instapaper saved article (bookmark).
///
/// Mirrors the bookmark object from the Instapaper Full API.
/// See: https://www.instapaper.com/developers/v1/full-api/responses
class InstapaperBookmark {
  /// Creates an [InstapaperBookmark] with the given fields.
  const InstapaperBookmark({
    required this.bookmarkId,
    required this.url,
    required this.title,
    this.description = '',
    this.hash = '',
    this.progress = 0.0,
    this.progressTimestamp = 0,
    this.time = 0,
    this.starred = false,
    this.privateSource = '',
  });

  /// Parse from Instapaper API JSON response.
  ///
  /// Throws a [FormatException] when the object has no usable `bookmark_id`.
  factory InstapaperBookmark.fromJson(Map<String, Object?> json) {
    final bookmark = tryFromJson(json);
    if (bookmark == null) throw const FormatException('Missing bookmark_id');
    return bookmark;
  }

  /// Parse from Instapaper API JSON, or null when the object has no usable
  /// `bookmark_id`. Every other field is optional and tolerant of the type
  /// it arrives in, so one odd entry cannot fail a whole list.
  static InstapaperBookmark? tryFromJson(Map<String, Object?> json) {
    final id = instapaperInt(json['bookmark_id']);
    if (id == null) return null;
    final starred = json['starred'];
    return InstapaperBookmark(
      bookmarkId: id,
      url: instapaperString(json['url']),
      title: instapaperString(json['title']),
      description: instapaperString(json['description']),
      hash: instapaperString(json['hash']),
      progress: (instapaperDouble(json['progress']) ?? 0.0).clamp(0.0, 1.0),
      progressTimestamp: instapaperInt(json['progress_timestamp']) ?? 0,
      time: instapaperInt(json['time']) ?? 0,
      starred: starred == true || starred == 1 || starred == '1',
      privateSource: instapaperString(json['private_source']),
    );
  }

  /// Unique bookmark identifier.
  final int bookmarkId;

  /// Original article URL. Private bookmarks (saved by email, for example)
  /// carry a non-functioning `instapaper://private-content/…` value.
  final String url;

  /// Article title.
  final String title;

  /// Brief description or summary.
  final String description;

  /// Hash of URL + title + description + progress (for sync).
  final String hash;

  /// Reading progress (0.0 to 1.0).
  final double progress;

  /// Unix timestamp of last progress update.
  final int progressTimestamp;

  /// Unix timestamp of when the bookmark was saved.
  final int time;

  /// Whether the bookmark is starred.
  final bool starred;

  /// Empty for public bookmarks; source label for private ones.
  final String privateSource;

  /// Whether the bookmark has a web address a browser could open.
  bool get hasWebUrl {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// The site the article came from, for display ("example.com"). Empty for
  /// private bookmarks, which have no site.
  String get domain {
    if (!hasWebUrl) return '';
    final host = Uri.parse(url).host.toLowerCase();
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// The title to show: the article's own, or where it came from when the
  /// title is missing.
  String get displayTitle {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    if (domain.isNotEmpty) return domain;
    if (privateSource.trim().isNotEmpty) return privateSource.trim();
    return 'Untitled article';
  }

  /// Reading progress as a percentage string (e.g. "50%").
  String get progressLabel => '${(progress * 100).round()}%';

  /// Whether the user has started reading this bookmark.
  bool get hasProgress => progress > 0.0;

  /// Returns a copy with the given fields replaced.
  InstapaperBookmark copyWith({
    int? bookmarkId,
    String? url,
    String? title,
    String? description,
    String? hash,
    double? progress,
    int? progressTimestamp,
    int? time,
    bool? starred,
    String? privateSource,
  }) => InstapaperBookmark(
    bookmarkId: bookmarkId ?? this.bookmarkId,
    url: url ?? this.url,
    title: title ?? this.title,
    description: description ?? this.description,
    hash: hash ?? this.hash,
    progress: progress ?? this.progress,
    progressTimestamp: progressTimestamp ?? this.progressTimestamp,
    time: time ?? this.time,
    starred: starred ?? this.starred,
    privateSource: privateSource ?? this.privateSource,
  );

  /// Serialize to JSON map.
  Map<String, Object?> toJson() => {
    'bookmark_id': bookmarkId,
    'url': url,
    'title': title,
    'description': description,
    'hash': hash,
    'progress': progress,
    'progress_timestamp': progressTimestamp,
    'time': time,
    'starred': starred ? '1' : '0',
    'private_source': privateSource,
  };
}
