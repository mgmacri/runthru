import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/core/clipboard_document.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/core/sample_document.dart';
import 'package:runthru/features/content/models/drive_content_identity.dart';
import 'package:runthru/navigation/cube_transition.dart';
import 'package:runthru/navigation/wall_fold_transition.dart';
import 'package:runthru/screens/home_shell.dart';
import 'package:runthru/screens/parallax_reading_screen.dart';
import 'package:runthru/screens/range_picker_screen.dart';
import 'package:runthru/screens/reading_screen.dart';
import 'package:runthru/screens/settings_sources_screen.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/widgets/reading_goal_onboarding_gate.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) {
        final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
        final focusGoogleDriveBrowserSetting =
            state.uri.queryParameters['focus'] == 'googleDriveBrowser';
        final focusRequestId = state.uri.queryParameters['focusRequest'];
        return libraryTransitionPage(
          key: state.pageKey,
          child: ReadingEntryOnboardingGate(
            child: HomeShell(
              initialTab: tab,
              focusGoogleDriveBrowserSetting: focusGoogleDriveBrowserSetting,
              focusRequestId: focusRequestId,
            ),
          ),
        );
      },
    ),
    GoRoute(
      path: '/read',
      pageBuilder: (context, state) {
        final filePath = state.uri.queryParameters['path'] ?? '';
        return wallFoldTransitionPage(
          key: state.pageKey,
          child: ReadingEntryOnboardingGate(
            child: ParallaxReadingScreen(filePath: filePath),
          ),
        );
      },
    ),
    GoRoute(
      path: '/read-legacy',
      pageBuilder: (context, state) {
        final filePath = state.uri.queryParameters['path'] ?? '';
        return cubeTransitionPage(
          key: state.pageKey,
          direction: -1,
          child: ReadingEntryOnboardingGate(
            child: ReadingScreen(filePath: filePath),
          ),
        );
      },
    ),
    GoRoute(
      path: '/range-picker',
      pageBuilder: (context, state) {
        final filePath = state.uri.queryParameters['path'] ?? '';
        return cubeTransitionPage(
          key: state.pageKey,
          child: RangePickerScreen(filePath: filePath),
        );
      },
    ),
    GoRoute(path: '/sources', redirect: (_, __) => '/?tab=1'),
    GoRoute(path: '/analytics', redirect: (_, __) => '/?tab=2'),
    GoRoute(path: '/settings', redirect: (_, __) => '/?tab=3'),
    GoRoute(
      path: '/settings/sources',
      pageBuilder: (context, state) => MaterialPage(
        key: state.pageKey,
        child: const SettingsSourcesScreen(),
      ),
    ),
    GoRoute(
      path: '/read-sample',
      pageBuilder: (context, state) {
        final doc = sampleDocument;
        return wallFoldTransitionPage(
          key: state.pageKey,
          child: ReadingEntryOnboardingGate(
            child: ParallaxReadingScreen(
              filePath: sampleContentId,
              contentSource: 'sample',
              clipboardDocument: doc,
            ),
          ),
        );
      },
    ),
    // Rule 28 — clipboard reading route; document passed via extra
    GoRoute(
      path: '/read-clipboard',
      pageBuilder: (context, state) {
        final clipboardDoc = state.extra as ClipboardDocument?;
        return wallFoldTransitionPage(
          key: state.pageKey,
          child: ReadingEntryOnboardingGate(
            child: ParallaxReadingScreen(
              filePath: 'clipboard://${clipboardDoc?.title ?? 'clipboard'}',
              contentSource: 'clipboard',
              clipboardDocument: clipboardDoc,
            ),
          ),
        );
      },
    ),
    // Instapaper article reading route; document + title via extra map
    GoRoute(
      path: '/read-instapaper',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, Object?>?;
        final document = extra?['document'] as ExtractedDocument?;
        final title = extra?['title'] as String? ?? 'Instapaper Article';
        final bookmarkId = extra?['bookmarkId'] as int?;
        final initialProgress =
            (extra?['initialProgress'] as num?)?.toDouble() ?? 0.0;
        // Use the stable Instapaper bookmarkId (not the title) so the local
        // bookmark key survives title changes from the API and matches across
        // reopens. Falls back to title only if id is missing (defensive).
        final filePath = bookmarkId != null
            ? 'instapaper://$bookmarkId'
            : 'instapaper://$title';
        return wallFoldTransitionPage(
          key: state.pageKey,
          child: ReadingEntryOnboardingGate(
            child: ParallaxReadingScreen(
              filePath: filePath,
              contentSource: 'instapaper',
              instapaperBookmarkId: bookmarkId,
              instapaperInitialProgress: initialProgress,
              clipboardDocument: ClipboardDocument(
                title: title,
                fullText: '',
                document: document!,
                pastedAt: DateTime.now(),
              ),
            ),
          ),
        );
      },
    ),
    // Google Drive reading route; imported document + stable Drive ID via extra.
    GoRoute(
      path: '/read-drive',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, Object?>?;
        final document = extra?['document'] as ExtractedDocument?;
        final identity = extra?['identity'] as DriveContentIdentity?;
        final title =
            identity?.name ??
            extra?['title'] as String? ??
            'Google Drive Document';
        final sourceId = driveSourceIdFromRouteExtra(extra, identity);
        if (sourceId == null) {
          appLog(
            'google-drive-route',
            'operation=drive_source_id classification=missing_identity '
                'storage=preserved',
          );
          throw StateError(
            'Drive reading route requires a Drive identity or fileId.',
          );
        }
        return wallFoldTransitionPage(
          key: state.pageKey,
          child: ReadingEntryOnboardingGate(
            child: ParallaxReadingScreen(
              filePath: sourceId,
              contentSource: 'drive',
              clipboardDocument: ClipboardDocument(
                title: title,
                fullText: '',
                document: document!,
                pastedAt: DateTime.now(),
              ),
            ),
          ),
        );
      },
    ),
  ],
);

/// Returns a stable Drive source ID from route extras, or null if missing.
///
/// A missing Drive identity/fileId must not fall back to a shared persistent
/// value, because that would collide saved reading progress across documents.
String? driveSourceIdFromRouteExtra(
  Map<String, Object?>? extra,
  DriveContentIdentity? identity,
) {
  final identitySourceId = identity?.sourceId;
  if (_isValidDriveSourceId(identitySourceId)) {
    return identitySourceId!.trim();
  }

  final fileId = extra?['fileId'] as String?;
  if (fileId != null && fileId.trim().isNotEmpty) {
    return 'drive://${fileId.trim()}';
  }

  final sourceId = extra?['sourceId'] as String?;
  if (_isValidDriveSourceId(sourceId)) {
    return sourceId!.trim();
  }

  return null;
}

bool _isValidDriveSourceId(String? sourceId) {
  if (sourceId == null) return false;
  final trimmed = sourceId.trim();
  if (!trimmed.startsWith('drive://')) return false;
  return trimmed.substring('drive://'.length).trim().isNotEmpty;
}
