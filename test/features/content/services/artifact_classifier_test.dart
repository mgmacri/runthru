import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/services/artifact_classifier.dart';

void main() {
  group('classifyArtifacts', () {
    test('returns empty list for plain prose', () {
      final words =
          'The quick brown fox jumps over the lazy dog and runs away quickly today'
              .split(' ');
      expect(classifyArtifacts(words), isEmpty);
    });

    test('returns empty list for empty input', () {
      expect(classifyArtifacts([]), isEmpty);
    });

    test('detects pipe-delimited table content', () {
      final words = [
        'Name',
        '|',
        'Age',
        '|',
        'City',
        'John',
        '|',
        '30',
        '|',
        'NYC',
      ];
      final regions = classifyArtifacts(words);
      expect(regions, isNotEmpty);
      expect(regions.first.type, ArtifactType.table);
    });

    test('detects code block with braces and semicolons', () {
      final words = ['void', 'main()', '{', 'print(', '"hello"', ');', '}'];
      final regions = classifyArtifacts(words);
      expect(regions, isNotEmpty);
      expect(regions.first.type, ArtifactType.codeBlock);
    });

    test('detects figure caption', () {
      final words = [
        'Figure',
        '1:',
        'The',
        'relationship',
        'between',
        'variables',
      ];
      final regions = classifyArtifacts(words);
      expect(regions, isNotEmpty);
      expect(regions.first.type, ArtifactType.caption);
      expect(regions.first.startIndex, 0);
    });

    test('detects "Fig." caption variant', () {
      final words = ['See', 'Fig.', '3', 'for', 'details'];
      final regions = classifyArtifacts(words);
      final captions = regions.where((r) => r.type == ArtifactType.caption);
      expect(captions, isNotEmpty);
    });

    test('detects "Table" caption', () {
      final words = ['Table', '2:', 'Summary', 'of', 'results'];
      final regions = classifyArtifacts(words);
      expect(regions.first.type, ArtifactType.caption);
    });

    test('detects isolated page number', () {
      final words = ['end', 'of', 'chapter.', '42', 'The', 'next', 'chapter'];
      final regions = classifyArtifacts(words);
      final pageMarkers = regions.where(
        (r) => r.type == ArtifactType.pageMarker,
      );
      expect(pageMarkers, isNotEmpty);
      expect(pageMarkers.first.confidence, lessThan(0.6));
    });

    test('does not flag numbers within prose as page markers', () {
      final words = ['there', 'were', '42', 'people', 'in', 'the', 'room'];
      final regions = classifyArtifacts(words);
      final pageMarkers = regions.where(
        (r) => r.type == ArtifactType.pageMarker,
      );
      expect(pageMarkers, isEmpty);
    });

    test('detects bracketed references [N]', () {
      final words = ['as', 'shown', 'by', '[1]', 'and', '[2]', 'the'];
      final regions = classifyArtifacts(words);
      final refs = regions.where((r) => r.type == ArtifactType.reference);
      expect(refs, isNotEmpty);
    });

    test('merges adjacent table regions', () {
      final words = List.generate(20, (i) => i.isEven ? '|' : '$i');
      final regions = classifyArtifacts(words);
      expect(regions.length, lessThanOrEqualTo(2));
    });

    test('returns correct start/end indices for captions', () {
      final words = [
        'Hello',
        'world.',
        'Figure',
        '1:',
        'Caption',
        'text.',
        'More',
        'prose.',
      ];
      final regions = classifyArtifacts(words);
      final caption = regions.firstWhere((r) => r.type == ArtifactType.caption);
      expect(caption.startIndex, 2); // "Figure"
      expect(caption.endIndex, greaterThanOrEqualTo(3)); // at least "1:"
    });

    test('does not false-positive on conversational prose', () {
      final words =
          'I went to the store and bought some bread and milk for the family dinner tonight we had a great time'
              .split(' ');
      expect(classifyArtifacts(words), isEmpty);
    });
  });

  group('ArtifactRegion', () {
    test('length is calculated correctly', () {
      const region = ArtifactRegion(
        startIndex: 5,
        endIndex: 10,
        type: ArtifactType.table,
        confidence: 0.8,
      );
      expect(region.length, 6);
    });

    test('single-word region has length 1', () {
      const region = ArtifactRegion(
        startIndex: 3,
        endIndex: 3,
        type: ArtifactType.pageMarker,
        confidence: 0.5,
      );
      expect(region.length, 1);
    });
  });
}
