/// Classifies regions of extracted text that are likely non-prose artifacts
/// (tables, code blocks, figure captions, page markers, references) which
/// degrade the RSVP reading experience.
///
/// Designed to run in an isolate — no Flutter or FFI dependencies.
library;

/// A detected artifact region within a word list.
class ArtifactRegion {
  /// Creates an artifact region spanning [startIndex] to [endIndex] inclusive.
  const ArtifactRegion({
    required this.startIndex,
    required this.endIndex,
    required this.type,
    required this.confidence,
  });

  /// Index of first word in the artifact (inclusive).
  final int startIndex;

  /// Index of last word in the artifact (inclusive).
  final int endIndex;

  /// The type of artifact detected.
  final ArtifactType type;

  /// Detection confidence from 0.0 (guess) to 1.0 (certain).
  final double confidence;

  /// Number of words in this region.
  int get length => endIndex - startIndex + 1;
}

/// Types of artifacts that can be detected.
enum ArtifactType {
  /// Tabular data — columns, delimiters, repeated numeric patterns.
  table,

  /// Code blocks — braces, semicolons, indentation patterns.
  codeBlock,

  /// Figure/table captions — "Figure 1:", "Table 2:", etc.
  caption,

  /// Page numbers and headers/footers.
  pageMarker,

  /// Bibliographic references — "[1]", "(Author, 2023)", etc.
  reference,
}

/// Scan a word list and return detected artifact regions.
///
/// This function is isolate-safe — call via
/// `Isolate.run(() => classifyArtifacts(words))`.
List<ArtifactRegion> classifyArtifacts(List<String> words) {
  final regions = <ArtifactRegion>[];
  regions.addAll(_detectTables(words));
  regions.addAll(_detectCodeBlocks(words));
  regions.addAll(_detectCaptions(words));
  regions.addAll(_detectPageMarkers(words));
  regions.addAll(_detectReferences(words));
  return _mergeOverlapping(regions);
}

List<ArtifactRegion> _detectTables(List<String> words) {
  const windowSize = 10;
  final regions = <ArtifactRegion>[];
  if (words.length < windowSize) return regions;
  for (int i = 0; i <= words.length - windowSize; i++) {
    final window = words.sublist(i, i + windowSize);
    int matchCount = 0;
    for (final w in window) {
      if (w == '|' ||
          w == '-' ||
          w == '_' ||
          RegExp(r'^[0-9.]+$').hasMatch(w) ||
          w.contains('|') ||
          (w.length == 1 && !RegExp(r'^[a-zA-Z]$').hasMatch(w)) ||
          (w.length <= 3 && RegExp(r'^[0-9|_.\-]+$').hasMatch(w))) {
        matchCount++;
      }
    }
    if (matchCount >= 5) {
      regions.add(
        ArtifactRegion(
          startIndex: i,
          endIndex: i + windowSize - 1,
          type: ArtifactType.table,
          confidence: matchCount / windowSize,
        ),
      );
    }
  }
  return regions;
}

List<ArtifactRegion> _detectCodeBlocks(List<String> words) {
  final regions = <ArtifactRegion>[];
  final codeSignals = <String>[
    '{',
    '}',
    ';',
    '//',
    '/*',
    '->',
    '=>',
    '==',
    '!=',
    '>=',
    '<=',
  ];

  // Standard 15-word window
  const windowSize = 15;
  if (words.length >= windowSize) {
    for (int i = 0; i <= words.length - windowSize; i++) {
      final window = words.sublist(i, i + windowSize);
      int signalCount = 0;
      bool hasBacktick = false;
      for (final w in window) {
        for (final sig in codeSignals) {
          if (w.contains(sig)) signalCount++;
        }
        if (w.contains('`')) hasBacktick = true;
      }
      if (signalCount >= 6) {
        regions.add(
          ArtifactRegion(
            startIndex: i,
            endIndex: i + windowSize - 1,
            type: ArtifactType.codeBlock,
            confidence: hasBacktick ? 0.9 : 0.7,
          ),
        );
      }
    }
  }

  // Short code block detection (7+ words with 4+ signals)
  const shortWindow = 7;
  if (words.length >= shortWindow) {
    for (int i = 0; i <= words.length - shortWindow; i++) {
      final window = words.sublist(i, i + shortWindow);
      int signalCount = 0;
      bool hasBacktick = false;
      for (final w in window) {
        for (final sig in codeSignals) {
          if (w.contains(sig)) signalCount++;
        }
        if (w.contains('`')) hasBacktick = true;
      }
      if (signalCount >= 3) {
        regions.add(
          ArtifactRegion(
            startIndex: i,
            endIndex: i + shortWindow - 1,
            type: ArtifactType.codeBlock,
            confidence: hasBacktick ? 0.9 : 0.7,
          ),
        );
      }
    }
  }

  return regions;
}

