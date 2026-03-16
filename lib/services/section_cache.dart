import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/services/models.dart';
import 'package:speedy_boy/services/section_store.dart';

/// In-memory LRU section cache with prefetch support.
///
/// Holds at most [_maxSections] sections across all PDFs. When the limit is
/// exceeded the least-recently-used section is evicted (disk copy remains).
class SectionCacheNotifier
    extends StateNotifier<Map<String, Map<int, SectionData>>> {
  SectionCacheNotifier() : super({});

  static const int _maxSections = 10;

  // Track access order: most recent at end.
  final List<({String filePath, int sectionIndex})> _lruOrder = [];

  /// Load a single section — returns from cache or disk.
  Future<SectionData?> loadSection(String filePath, int sectionIndex) async {
    // 1. In-memory hit
    final cached = state[filePath]?[sectionIndex];
    if (cached != null) {
      _touch(filePath, sectionIndex);
      return cached;
    }

    // 2. Load from disk
    final hash = SectionStore.fileHash(filePath);
    final dir = await SectionStore.storeDir(hash);
    if (dir == null) return null;

    final data = await SectionStore.loadSectionInIsolate(dir, sectionIndex);
    if (data == null) return null;

    _put(filePath, sectionIndex, data);
    return data;
  }

  /// Prefetch the next [lookahead] sections in the background.
  Future<void> prefetchSections(
    String filePath,
    int currentSectionIndex, {
    int lookahead = 2,
  }) async {
    for (var i = 1; i <= lookahead; i++) {
      final idx = currentSectionIndex + i;
      if (state[filePath]?.containsKey(idx) ?? false) continue;
      // Fire-and-forget — errors are non-critical
      loadSection(filePath, idx).catchError((Object e) {
        dev.log('Prefetch section $idx failed: $e', name: 'section_cache');
        return null;
      });
    }
  }

  /// Resolve a global word index to section + local indices.
  static ({int sectionIndex, int localSentenceIndex, int localWordIndex})
      resolveWord(DocumentManifest manifest, int globalWordIndex) {
    final sectionSize = manifest.sectionSize;
    // Walk sentences to find the target
    var sentenceIdx = 0;
    // We don't have full sentence data in the manifest, so approximate:
    // Each section holds sectionSize sentences. We need to find which section
    // the global word falls into by walking.
    // For a precise resolution the caller should provide sections, but
    // this approximation works when sentence lengths average ~10 words.
    final avgWordsPerSentence =
        manifest.totalWords / manifest.totalSentences.clamp(1, 999999);
    final approxSentence = (globalWordIndex / avgWordsPerSentence).floor();
    final sectionIndex = (approxSentence / sectionSize).floor();

    // Local indices within the section
    final localSentenceStart = sectionIndex * sectionSize;
    sentenceIdx = approxSentence - localSentenceStart;

    return (
      sectionIndex: sectionIndex.clamp(0, manifest.totalSections - 1),
      localSentenceIndex: sentenceIdx.clamp(0, sectionSize - 1),
      localWordIndex: 0, // Precise resolution needs actual section data
    );
  }

  /// Precise resolution using actual section data.
  static ({int sectionIndex, int localSentenceIndex, int localWordIndex})
      resolveWordPrecise(
    DocumentManifest manifest,
    int globalWordIndex,
    Map<int, SectionData> loadedSections,
  ) {
    var wordsSoFar = 0;
    final sortedKeys = loadedSections.keys.toList()..sort();

    for (final secIdx in sortedKeys) {
      final section = loadedSections[secIdx]!;
      for (var si = 0; si < section.sentences.length; si++) {
        final sentenceWords = section.sentences[si].words.length;
        if (wordsSoFar + sentenceWords > globalWordIndex) {
          return (
            sectionIndex: secIdx,
            localSentenceIndex: si,
            localWordIndex: globalWordIndex - wordsSoFar,
          );
        }
        wordsSoFar += sentenceWords;
      }
    }

    // Past end — return last position
    final lastKey = sortedKeys.isNotEmpty ? sortedKeys.last : 0;
    return (sectionIndex: lastKey, localSentenceIndex: 0, localWordIndex: 0);
  }

  void _put(String filePath, int sectionIndex, SectionData data) {
    _evictIfNeeded();

    final updated = Map<String, Map<int, SectionData>>.from(state);
    updated.putIfAbsent(filePath, () => {});
    updated[filePath] = Map<int, SectionData>.from(updated[filePath]!);
    updated[filePath]![sectionIndex] = data;
    state = updated;

    _touch(filePath, sectionIndex);
  }

  void _touch(String filePath, int sectionIndex) {
    _lruOrder.removeWhere(
      (e) => e.filePath == filePath && e.sectionIndex == sectionIndex,
    );
    _lruOrder.add((filePath: filePath, sectionIndex: sectionIndex));
  }

  void _evictIfNeeded() {
    while (_lruOrder.length >= _maxSections) {
      final victim = _lruOrder.removeAt(0);
      final fileMap = state[victim.filePath];
      if (fileMap != null) {
        final updated = Map<String, Map<int, SectionData>>.from(state);
        updated[victim.filePath] =
            Map<int, SectionData>.from(updated[victim.filePath]!);
        updated[victim.filePath]!.remove(victim.sectionIndex);
        if (updated[victim.filePath]!.isEmpty) {
          updated.remove(victim.filePath);
        }
        state = updated;
      }
    }
  }
}

final sectionCacheProvider = StateNotifierProvider<SectionCacheNotifier,
    Map<String, Map<int, SectionData>>>((ref) {
  return SectionCacheNotifier();
});

/// Storage usage provider.
final storageUsageProvider =
    FutureProvider<({int usedBytes, int budgetBytes, double percent})>(
        (ref) async {
  const budget = 200 * 1024 * 1024; // 200 MB
  final used = await SectionStore.totalDiskUsage();
  return (
    usedBytes: used,
    budgetBytes: budget,
    percent: used / budget,
  );
});
