import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedy_boy/app.dart';
import 'package:speedy_boy/core/logger.dart';

void main() {
  // Must init before runZonedGuarded so errors are captured too.
  AppLogger.init();
  appLog('main', 'app starting');

  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        appLog('FlutterError', details.exceptionAsString());
        FlutterError.presentError(details);
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        appLog('PlatformDispatcher', '$error\n$stack');
        return true;
      };

      runApp(
        const ProviderScope(
          child: SpeedyBoyApp(),
        ),
      );
    },
    (Object error, StackTrace stackTrace) {
      appLog('UncaughtZoneError', '$error\n$stackTrace');
    },
  );
}
