import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/features/content/models/google_drive_file.dart';
import 'package:runthru/features/content/services/google_drive_client.dart';
import 'package:runthru/store/models.dart';

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

        final files = await client.listDriveFiles();

        expect(files.map((file) => file.id), ['doc1', 'pdf1']);
        expect(files.first.sourceId, 'drive://doc1');
      },
    );

    test('selected-files mode rejects Drive-wide listing', () async {
      final client = GoogleDriveClient(
        accessMode: GoogleDriveAccessMode.selectedFilesOnly,
        httpClient: MockClient((request) async {
          fail('selected-files mode must not call Drive files.list');
        }),
        headersProvider: () async => {'Authorization': 'Bearer test'},
      );

      await expectLater(
        client.listDriveFiles(),
        throwsA(
          isA<GoogleDriveException>()
              .having(
                (error) => error.kind,
                'kind',
                GoogleDriveFailureKind.permission,
              )
              .having(
                (error) => error.classification,
                'classification',
                GoogleDriveFailureClassification.accessDenied,
              ),
        ),
      );
    });

    test('search query is sent as a Drive name filter', () async {
      final client = clientFor(
        MockClient((request) async {
          expect(request.url.queryParameters['q'], contains("name contains"));
          expect(request.url.queryParameters['q'], contains(r"Bob\'s"));
          return http.Response(jsonEncode({'files': <Object?>[]}), 200);
        }),
      );

      final files = await client.listDriveFiles(query: "Bob's");

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

      final files = await client.listDriveFiles();

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

      final bytes = await client.downloadSelectedFile(
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
        client.listDriveFiles(),
        throwsA(
          isA<GoogleDriveException>().having(
            (error) => error.kind,
            'kind',
            GoogleDriveFailureKind.rateLimit,
          ),
        ),
      );
    });

    test(
      '401 followed by refreshed headers succeeds after one retry',
      () async {
        final seenAuthHeaders = <String?>[];
        var headerCalls = 0;
        final client = GoogleDriveClient(
          httpClient: MockClient((request) async {
            seenAuthHeaders.add(request.headers['Authorization']);
            if (request.headers['Authorization'] == 'Bearer expired-token') {
              return http.Response(
                jsonEncode({
                  'error': {
                    'code': 401,
                    'status': 'UNAUTHENTICATED',
                    'errors': [
                      {'domain': 'global', 'reason': 'authError'},
                    ],
                  },
                }),
                401,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({
                'files': [
                  {'id': 'doc1', 'name': 'Doc', 'mimeType': googleDocsMimeType},
                ],
              }),
              200,
            );
          }),
          headersProvider: () async {
            headerCalls++;
            return {
              'Authorization': headerCalls == 1
                  ? 'Bearer expired-token'
                  : 'Bearer fresh-token',
            };
          },
        );

        final files = await client.listDriveFiles();

        expect(files.single.id, 'doc1');
        expect(seenAuthHeaders, ['Bearer expired-token', 'Bearer fresh-token']);
        expect(headerCalls, 2);
      },
    );

    test(
      '401 followed by another 401 throws expired-token exception',
      () async {
        final seenAuthHeaders = <String?>[];
        var headerCalls = 0;
        final client = GoogleDriveClient(
          httpClient: MockClient((request) async {
            seenAuthHeaders.add(request.headers['Authorization']);
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 401,
                  'status': 'UNAUTHENTICATED',
                  'message': 'Invalid Credentials',
                  'errors': [
                    {'domain': 'global', 'reason': 'authError'},
                  ],
                },
              }),
              401,
              headers: {'content-type': 'application/json'},
            );
          }),
          headersProvider: () async {
            headerCalls++;
            return {
              'Authorization': headerCalls == 1
                  ? 'Bearer expired-token'
                  : 'Bearer fresh-token',
            };
          },
        );

        await expectLater(
          client.listDriveFiles(),
          throwsA(
            isA<GoogleDriveException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  GoogleDriveFailureKind.expiredToken,
                )
                .having((error) => error.statusCode, 'statusCode', 401),
          ),
        );

        expect(seenAuthHeaders, ['Bearer expired-token', 'Bearer fresh-token']);
        expect(headerCalls, 2);
      },
    );

    test('logs likely expired token 401 using safe metadata', () async {
      AppLogger.clear();
      final seenAuthHeaders = <String?>[];
      final client = GoogleDriveClient(
        httpClient: MockClient((request) async {
          seenAuthHeaders.add(request.headers['Authorization']);
          return http.Response(
            jsonEncode({
              'error': {
                'code': 401,
                'status': 'UNAUTHENTICATED',
                'message': 'Invalid Credentials',
                'errors': [
                  {'domain': 'global', 'reason': 'authError'},
                ],
              },
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
        headersProvider: () async => {'Authorization': 'Bearer expired-token'},
      );

      await expectLater(
        client.listDriveFiles(),
        throwsA(isA<GoogleDriveException>()),
      );

      expect(seenAuthHeaders, ['Bearer expired-token', 'Bearer expired-token']);
      final logs = AppLogger.entries.join('\n');
      expect(logs, contains('classification=expiredOrInvalidAccessToken'));
      expect(logs, contains('retryAttempted=true'));
      expect(logs, contains('retryAttempted=false'));
      AppLogger.clear();
    });

    test('unknown 401 does not retry', () async {
      var requestCount = 0;
      final client = GoogleDriveClient(
        httpClient: MockClient((request) async {
          requestCount++;
          return http.Response('not json', 401);
        }),
        headersProvider: () async => {'Authorization': 'Bearer expired-token'},
      );

      await expectLater(
        client.listDriveFiles(),
        throwsA(
          isA<GoogleDriveException>()
              .having(
                (error) => error.kind,
                'kind',
                GoogleDriveFailureKind.auth,
              )
              .having(
                (error) => error.classification,
                'classification',
                GoogleDriveFailureClassification.transient,
              )
              .having((error) => error.isRetryable, 'isRetryable', isTrue),
        ),
      );

      expect(requestCount, 1);
    });

    test('401 insufficient scope does not retry', () async {
      var requestCount = 0;
      final client = GoogleDriveClient(
        httpClient: MockClient((request) async {
          requestCount++;
          return http.Response(
            jsonEncode({
              'error': {
                'code': 401,
                'status': 'ACCESS_TOKEN_SCOPE_INSUFFICIENT',
                'message': 'Insufficient Permission',
                'errors': [
                  {'domain': 'global', 'reason': 'insufficientPermissions'},
                ],
              },
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
        headersProvider: () async => {'Authorization': 'Bearer test'},
      );

      await expectLater(
        client.listDriveFiles(),
        throwsA(
          isA<GoogleDriveException>()
              .having(
                (error) => error.kind,
                'kind',
                GoogleDriveFailureKind.permission,
              )
              .having(
                (error) => error.classification,
                'classification',
                GoogleDriveFailureClassification.insufficientScope,
              ),
        ),
      );

      expect(requestCount, 1);
    });

    test('403 insufficient scope body/header yields scope exception', () async {
      var requestCount = 0;
      final client = GoogleDriveClient(
        httpClient: MockClient((request) async {
          requestCount++;
          return http.Response(
            jsonEncode({
              'error': {
                'code': 403,
                'status': 'PERMISSION_DENIED',
                'errors': [
                  {'domain': 'global', 'reason': 'forbidden'},
                ],
              },
            }),
            403,
            headers: {
              'content-type': 'application/json',
              'www-authenticate': 'Bearer error="insufficient_scope"',
            },
          );
        }),
        headersProvider: () async => {'Authorization': 'Bearer test'},
      );

      await expectLater(
        client.listDriveFiles(),
        throwsA(
          isA<GoogleDriveException>()
              .having(
                (error) => error.kind,
                'kind',
                GoogleDriveFailureKind.permission,
              )
              .having(
                (error) => error.classification,
                'classification',
                GoogleDriveFailureClassification.insufficientScope,
              ),
        ),
      );

      expect(requestCount, 1);
    });

    test(
      'revoked grant is permanent auth failure, not expired token',
      () async {
        var requestCount = 0;
        final client = GoogleDriveClient(
          httpClient: MockClient((request) async {
            requestCount++;
            return http.Response(
              jsonEncode({
                'error': 'invalid_grant',
                'error_description': 'Token has been expired or revoked.',
              }),
              401,
              headers: {'content-type': 'application/json'},
            );
          }),
          headersProvider: () async => {'Authorization': 'Bearer test'},
        );

        await expectLater(
          client.listDriveFiles(),
          throwsA(
            isA<GoogleDriveException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  GoogleDriveFailureKind.auth,
                )
                .having(
                  (error) => error.classification,
                  'classification',
                  GoogleDriveFailureClassification.permanent,
                )
                .having(
                  (error) => error.shouldClearStoredCredentials,
                  'shouldClearStoredCredentials',
                  isTrue,
                ),
          ),
        );

        expect(requestCount, 1);
      },
    );

    test('malformed 401 JSON falls back safely without retry', () async {
      var requestCount = 0;
      final client = GoogleDriveClient(
        httpClient: MockClient((request) async {
          requestCount++;
          return http.Response(
            '{"error":',
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
        headersProvider: () async => {'Authorization': 'Bearer expired-token'},
      );

      await expectLater(
        client.listDriveFiles(),
        throwsA(isA<GoogleDriveException>()),
      );

      expect(requestCount, 1);
    });

    test('oversized 401 JSON body falls back safely without retry', () async {
      var requestCount = 0;
      final client = GoogleDriveClient(
        httpClient: MockClient((request) async {
          requestCount++;
          final oversized = List.filled(20 * 1024, 'x').join();
          return http.Response(
            '{"error":"$oversized"}',
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
        headersProvider: () async => {'Authorization': 'Bearer expired-token'},
      );

      await expectLater(
        client.listDriveFiles(),
        throwsA(isA<GoogleDriveException>()),
      );

      expect(requestCount, 1);
    });

    test(
      '401 decision logs do not include body or authorization values',
      () async {
        AppLogger.clear();
        final client = GoogleDriveClient(
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 401,
                  'status': 'ACCESS_TOKEN_SCOPE_INSUFFICIENT',
                  'message': 'secret-response-body-value',
                  'errors': [
                    {'domain': 'global', 'reason': 'insufficientPermissions'},
                  ],
                },
              }),
              401,
              headers: {'content-type': 'application/json'},
            );
          }),
          headersProvider: () async {
            return {'Authorization': 'Bearer secret-access-token'};
          },
        );

        await expectLater(
          client.listDriveFiles(),
          throwsA(isA<GoogleDriveException>()),
        );

        final logs = AppLogger.entries.join('\n');
        expect(logs, contains('operation=drive_authorized_send'));
        expect(logs, contains('retryAttempted=false'));
        expect(logs, isNot(contains('secret-response-body-value')));
        expect(logs, isNot(contains('secret-access-token')));
        expect(logs, isNot(contains('Authorization')));
        AppLogger.clear();
      },
    );

    test('does not include response bodies in thrown Drive errors', () async {
      final client = clientFor(
        MockClient(
          (request) async => http.Response('secret-access-token', 403),
        ),
      );

      Object? thrown;
      try {
        await client.listDriveFiles();
      } on Object catch (error) {
        thrown = error;
      }

      expect(thrown, isA<GoogleDriveException>());
      expect(thrown.toString(), isNot(contains('secret-access-token')));
    });
  });
}
