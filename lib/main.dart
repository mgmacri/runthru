import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:runthru/app.dart';
import 'package:runthru/core/logger.dart';

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
