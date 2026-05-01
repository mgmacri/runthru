import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/section_store.dart';

void main() {
  group('SectionStore', () {
    test('splitIntoSections divides evenly', () {
      final sentences = List.generate(
        400,
        (i) => Sentence(words: ['word_$i']),
      );
      final doc = ExtractedDocument(sentences: sentences);
      final sections = SectionStore.splitIntoSections(doc);

      expect(sections.length, 2);
      expect(sections[0].sectionIndex, 0);
      expect(sections[0].startSentenceIndex, 0);
      expect(sections[0].sentences.length, 200);
      expect(sections[1].sectionIndex, 1);
      expect(sections[1].startSentenceIndex, 200);
      expect(sections[1].sentences.length, 200);
    });

    test('splitIntoSections handles remainder', () {
      final sentences = List.generate(
        350,
        (i) => Sentence(words: ['word_$i']),
      );
      final doc = ExtractedDocument(sentences: sentences);
      final sections = SectionStore.splitIntoSections(doc);

      expect(sections.length, 2);
      expect(sections[0].sentences.length, 200);
      expect(sections[1].sentences.length, 150);
      expect(sections[1].startSentenceIndex, 200);
    });

    test('splitIntoSections handles small document', () {
      final sentences = List.generate(
        50,
        (i) => Sentence(words: ['word_$i']),
      );
      final doc = ExtractedDocument(sentences: sentences);
      final sections = SectionStore.splitIntoSections(doc);

      expect(sections.length, 1);
      expect(sections[0].sentences.length, 50);
    });

    test('splitIntoSections handles empty document', () {
      const doc = ExtractedDocument(sentences: []);
      final sections = SectionStore.splitIntoSections(doc);
      expect(sections, isEmpty);
    });

    test('buildManifest computes correct metadata', () {
      final sentences = List.generate(
        450,
        (i) => Sentence(words: ['word_${i}a', 'word_${i}b']),
      );
      final doc = ExtractedDocument(sentences: sentences);
      final manifest = SectionStore.buildManifest('test.pdf', 'abc123', doc);

      expect(manifest.filePath, 'test.pdf');
      expect(manifest.fileHash, 'abc123');
      expect(manifest.totalSentences, 450);
      expect(manifest.totalWords, 900);
      expect(manifest.totalSections, 3); // ceil(450/200)
      expect(manifest.sectionSize, 200);
    });

    test('fileHash produces consistent 16-char hex', () {
      // fileHash depends on file existence, so test the format
      final hash = SectionStore.fileHash('/nonexistent/path.pdf');
      expect(hash.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(hash), isTrue);
    });

    test('fileHash is deterministic', () {
      final a = SectionStore.fileHash('/some/file.pdf');
      final b = SectionStore.fileHash('/some/file.pdf');
      expect(a, b);
    });
  });

  group('SectionData', () {
    test('JSON round-trip', () {
      const section = SectionData(
        sectionIndex: 2,
        startSentenceIndex: 400,
        sentences: [
          Sentence(words: ['hello', 'world']),
          Sentence(words: ['foo']),
        ],
      );
      final json = section.toJson();
      final restored = SectionData.fromJson(json);

      expect(restored.sectionIndex, 2);
      expect(restored.startSentenceIndex, 400);
      expect(restored.sentences.length, 2);
      expect(restored.sentences[0].words, ['hello', 'world']);
      expect(restored.totalWords, 3);
    });
  });

  group('DocumentManifest', () {
    test('JSON round-trip', () {
      final manifest = DocumentManifest(
        filePath: '/docs/test.pdf',
        fileHash: 'abc123def456',
        totalSentences: 1000,
        totalWords: 8000,
        totalSections: 5,
        sectionSize: 200,
        pageMap: {0: 0, 1: 42, 2: 100},
        lastModified: DateTime(2025, 6, 1),
        createdAt: DateTime(2025, 5, 30),
      );
      final json = manifest.toJson();
      final restored = DocumentManifest.fromJson(json);

      expect(restored.filePath, '/docs/test.pdf');
      expect(restored.fileHash, 'abc123def456');
      expect(restored.totalSentences, 1000);
      expect(restored.totalWords, 8000);
      expect(restored.totalSections, 5);
      expect(restored.sectionSize, 200);
      expect(restored.pageMap, {0: 0, 1: 42, 2: 100});
    });
  });

  group('StoreIndex', () {
    test('touch updates timestamp', () {
      const index = StoreIndex(entries: {});
      final updated = index.touch('hash1');
      expect(updated.entries.containsKey('hash1'), isTrue);
    });

    test('remove deletes entry', () {
      final index = StoreIndex(entries: {'hash1': DateTime.now()});
      final updated = index.remove('hash1');
      expect(updated.entries.containsKey('hash1'), isFalse);
    });

    test('JSON round-trip', () {
      final now = DateTime.now();
      final index = StoreIndex(entries: {'h1': now, 'h2': now});
      final json = index.toJson();
      final restored = StoreIndex.fromJson(json);
      expect(restored.entries.length, 2);
      expect(restored.entries.containsKey('h1'), isTrue);
    });
  });

  group('PageBoundary', () {
    test('JSON round-trip', () {
      const boundary = PageBoundary(
        pageNumber: 3,
        startSentenceIndex: 42,
        startWordIndex: 200,
        firstWords: 'The quick brown fox',
      );
      final json = boundary.toJson();
      final restored = PageBoundary.fromJson(json);

      expect(restored.pageNumber, 3);
      expect(restored.startSentenceIndex, 42);
      expect(restored.startWordIndex, 200);
      expect(restored.firstWords, 'The quick brown fox');
    });
  });

  group('ReadingRange', () {
    test('JSON round-trip', () {
      const range = ReadingRange(
        startPage: 5,
        startWordIndexOnPage: 10,
        startWordAnchor: 'chapter',
        endPage: 20,
        endWordIndexOnPage: 50,
        endWordAnchor: 'conclusion',
        resolvedStartWordIndex: 500,
        resolvedEndWordIndex: 2000,
      );
      final json = range.toJson();
      final restored = ReadingRange.fromJson(json);

      expect(restored.startPage, 5);
      expect(restored.startWordIndexOnPage, 10);
      expect(restored.startWordAnchor, 'chapter');
      expect(restored.endPage, 20);
      expect(restored.endWordIndexOnPage, 50);
      expect(restored.resolvedStartWordIndex, 500);
      expect(restored.resolvedEndWordIndex, 2000);
    });

    test('copyWith preserves unchanged fields', () {
      const range = ReadingRange(startPage: 1, endPage: 10);
      final updated = range.copyWith(endPage: 15);
      expect(updated.startPage, 1);
      expect(updated.endPage, 15);
    });
  });

  group('resolveRange', () {
    test('resolves page+word to global indices', () {
      final boundaries = [
        const PageBoundary(
            pageNumber: 0,
            startSentenceIndex: 0,
            startWordIndex: 0,
            firstWords: 'Start'),
        const PageBoundary(
            pageNumber: 1,
            startSentenceIndex: 10,
            startWordIndex: 100,
            firstWords: 'Page two'),
        const PageBoundary(
            pageNumber: 2,
            startSentenceIndex: 20,
            startWordIndex: 200,
            firstWords: 'Page three'),
      ];

      const range = ReadingRange(
        startPage: 1,
        startWordIndexOnPage: 5,
        endPage: 2,
        endWordIndexOnPage: 10,
      );

      final result = resolveRange(range, boundaries);
      expect(result.globalStart, 105); // 100 + 5
      expect(result.globalEnd, 210); // 200 + 10
    });
  });
}