List<ArtifactRegion> _detectCaptions(List<String> words) {
  final regions = <ArtifactRegion>[];
  for (int i = 0; i < words.length - 1; i++) {
    final w = words[i].toLowerCase();
    if ((w == 'figure' || w == 'fig.' || w == 'table' || w == 'chart') &&
        _isNumberish(words[i + 1])) {
      regions.add(
        ArtifactRegion(
          startIndex: i,
          endIndex: i + 1,
          type: ArtifactType.caption,
          confidence: 0.85,
        ),
      );
    }
  }
  return regions;
}

List<ArtifactRegion> _detectPageMarkers(List<String> words) {
  final regions = <ArtifactRegion>[];
  for (int i = 0; i < words.length; i++) {
    final w = words[i];
    if (!RegExp(r'^[0-9]{1,4}$').hasMatch(w)) continue;

    final prev = i > 0 ? words[i - 1] : '';
    final next = i < words.length - 1 ? words[i + 1] : '';

    // Skip if adjacent to lowercase words (likely part of prose)
    if (_isLowercase(next)) continue;
    if (_isLowercase(prev)) continue;

    // Skip if adjacent to other numbers
    if (_isNumberish(prev) || _isNumberish(next)) continue;

    // Skip if surrounded by pure-alpha words (e.g. "were 42 people")
    if (prev.isNotEmpty &&
        RegExp(r'^[a-z]+$').hasMatch(prev) &&
        next.isNotEmpty &&
        RegExp(r'^[a-zA-Z]+$').hasMatch(next)) {
      continue;
    }

    regions.add(
      ArtifactRegion(
        startIndex: i,
        endIndex: i,
        type: ArtifactType.pageMarker,
        confidence: 0.5,
      ),
    );
  }
  return regions;
}

List<ArtifactRegion> _detectReferences(List<String> words) {
  final regions = <ArtifactRegion>[];
  for (int i = 0; i < words.length; i++) {
    final w = words[i];
    if (RegExp(r'^\[[0-9]{1,3}\]$').hasMatch(w)) {
      regions.add(
        ArtifactRegion(
          startIndex: i,
          endIndex: i,
          type: ArtifactType.reference,
          confidence: 0.75,
        ),
      );
    } else if (i < words.length - 2) {
      final joined = '${words[i]} ${words[i + 1]} ${words[i + 2]}';
      if (RegExp(r'^\([A-Za-z][A-Za-z .-]*,\s*[0-9]{4}\)$').hasMatch(joined)) {
        regions.add(
          ArtifactRegion(
            startIndex: i,
            endIndex: i + 2,
            type: ArtifactType.reference,
            confidence: 0.75,
          ),
        );
      }
    }
  }
  return regions;
}

List<ArtifactRegion> _mergeOverlapping(List<ArtifactRegion> regions) {
  if (regions.isEmpty) return [];
  regions.sort((a, b) => a.startIndex.compareTo(b.startIndex));
  final merged = <ArtifactRegion>[];
  ArtifactRegion current = regions.first;
  for (int i = 1; i < regions.length; i++) {
    final next = regions[i];
    if (next.startIndex <= current.endIndex + 2) {
      final keepNext = next.confidence > current.confidence;
      current = ArtifactRegion(
        startIndex: current.startIndex,
        endIndex: next.endIndex > current.endIndex
            ? next.endIndex
            : current.endIndex,
        type: keepNext ? next.type : current.type,
        confidence: keepNext ? next.confidence : current.confidence,
      );
    } else {
      merged.add(current);
      current = next;
    }
  }
  merged.add(current);
  return merged;
}

bool _isNumberish(String s) => RegExp(r'^[0-9]+[:\.]?$').hasMatch(s);

bool _isLowercase(String s) =>
    s.isNotEmpty &&
    RegExp(r'^[a-z]').hasMatch(s) &&
    !RegExp(r'[.!?;:,]$').hasMatch(s);
