import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:runthru/app.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/services/drive_local_store.dart';

void main() {
  // Must init before runZonedGuarded so errors are captured too.
  AppLogger.init();
  appLog('main', 'app starting');

  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      // pdfrx requires a cache directory to be configured before opening PDFs.
      Pdfrx.getCacheDirectory = () async {
        final dir = await getApplicationCacheDirectory();
        return dir.path;
      };

      // Reclaim Drive download temp files orphaned by interrupted imports
      // (older than 24h). Fire-and-forget — never blocks startup.
      unawaited(
        getTemporaryDirectory().then(DriveLocalStore.sweepTempFiles).catchError(
          (Object e) {
            appLog('main', 'drive temp sweep failed: $e');
            return 0;
          },
        ),
      );

      // Global error boundary: replace Flutter's red error screen with a
      // calm, token-styled panel. The error itself is already captured by
      // FlutterError.onError below; this only controls what the user sees.
      ErrorWidget.builder = (FlutterErrorDetails details) =>
          const CalmErrorPanel();

      FlutterError.onError = (FlutterErrorDetails details) {
        appLog('FlutterError', details.exceptionAsString());
        FlutterError.presentError(details);
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        appLog('PlatformDispatcher', '$error\n$stack');
        return true;
      };

      runApp(const ProviderScope(child: RunThruApp()));
    },
    (Object error, StackTrace stackTrace) {
      appLog('UncaughtZoneError', '$error\n$stackTrace');
    },
  );
}

/// Calm fallback shown in place of a crashed widget subtree.
///
/// Deliberately free of Material/Scaffold dependencies so it renders safely
/// at any point in the tree, and free of animation so it is reduced-motion
/// safe by construction.
class CalmErrorPanel extends StatelessWidget {
  const CalmErrorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: RunThruTokens.shellBase,
      child: Center(
        child: Semantics(
          liveRegion: true,
          container: true,
          label: 'Something went wrong. Go back and try again.',
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.self_improvement,
                  size: 40,
                  color: RunThruTokens.shellTextSecondary,
                ),
                SizedBox(height: 12),
                Text(
                  'Something went wrong.\nGo back and try again.',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: RunThruTypography.body,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
