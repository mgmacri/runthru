import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/services/content_cache_policy.dart';
import 'package:runthru/services/device_capability.dart';
import 'package:runthru/services/pdf_cache.dart';

/// Phase 2 of the scale overhaul (BK-2): one coherent cache budget with
/// LRU eviction, exercised against the real eviction routine.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('runthru_evict_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeFile(String name, int bytes, DateTime lastModified) {
    final file = File('${tempDir.path}/$name');
    file.writeAsBytesSync(List.filled(bytes, 0));
    file.setLastModifiedSync(lastModified);
    return file;
  }

  group('ContentCachePolicy', () {
    test('low-end mobile gets the conservative budget', () {
      final policy = ContentCachePolicy.forDevice(
        const DeviceCapability(
          processorCount: 4,
          maxWorkers: 2,
          isMobile: true,
        ),
      );
      expect(policy.totalBudgetBytes, ContentCachePolicy.lowEndBudgetBytes);
    });

    test('high-end devices get the larger budget', () {
      final policy = ContentCachePolicy.forDevice(
        const DeviceCapability(
          processorCount: 8,
          maxWorkers: 6,
          isMobile: true,
        ),
      );
      expect(policy.totalBudgetBytes, ContentCachePolicy.highEndBudgetBytes);
    });

    test('configureBudget propagates the policy to PdfCache', () {
      PdfCache.configureBudget(1234);
      expect(PdfCache.maxCacheBytes, 1234);
      PdfCache.configureBudget(ContentCachePolicy.lowEndBudgetBytes);
    });
  });

  group('LRU eviction under budget pressure', () {
    test('evicts least-recently-used files first, stops under budget', () {
      final now = DateTime.now();
      writeFile('oldest.json.gz', 400, now.subtract(const Duration(days: 3)));
      writeFile('middle.json.gz', 400, now.subtract(const Duration(days: 2)));
      writeFile('newest.json.gz', 400, now.subtract(const Duration(days: 1)));

      // Budget of 900 bytes: only the oldest file must go (1200 → 800).
      PdfCache.evictSync(tempDir.path, 900);

      expect(File('${tempDir.path}/oldest.json.gz').existsSync(), isFalse);
      expect(File('${tempDir.path}/middle.json.gz').existsSync(), isTrue);
      expect(File('${tempDir.path}/newest.json.gz').existsSync(), isTrue);
    });

    test('no eviction when under budget', () {
      final now = DateTime.now();
      writeFile('a.json.gz', 100, now);
      writeFile('b.json.gz', 100, now);

      PdfCache.evictSync(tempDir.path, 10000);

      expect(tempDir.listSync().whereType<File>().length, 2);
    });
  });
}
