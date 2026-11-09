import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/device_capability.dart';
import 'package:runthru/services/folder_scanner.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/preprocessing_queue.dart';
import 'package:runthru/store/config.dart';

/// Phase 1 of the scale overhaul (BK-1): no document text survives in queue
/// state past its reading session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
  });

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        deviceCapabilityProvider.overrideWithValue(
          const DeviceCapability(
            processorCount: 4,
            maxWorkers: 2,
            isMobile: false,
          ),
        ),
        configProvider.overrideWith(
          () => throw UnimplementedError('config not needed'),
        ),
        pdfListProvider.overrideWith((ref) async => const <PdfEntry>[]),
      ],
    );
  }

  ExtractedDocument docWith(String word) => ExtractedDocument(
    sentences: [
      Sentence(words: [word, 'text']),
    ],
    pageBoundaries: const [
      PageBoundary(pageNumber: 0, startSentenceIndex: 0, startWordIndex: 0),
    ],
    totalPages: 1,
  );

  group('releaseDocument', () {
    test('opening book A, closing it, then opening B drops A\'s text', () {
      final container = createContainer();
      addTearDown(container.dispose);
      final queue = container.read(preprocessingQueueProvider.notifier);
      queue.pauseBackground();

      // Session for A materialized its document, then for B.
      queue.debugSetEntry(
        PdfEntry(
          filePath: '/a.pdf',
          fileName: 'a.pdf',
          status: PdfStatus.ready,
          document: docWith('alpha'),
          progress: const PdfProgress(
            lastCompletedPage: 1,
            totalPages: 1,
            phase: ExtractionPhase.done,
          ),
        ),
      );
      queue.debugSetEntry(
        PdfEntry(
          filePath: '/b.pdf',
          fileName: 'b.pdf',
          status: PdfStatus.ready,
          document: docWith('beta'),
        ),
      );

      // Closing A's reading session releases its document.
      queue.releaseDocument('/a.pdf');

      final state = container.read(preprocessingQueueProvider);
      expect(
        state['/a.pdf']!.document,
        isNull,
        reason: 'book A text must not stay in RAM after its session',
      );
      expect(
        state['/b.pdf']!.document,
        isNotNull,
        reason: 'active book B keeps its document',
      );
    });

    test('release preserves status, progress, and retry metadata', () {
      final container = createContainer();
      addTearDown(container.dispose);
      final queue = container.read(preprocessingQueueProvider.notifier);
      queue.pauseBackground();

      queue.debugSetEntry(
        PdfEntry(
          filePath: '/c.pdf',
          fileName: 'c.pdf',
          status: PdfStatus.preview,
          document: docWith('gamma'),
          retryCount: 1,
          progress: const PdfProgress(
            lastCompletedPage: 3,
            totalPages: 90,
            phase: ExtractionPhase.preview,
          ),
        ),
      );

      queue.releaseDocument('/c.pdf');

      final entry = container.read(preprocessingQueueProvider)['/c.pdf']!;
      expect(entry.document, isNull);
      expect(entry.status, PdfStatus.preview);
      expect(entry.retryCount, 1);
      expect(entry.progress.lastCompletedPage, 3);
      expect(entry.progress.totalPages, 90);
    });

    test('release is a no-op for unknown paths and document-free entries', () {
      final container = createContainer();
      addTearDown(container.dispose);
      final queue = container.read(preprocessingQueueProvider.notifier);
      queue.pauseBackground();

      queue.enqueueEntry(const PdfEntry(filePath: '/d.pdf', fileName: 'd.pdf'));

      expect(() => queue.releaseDocument('/missing.pdf'), returnsNormally);
      expect(() => queue.releaseDocument('/d.pdf'), returnsNormally);
      final state = container.read(preprocessingQueueProvider);
      expect(state.containsKey('/missing.pdf'), isFalse);
      expect(state['/d.pdf']!.status, PdfStatus.queued);
    });

    test('retryErrors routes by phase even when document was released', () {
      final container = createContainer();
      addTearDown(container.dispose);
      final queue = container.read(preprocessingQueueProvider.notifier);
      queue.pauseBackground();

      queue.debugSetEntry(
        const PdfEntry(
          filePath: '/e.pdf',
          fileName: 'e.pdf',
          status: PdfStatus.error,
          retryCount: 1,
          progress: PdfProgress(
            lastCompletedPage: 3,
            totalPages: 50,
            phase: ExtractionPhase.backgroundCompletion,
          ),
        ),
      );

      // Must not throw despite document == null (pre-fix it required a doc).
      expect(queue.retryErrors, returnsNormally);
    });
  });
}
