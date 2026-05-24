import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/core/clipboard_document.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/navigation/cube_transition.dart';
import 'package:runthru/navigation/wall_fold_transition.dart';
import 'package:runthru/screens/home_shell.dart';
import 'package:runthru/screens/parallax_reading_screen.dart';
import 'package:runthru/screens/range_picker_screen.dart';
import 'package:runthru/screens/reading_screen.dart';
import 'package:runthru/screens/settings_sources_screen.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/purchase_service.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) {
        final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
        return libraryTransitionPage(
          key: state.pageKey,
          child: HomeShell(initialTab: tab),
        );
      },
    ),
    GoRoute(
      path: '/read',
      pageBuilder: (context, state) {
        final filePath = state.uri.queryParameters['path'] ?? '';
        return wallFoldTransitionPage(
          key: state.pageKey,
          child: _PremiumReadGuard(filePath: filePath),
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
          child: ReadingScreen(filePath: filePath),
        );
      },
    ),
    GoRoute(
      path: '/range-picker',
      pageBuilder: (context, state) {
        final filePath = state.uri.queryParameters['path'] ?? '';
        return cubeTransitionPage(
          key: state.pageKey,
          child: _PremiumRangePickerGuard(filePath: filePath),
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
    // Rule 28 — clipboard reading route; document passed via extra
    GoRoute(
      path: '/read-clipboard',
      pageBuilder: (context, state) {
        final clipboardDoc = state.extra as ClipboardDocument?;
        return wallFoldTransitionPage(
          key: state.pageKey,
          child: ParallaxReadingScreen(
            filePath: 'clipboard://${clipboardDoc?.title ?? 'clipboard'}',
            clipboardDocument: clipboardDoc,
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
          child: ParallaxReadingScreen(
            filePath: filePath,
            instapaperBookmarkId: bookmarkId,
            instapaperInitialProgress: initialProgress,
            clipboardDocument: ClipboardDocument(
              title: title,
              fullText: '',
              document: document!,
              pastedAt: DateTime.now(),
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
        final title = extra?['title'] as String? ?? 'Google Drive Document';
        final fileId = extra?['fileId'] as String? ?? title;
        return wallFoldTransitionPage(
          key: state.pageKey,
          child: ParallaxReadingScreen(
            filePath: 'drive://$fileId',
            clipboardDocument: ClipboardDocument(
              title: title,
              fullText: '',
              document: document!,
              pastedAt: DateTime.now(),
            ),
          ),
        );
      },
    ),
  ],
);

/// Routes to the appropriate reading screen based on configuration.
///
/// All users now use [ParallaxReadingScreen] which handles every
/// [ParallaxIntensity] mode — including `none` (flat 2D viewport).
/// This ensures ContextReveal gestures are available regardless of
/// premium status.
class _PremiumReadGuard extends ConsumerWidget {
  const _PremiumReadGuard({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ParallaxReadingScreen(filePath: filePath);
  }
}

/// Gates range-picker behind premium. Free users see the upsell screen.
class _PremiumRangePickerGuard extends ConsumerWidget {
  const _PremiumRangePickerGuard({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider).valueOrNull ?? const AppConfig();
    if (config.hasPremium) {
      return RangePickerScreen(filePath: filePath);
    }
    return const _RangePickerUpsellScreen();
  }
}

/// Upsell screen shown when free users navigate to the range picker.
class _RangePickerUpsellScreen extends ConsumerWidget {
  const _RangePickerUpsellScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: RunThruTokens.shellBase,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.auto_stories,
                size: 48,
                color: RunThruTokens.shellTextSecondary,
              ),
              const SizedBox(height: 16),
              const Text('Reading Ranges', style: RunThruTypography.title),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Select exactly which pages to read — perfect for '
                  'assigned chapters or focused review. Available with Premium.',
                  style: RunThruTypography.body.copyWith(
                    color: RunThruTokens.shellTextSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: RunThruTokens.shellAccent,
                  foregroundColor: RunThruTokens.shellBase,
                ),
                onPressed: () =>
                    ref.read(purchaseServiceProvider).purchasePremium(),
                child: Text(
                  'Upgrade',
                  style: RunThruTypography.body.copyWith(
                    color: RunThruTokens.shellBase,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.pop(),
                child: Text(
                  'Back to Library',
                  style: RunThruTypography.body.copyWith(
                    color: RunThruTokens.shellTextSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
