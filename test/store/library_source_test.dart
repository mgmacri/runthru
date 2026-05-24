import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/store/library_source.dart';

void main() {
  group('LibrarySource', () {
    test('toJson / fromJson round-trip preserves all fields', () {
      final source = LibrarySource(
        id: 'abc',
        kind: LibrarySourceKind.file,
        locator: '/books/a.pdf',
        displayName: 'a.pdf',
        ownsFiles: true,
        sourceKey: 'android-tree:content://tree/book',
        addedAt: DateTime.utc(2026, 5, 22, 10, 30),
      );

      final restored = LibrarySource.fromJson(source.toJson());

      expect(restored.id, 'abc');
      expect(restored.kind, LibrarySourceKind.file);
      expect(restored.locator, '/books/a.pdf');
      expect(restored.displayName, 'a.pdf');
      expect(restored.ownsFiles, isTrue);
      expect(restored.sourceKey, 'android-tree:content://tree/book');
      expect(restored.addedAt, source.addedAt);
    });

    test('fromJson tolerates missing fields with safe defaults', () {
      final restored = LibrarySource.fromJson(const {'locator': '/x'});
      expect(restored.kind, LibrarySourceKind.folder);
      expect(restored.ownsFiles, isFalse);
      expect(restored.locator, '/x');
    });

    test('equality is by id and locator', () {
      final a = LibrarySource(
        id: '1',
        kind: LibrarySourceKind.folder,
        locator: '/p',
        displayName: 'p',
        addedAt: DateTime(2026),
      );
      final b = a.copyWith(displayName: 'different');
      expect(a, equals(b));
    });
  });
}
