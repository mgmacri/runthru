import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/models/drive_content_identity.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';

void main() {
  group('DriveContentIdentity', () {
    test('sourceId is always drive://{fileId}', () {
      const identity = DriveContentIdentity(
        fileId: 'abc123',
        name: 'My Doc',
        mimeType: googleDocsMimeType,
      );

      expect(identity.sourceId, 'drive://abc123');
    });

    test('sourceRevisionKey uses ISO-8601 UTC modifiedTime when present', () {
      final time = DateTime.utc(2026, 5, 22, 10, 0, 0);
      final identity = DriveContentIdentity(
        fileId: 'abc123',
        name: 'My Doc',
        mimeType: googleDocsMimeType,
        modifiedTime: time,
      );

      expect(identity.sourceRevisionKey, time.toUtc().toIso8601String());
    });

    test('sourceRevisionKey is null when modifiedTime is null', () {
      const identity = DriveContentIdentity(
        fileId: 'abc123',
        name: 'My Doc',
        mimeType: googleDocsMimeType,
      );

      expect(identity.sourceRevisionKey, isNull);
      expect(identity.sourceId, 'drive://abc123');
    });

    test('sourceRevisionKey changes when modifiedTime changes', () {
      final time1 = DateTime.utc(2026, 5, 1);
      final time2 = DateTime.utc(2026, 5, 22);

      final identity1 = DriveContentIdentity(
        fileId: 'abc123',
        name: 'My Doc',
        mimeType: googleDocsMimeType,
        modifiedTime: time1,
      );
      final identity2 = DriveContentIdentity(
        fileId: 'abc123',
        name: 'My Doc',
        mimeType: googleDocsMimeType,
        modifiedTime: time2,
      );

      expect(identity1.sourceRevisionKey, isNot(identity2.sourceRevisionKey));
    });

    test('fromGoogleDriveFile maps all fields for a Google Doc', () {
      final file = GoogleDriveFile(
        id: 'doc1',
        name: 'My Document',
        mimeType: googleDocsMimeType,
        modifiedTime: DateTime.utc(2026, 5, 22),
      );

      final identity = DriveContentIdentity.fromGoogleDriveFile(file);

      expect(identity.fileId, 'doc1');
      expect(identity.name, 'My Document');
      expect(identity.mimeType, googleDocsMimeType);
      expect(identity.modifiedTime, file.modifiedTime);
      expect(identity.sizeBytes, isNull);
      expect(identity.exportMimeType, plainTextMimeType);
    });

    test('fromGoogleDriveFile maps all fields for a PDF', () {
      const file = GoogleDriveFile(
        id: 'pdf1',
        name: 'Paper.pdf',
        mimeType: pdfMimeType,
        sizeBytes: 204800,
      );

      final identity = DriveContentIdentity.fromGoogleDriveFile(file);

      expect(identity.fileId, 'pdf1');
      expect(identity.name, 'Paper.pdf');
      expect(identity.mimeType, pdfMimeType);
      expect(identity.sizeBytes, 204800);
      expect(identity.exportMimeType, isNull);
    });

    test('sourceId matches GoogleDriveFile.sourceId for the same file', () {
      const file = GoogleDriveFile(
        id: 'xyz789',
        name: 'Report.pdf',
        mimeType: pdfMimeType,
      );

      final identity = DriveContentIdentity.fromGoogleDriveFile(file);

      expect(identity.sourceId, file.sourceId);
    });

    test('equality is based on fileId only', () {
      final identity1 = DriveContentIdentity(
        fileId: 'same',
        name: 'Name A',
        mimeType: pdfMimeType,
        modifiedTime: DateTime.utc(2026, 1, 1),
      );
      final identity2 = DriveContentIdentity(
        fileId: 'same',
        name: 'Name B',
        mimeType: pdfMimeType,
        modifiedTime: DateTime.utc(2026, 6, 1),
      );
      const identity3 = DriveContentIdentity(
        fileId: 'different',
        name: 'Name A',
        mimeType: pdfMimeType,
      );

      expect(identity1, equals(identity2));
      expect(identity1, isNot(equals(identity3)));
      expect(identity1.hashCode, identity2.hashCode);
    });
  });
}
