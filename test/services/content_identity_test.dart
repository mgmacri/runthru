import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/content_identity.dart';

/// Phase 2 of the scale overhaul (BK-4/BK-11): content-hash identity.
void main() {
  late Directory tempDir;
  late ContentIdentityService identity;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('runthru_identity_test');
    identity = ContentIdentityService(rootResolver: () async => tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  File write(String name, String content) {
    final file = File('${tempDir.path}/$name');
    file.writeAsStringSync(content);
    return file;
  }

  group('ContentIdentityService', () {
    test('same content under different names → same hash', () async {
      final a = write('book.pdf', 'identical bytes');
      final b = write('copy of book.pdf', 'identical bytes');

      final hashA = await identity.ensureHash(a.path);
      final hashB = await identity.ensureHash(b.path);

      expect(hashA, isNotNull);
      expect(hashA, hashB);
      expect(hashA, hasLength(64), reason: 'full sha256 hex digest');
    });

    test('different content under the same name → different hash', () async {
      final dirA = Directory('${tempDir.path}/a')..createSync();
      final dirB = Directory('${tempDir.path}/b')..createSync();
      final a = File('${dirA.path}/book.pdf')..writeAsStringSync('content A');
      final b = File('${dirB.path}/book.pdf')..writeAsStringSync('content B');

      final hashA = await identity.ensureHash(a.path);
      final hashB = await identity.ensureHash(b.path);

      expect(hashA, isNotNull);
      expect(hashB, isNotNull);
      expect(hashA, isNot(hashB));
    });

    test('hash is memoised — knownHashFor hits without re-reading', () async {
      final a = write('memo.pdf', 'memo bytes');
      expect(await identity.knownHashFor(a.path), isNull);

      final hash = await identity.ensureHash(a.path);
      expect(await identity.knownHashFor(a.path), hash);

      // A fresh service instance reads the persisted index.
      // (Writes are serialized; give the chain a beat to flush.)
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final fresh = ContentIdentityService(
        rootResolver: () async => tempDir.path,
      );
      expect(await fresh.knownHashFor(a.path), hash);
    });

    test('modified file gets a new identity', () async {
      final a = write('changing.pdf', 'version 1');
      final hash1 = await identity.ensureHash(a.path);

      // Ensure the mtime/size changes.
      a.writeAsStringSync('version 2 — longer');
      final hash2 = await identity.ensureHash(a.path);

      expect(hash1, isNot(hash2));
    });

    test('missing file → null, no throw', () async {
      expect(await identity.ensureHash('${tempDir.path}/nope.pdf'), isNull);
      expect(await identity.knownHashFor('${tempDir.path}/nope.pdf'), isNull);
    });

    test('unavailable storage degrades to null results', () async {
      final degraded = ContentIdentityService(rootResolver: () async => null);
      final a = write('deg.pdf', 'bytes');
      // Hash still computes (memoisation is just skipped).
      expect(await degraded.ensureHash(a.path), isNotNull);
    });
  });
}
