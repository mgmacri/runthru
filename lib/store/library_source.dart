import 'package:flutter/foundation.dart';

/// Whether a [LibrarySource] points at a folder to scan or a single file.
enum LibrarySourceKind {
  /// A directory scanned (recursively) for PDF/EPUB files.
  folder,

  /// A single PDF/EPUB file.
  file,
}

/// A user-added library location — the durable, slim record of *what the user
/// added* to their library.
///
/// The scanned books a source yields are **derived** (see `pdfListProvider`)
/// and are not persisted here. Only the handful of sources are stored, which
/// keeps the persisted payload tiny regardless of library size.
@immutable
class LibrarySource {
  /// Creates a library source.
  const LibrarySource({
    required this.id,
    required this.kind,
    required this.locator,
    required this.displayName,
    required this.addedAt,
    this.ownsFiles = false,
    this.sourceKey,
  });

  /// Rebuilds a source from its [toJson] map, tolerating missing/unknown fields.
  factory LibrarySource.fromJson(Map<String, Object?> json) {
    return LibrarySource(
      id: json['id'] as String? ?? '',
      kind:
          LibrarySourceKind.values.asNameMap()[json['kind'] as String? ?? ''] ??
          LibrarySourceKind.folder,
      locator: json['locator'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      ownsFiles: json['ownsFiles'] as bool? ?? false,
      sourceKey: json['sourceKey'] as String?,
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Stable unique identifier for this source.
  final String id;

  /// Whether [locator] is a folder or a single file.
  final LibrarySourceKind kind;

  /// Filesystem path of the folder/file. A real OS path for referenced sources;
  /// an app-managed directory when [ownsFiles] is true.
  final String locator;

  /// Human-readable label shown in the sources list.
  final String displayName;

  /// True when [locator] is an app-managed copy that must be deleted when the
  /// source is removed. False for in-place references to the user's own files,
  /// which are never touched on removal.
  final bool ownsFiles;

  /// When the source was added.
  final DateTime addedAt;

  /// Optional stable identity for sources copied into app storage.
  ///
  /// On platforms that copy a picked folder into a fresh app-private directory,
  /// [locator] changes on every import. This key preserves the original picker
  /// identity so re-adding the same folder can be treated as a duplicate.
  final String? sourceKey;

  /// Returns a copy with the given fields replaced.
  LibrarySource copyWith({
    String? id,
    LibrarySourceKind? kind,
    String? locator,
    String? displayName,
    bool? ownsFiles,
    DateTime? addedAt,
    String? sourceKey,
  }) {
    return LibrarySource(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      locator: locator ?? this.locator,
      displayName: displayName ?? this.displayName,
      ownsFiles: ownsFiles ?? this.ownsFiles,
      addedAt: addedAt ?? this.addedAt,
      sourceKey: sourceKey ?? this.sourceKey,
    );
  }

  /// Serializes to a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'locator': locator,
    'displayName': displayName,
    'ownsFiles': ownsFiles,
    'sourceKey': sourceKey,
    'addedAt': addedAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is LibrarySource && other.id == id && other.locator == locator;

  @override
  int get hashCode => Object.hash(id, locator);
}
