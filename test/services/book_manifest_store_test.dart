import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/book_manifest_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 4 of the scale overhaul (BK-3/BK-7): durable page counts and
/// chunked-extraction progress.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BookManifestStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('runthru_manifest_test');
    store = BookManifestStore();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  File writeBook(String name) {
    return File('${tempDir.path}/$name')..writeAsStringSync('pdf bytes $name');
  }

  group('page-count manifest', () {
    test('records and serves page counts without reopening files', () async {
      final book = writeBook('a.pdf');
      expect(await store.entryFor(book.path), isNull);

      await store.setPageCount(book.path, 612);

      final entry = await store.entryFor(book.path);
      expect(entry!.pageCount, 612);
      expect(entry.lastCompletedPage, 0);
    });

    test('manifest survives across store instances (durable)', () async {
      final book = writeBook('b.pdf');
      await store.setPageCount(book.path, 100);

      final fresh = BookManifestStore();
      final entry = await fresh.entryFor(book.path);
      expect(entry!.pageCount, 100);
    });

    test('a changed file invalidates its manifest entry', () async {
      final book = writeBook('c.pdf');
      await store.setPageCount(book.path, 50);

      book.writeAsStringSync('different bytes — new size and mtime');
      expect(
        await store.entryFor(book.path),
        isNull,
        reason: 'stat key changed → entry no longer applies',
      );
    });
  });

  group('chunked-extraction progress', () {
    test('per-chunk commits persist and resume after a simulated crash', () async {
      final book = writeBook('big.pdf');
      await store.setPageCount(book.path, 600);

      // Chunks commit 25 pages at a time.
      await store.setProgress(book.path, lastCompletedPage: 25, pageCount: 600);
      await store.setProgress(book.path, lastCompletedPage: 50, pageCount: 600);

      // "Crash": a brand-new store instance (fresh process) reads the
      // committed progress — extraction resumes at page 50, not page 3.
      final afterCrash = BookManifestStore();
      final entry = await afterCrash.entryFor(book.path);
      expect(entry!.lastCompletedPage, 50);
      expect(entry.pageCount, 600);
    });

    test('setPageCount with the same count preserves chunk progress', () async {
      final book = writeBook('same.pdf');
      await store.setProgress(book.path, lastCompletedPage: 75, pageCount: 200);

      await store.setPageCount(book.path, 200);

      final entry = await store.entryFor(book.path);
      expect(entry!.lastCompletedPage, 75);
    });

    test('completion commits the final page', () async {
      final book = writeBook('done.pdf');
      await store.setProgress(
        book.path,
        lastCompletedPage: 200,
        pageCount: 200,
      );
      final entry = await store.entryFor(book.path);
      expect(entry!.lastCompletedPage, entry.pageCount);
    });
  });
}
