import 'package:flutter_test/flutter_test.dart';
import 'package:runthru/features/content/models/drive_content_identity.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/navigation/app_router.dart';

void main() {
  group('driveSourceIdFromRouteExtra', () {
    test('prefers canonical Drive identity source ID', () {
      const identity = DriveContentIdentity(
        fileId: 'identity-file',
        name: 'Doc',
        mimeType: pdfMimeType,
      );

      expect(
        driveSourceIdFromRouteExtra({
          'fileId': 'route-file',
          'sourceId': 'drive://route-source',
        }, identity),
        'drive://identity-file',
      );
    });

    test('uses fileId when identity is absent', () {
      expect(
        driveSourceIdFromRouteExtra({'fileId': ' route-file '}, null),
        'drive://route-file',
      );
    });

    test(
      'returns null instead of a colliding fallback when identity is missing',
      () {
        expect(driveSourceIdFromRouteExtra(null, null), isNull);
        expect(driveSourceIdFromRouteExtra({}, null), isNull);
        expect(
          driveSourceIdFromRouteExtra({'sourceId': 'drive://'}, null),
          isNull,
        );
      },
    );
  });
}
