/// An Instapaper saved article (bookmark).
///
/// Mirrors the bookmark object from the Instapaper Full API.
/// See: https://www.instapaper.com/api/full
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
  factory InstapaperBookmark.fromJson(Map<String, Object?> json) {
    return InstapaperBookmark(
      bookmarkId: json['bookmark_id'] as int,
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      hash: json['hash'] as String? ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      progressTimestamp: json['progress_timestamp'] as int? ?? 0,
      time: json['time'] as int? ?? 0,
      starred: json['starred'] == '1' || json['starred'] == true,
      privateSource: json['private_source'] as String? ?? '',
    );
  }

  /// Unique bookmark identifier.
  final int bookmarkId;

  /// Original article URL.
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

  /// The domain portion of the URL for display.
  String get domain {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  /// Reading progress as a percentage string (e.g. "50%").
  String get progressLabel => '${(progress * 100).round()}%';

  /// Whether the user has started reading this bookmark.
  bool get hasProgress => progress > 0.0;

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
