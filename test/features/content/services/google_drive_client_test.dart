import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';

void main() {
  GoogleDriveClient clientFor(http.Client httpClient) {
    return GoogleDriveClient(
      httpClient: httpClient,
      headersProvider: () async => {'Authorization': 'Bearer test'},
    );
  }

  group('GoogleDriveClient', () {
    test(
      'parses supported Drive files and filters unsupported MIME types',
      () async {
        final client = clientFor(
          MockClient((request) async {
            expect(request.url.path, '/drive/v3/files');
            return http.Response(
              jsonEncode({
                'files': [
                  {
                    'id': 'doc1',
                    'name': 'Notes',
                    'mimeType': googleDocsMimeType,
                    'modifiedTime': '2026-05-22T10:00:00Z',
                  },
                  {
                    'id': 'pdf1',
                    'name': 'Paper.pdf',
                    'mimeType': pdfMimeType,
                    'size': '12',
                  },
                  {
                    'id': 'sheet1',
                    'name': 'Budget',
                    'mimeType': 'application/vnd.google-apps.spreadsheet',
                  },
                ],
              }),
              200,
            );
          }),
        );

        final files = await client.listSupportedFiles();

        expect(files.map((file) => file.id), ['doc1', 'pdf1']);
        expect(files.first.sourceId, 'drive://doc1');
      },
    );

    test('search query is sent as a Drive name filter', () async {
      final client = clientFor(
        MockClient((request) async {
          expect(request.url.queryParameters['q'], contains("name contains"));
          expect(request.url.queryParameters['q'], contains(r"Bob\'s"));
          return http.Response(jsonEncode({'files': <Object?>[]}), 200);
        }),
      );

      final files = await client.listSupportedFiles(query: "Bob's");

      expect(files, isEmpty);
    });

    test('follows Drive pagination', () async {
      final client = clientFor(
        MockClient((request) async {
          if (request.url.queryParameters['pageToken'] == 'next') {
            return http.Response(
              jsonEncode({
                'files': [
                  {'id': 'pdf2', 'name': 'Two.pdf', 'mimeType': pdfMimeType},
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'nextPageToken': 'next',
              'files': [
                {'id': 'pdf1', 'name': 'One.pdf', 'mimeType': pdfMimeType},
              ],
            }),
            200,
          );
        }),
      );

      final files = await client.listSupportedFiles();

      expect(files.map((file) => file.id), ['pdf1', 'pdf2']);
    });

    test('exports Google Docs as text', () async {
      final client = clientFor(
        MockClient((request) async {
          expect(request.url.path, '/drive/v3/files/doc1/export');
          expect(request.url.queryParameters['mimeType'], plainTextMimeType);
          return http.Response('Hello from Drive.', 200);
        }),
      );

      final text = await client.exportGoogleDoc(
        const GoogleDriveFile(
          id: 'doc1',
          name: 'Doc',
          mimeType: googleDocsMimeType,
        ),
      );

      expect(text, 'Hello from Drive.');
    });

    test('downloads blob files with alt media', () async {
      final client = clientFor(
        MockClient((request) async {
          expect(request.url.path, '/drive/v3/files/pdf1');
          expect(request.url.queryParameters['alt'], 'media');
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );

      final bytes = await client.downloadBinary(
        const GoogleDriveFile(
          id: 'pdf1',
          name: 'Paper.pdf',
          mimeType: pdfMimeType,
        ),
      );

      expect(bytes, [1, 2, 3]);
    });

    test('maps rate limit responses to typed errors', () async {
      final client = clientFor(
        MockClient((request) async => http.Response('rate limited', 429)),
      );

      await expectLater(
        client.listSupportedFiles(),
        throwsA(
          isA<GoogleDriveException>().having(
            (error) => error.kind,
            'kind',
            GoogleDriveFailureKind.rateLimit,
          ),
        ),
      );
    });
  });
}
