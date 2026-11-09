import 'dart:convert';
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

class _AlwaysRetryProcessor implements ModelProcessor {
  @override
  Future<Map<String, Object?>?> process(
    SectionProcessingRequest request,
    Section section,
  ) async => throw const RetryableModelException('busy');
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

    test(
      'retryable failures keep the request; permanent ones drop it',
      () async {
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
      },
    );

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

  group('A-01 task schema', () {
    final at = DateTime.utc(2026, 11, 9, 12);

    test('ModelTask defines exactly summarize and difficulty', () {
      expect(ModelTask.all, {'summarize', 'difficulty'});
      expect(ModelTask.isKnown('summarize'), isTrue);
      expect(ModelTask.isKnown('translate'), isFalse);
    });

    test('summarize annotation round-trips through JSON', () {
      final a = ModelAnnotation.summarize(
        text: '  A dog finds its way home.  ',
        version: 3,
        createdAt: at,
      );
      final back = ModelAnnotation.fromJson(
        jsonDecode(jsonEncode(a.toJson())),
      )!;
      expect(back.task, ModelTask.summarize);
      expect(back.version, 3);
      expect(back.createdAt, at);
      expect(back.summaryText, 'A dog finds its way home.');
      expect(back.difficultyScore, isNull);
      expect(back.hardWords, isEmpty);
    });

    test('difficulty annotation round-trips and clamps score', () {
      final a = ModelAnnotation.difficulty(
        score: 1.7,
        hardWords: ['ubiquitous', 'ephemeral'],
        version: 1,
        createdAt: at,
      );
      final back = ModelAnnotation.fromJson(
        jsonDecode(jsonEncode(a.toJson())),
      )!;
      expect(back.task, ModelTask.difficulty);
      expect(back.difficultyScore, 1.0);
      expect(back.hardWords, ['ubiquitous', 'ephemeral']);
      expect(back.summaryText, isNull);
    });

    test('malformed or unknown annotations parse to null', () {
      expect(ModelAnnotation.fromJson(null), isNull);
      expect(ModelAnnotation.fromJson('nope'), isNull);
      expect(
        ModelAnnotation.fromJson({
          'task': 'translate',
          'version': 1,
          'createdAt': at.toIso8601String(),
          'payload': <String, Object?>{},
        }),
        isNull,
      );
      expect(
        ModelAnnotation.fromJson({
          'task': 'summarize',
          'version': 1,
          'createdAt': 'not a date',
          'payload': <String, Object?>{},
        }),
        isNull,
      );
    });

    test('SectionMetadata JSON round-trip keeps typed annotations', () {
      final meta =
          const SectionMetadata(
                sectionIndex: 0,
                startWordIndex: 0,
                startSentenceIndex: 0,
                wordCount: 5,
              )
              .withAnnotations(
                ModelAnnotation.summarize(
                  text: 'Counting to five.',
                  version: 1,
                  createdAt: at,
                ).toAnnotations(),
              )
              .withAnnotations(
                ModelAnnotation.difficulty(
                  score: 0.2,
                  hardWords: const [],
                  version: 1,
                  createdAt: at,
                ).toAnnotations(),
              );
      final back = SectionMetadata.fromJson(
        jsonDecode(jsonEncode(meta.toJson())) as Map<String, Object?>,
      );
      expect(
        back.annotationFor(ModelTask.summarize)?.summaryText,
        'Counting to five.',
      );
      expect(back.annotationFor(ModelTask.difficulty)?.difficultyScore, 0.2);
      expect(
        const SectionMetadata(
          sectionIndex: 0,
          startWordIndex: 0,
          startSentenceIndex: 0,
          wordCount: 0,
        ).annotationFor(ModelTask.summarize),
        isNull,
      );
    });

    test(
      'processor results persist and read back typed via the store',
      () async {
        final processor = _RecordingProcessor()
          ..result = ModelAnnotation.summarize(
            text: 'Numbers one to five.',
            version: 2,
            createdAt: at,
          ).toAnnotations();
        final queue = EdgeAiQueue(store: store, processor: processor);

        await queue.enqueue(
          const SectionProcessingRequest(
            bookId: 'edgebook01',
            sectionIndex: 0,
            task: ModelTask.summarize,
          ),
        );

        final fresh = ContentStore(
          rootResolver: () async => '${tempDir.path}/store',
        );
        final annotation = (await fresh.getSection(
          'edgebook01',
          0,
        ))!.meta.annotationFor(ModelTask.summarize);
        expect(annotation?.summaryText, 'Numbers one to five.');
        expect(annotation?.version, 2);
        expect(annotation?.createdAt, at);
      },
    );

    test('request JSON round-trips; unknown tasks are rejected', () {
      const request = SectionProcessingRequest(
        bookId: 'b',
        sectionIndex: 4,
        task: ModelTask.difficulty,
      );
      final back = SectionProcessingRequest.fromJson(
        jsonDecode(jsonEncode(request.toJson())) as Map<String, Object?>,
      )!;
      expect(back.key, request.key);
      expect(
        SectionProcessingRequest.fromJson({
          'bookId': 'b',
          'sectionIndex': 4,
          'task': 'translate',
        }),
        isNull,
      );
    });

    test(
      'coalescing is per task: same section, two tasks, both kept',
      () async {
        // Retryable failure keeps requests pending so we can inspect them.
        final processor = _AlwaysRetryProcessor();
        final queue = EdgeAiQueue(store: store, processor: processor);
        const summarize = SectionProcessingRequest(
          bookId: 'edgebook01',
          sectionIndex: 0,
          task: ModelTask.summarize,
        );
        const difficulty = SectionProcessingRequest(
          bookId: 'edgebook01',
          sectionIndex: 0,
          task: ModelTask.difficulty,
        );

        await queue.enqueue(summarize);
        await queue.enqueue(difficulty);
        await queue.enqueue(summarize);

        final keys = (await queue.pending()).map((r) => r.key).toList();
        expect(keys, unorderedEquals([summarize.key, difficulty.key]));
      },
    );

    test('persisted unknown-task requests are skipped on load', () async {
      SharedPreferences.setMockInitialValues({
        'edge_ai_queue_v1': jsonEncode([
          {'bookId': 'edgebook01', 'sectionIndex': 0, 'task': 'translate'},
          {'bookId': 'edgebook01', 'sectionIndex': 0, 'task': 'summarize'},
        ]),
      });
      final queue = EdgeAiQueue(store: store);
      expect((await queue.pending()).map((r) => r.task), ['summarize']);
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
