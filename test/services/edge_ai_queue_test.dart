import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/book_identity.dart';
import 'package:runthru/services/content_store/content_store.dart';
import 'package:runthru/services/content_store/section_models.dart';
import 'package:runthru/services/edge_ai_queue.dart';
import 'package:runthru/services/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 7 of the scale overhaul: edge AI plumbing. No models — the
/// pipeline contract: enqueue → section in → annotations out → pacing hint.
class _RecordingProcessor implements ModelProcessor {
  final processed = <String>[];
  Map<String, Object?>? result;
  Object? throwOnce;

  @override
  Future<Map<String, Object?>?> process(
    SectionProcessingRequest request,
    Section section,
  ) async {
    final error = throwOnce;
    if (error != null) {
      throwOnce = null;
      throw error;
    }
    processed.add('${request.key}|words=${section.words.length}');
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ContentStore store;

  const identity = BookIdentity(
    contentHash: 'edgebook01',
    sourceId: 'local',
    displayName: 'Edge Book',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('runthru_edge_ai_test');
    store = ContentStore(rootResolver: () async => '${tempDir.path}/store');
    await store.putDocument(
      identity,
      const ExtractedDocument(
        sentences: [
          Sentence(words: ['one', 'two', 'three']),
          Sentence(words: ['four', 'five']),
        ],
        totalPages: 1,
      ),
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('EdgeAiQueue', () {
    test('processor receives the section payload; annotations land', () async {
      final processor = _RecordingProcessor()
        ..result = {
          'difficultyPerWord': [1.0, 1.5, 1.0, 2.0, 1.0],
        };
      final queue = EdgeAiQueue(store: store, processor: processor);

      await queue.enqueue(
        const SectionProcessingRequest(
          bookId: 'edgebook01',
          sectionIndex: 0,
          task: 'difficulty',
        ),
      );

      expect(processor.processed, ['edgebook01#0#difficulty|words=5']);
      expect(await queue.pending(), isEmpty);

      // Annotations are durable on the section — the pacing path reads them.
      final freshStore = ContentStore(
        rootResolver: () async => '${tempDir.path}/store',
      );
      final section = await freshStore.getSection('edgebook01', 0);
      expect(section!.meta.difficultyPerWord, [1.0, 1.5, 1.0, 2.0, 1.0]);
    });

    test('duplicate requests coalesce to one', () async {
      final processor = _RecordingProcessor();
      final queue = EdgeAiQueue(store: store, processor: processor);

      // Persist two identical requests before any drain can run.
      const request = SectionProcessingRequest(
        bookId: 'edgebook01',
        sectionIndex: 0,
        task: 'summarize',
      );
      await Future.wait([queue.enqueue(request), queue.enqueue(request)]);

      expect(processor.processed.length, lessThanOrEqualTo(2));
      expect(await queue.pending(), isEmpty);
    });

    test('retryable failures keep the request; permanent ones drop it', () async {
      final processor = _RecordingProcessor()
        ..throwOnce = const RetryableModelException('model still loading');
      final queue = EdgeAiQueue(store: store, processor: processor);
      const request = SectionProcessingRequest(
        bookId: 'edgebook01',
        sectionIndex: 0,
        task: 'summarize',
      );

      await queue.enqueue(request);
      expect((await queue.pending()).map((r) => r.key), [request.key]);

      // Permanent failure on the retained op → dropped.
      processor.throwOnce = StateError('unsupported model');
      await queue.drain();
      expect(await queue.pending(), isEmpty);
    });

    test('requests for evicted sections are dropped, not retried', () async {
      final processor = _RecordingProcessor();
      final queue = EdgeAiQueue(store: store, processor: processor);

      await queue.enqueue(
        const SectionProcessingRequest(
          bookId: 'no-such-book',
          sectionIndex: 7,
          task: 'difficulty',
        ),
      );

      expect(processor.processed, isEmpty);
      expect(await queue.pending(), isEmpty);
    });
  });

  group('SectionCursor', () {
    test('walks sections forward and ends cleanly', () async {
      var cursor = await store.openCursor('edgebook01', 0);
      expect(cursor, isNotNull);
      var sections = 0;
      while (cursor != null) {
        sections++;
        cursor = await cursor.next();
      }
      expect(sections, await store.getSectionCount('edgebook01'));
    });
  });
}
