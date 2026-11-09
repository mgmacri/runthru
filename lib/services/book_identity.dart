/// Canonical book identity for the content pipeline.
///
/// Identity is the **content hash** — sha256 of the raw file bytes. Paths,
/// filenames, and source-specific IDs are locators, not identity: mobile
/// re-imports copy files into fresh directories, and two unrelated books can
/// both be called `book.pdf`. Everything durable (cache entries, bookmarks,
/// reading progress) keys on [contentHash] so it survives re-imports and
/// never collides across distinct content.
library;

import 'package:flutter/foundation.dart';

/// Stable identity of one piece of content across the whole pipeline.
@immutable
class BookIdentity {
  /// Creates a book identity.
  const BookIdentity({
    required this.contentHash,
    required this.sourceId,
    required this.displayName,
  });

  /// sha256 hex digest of the raw file bytes — the canonical identity.
  ///
  /// While bytes are not yet fully available (e.g. mid-download) callers use
  /// a provisional identity from [provisionalHash] and upgrade on completion.
  final String contentHash;

  /// Stable integration source identifier: `local`, `drive:<fileId>`,
  /// `instapaper:<bookmarkId>`, …
  final String sourceId;

  /// User-visible name. Mutable in spirit — never part of identity.
  final String displayName;

  /// Whether this identity is provisional (content not fully hashed yet).
  bool get isProvisional => contentHash.startsWith(provisionalPrefix);

  /// Prefix marking provisional identities.
  static const String provisionalPrefix = 'prov:';

  /// Provisional identity for content whose bytes are not yet complete.
  static String provisionalHash(String sourceId, String locator) =>
      '$provisionalPrefix$sourceId:$locator';

  @override
  bool operator ==(Object other) =>
      other is BookIdentity && other.contentHash == contentHash;

  @override
  int get hashCode => contentHash.hashCode;

  @override
  String toString() =>
      'BookIdentity(${contentHash.length > 12 ? contentHash.substring(0, 12) : contentHash}…, $sourceId)';
}

/// Normalises a file path for use as a provisional dedup key.
String canonicalPathKey(String filePath) => filePath.replaceAll('\\', '/');
