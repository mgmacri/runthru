import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Cross-platform notification service for PDF processing progress.
///
/// - **Android**: Uses platform channel to show a foreground service
///   notification with progress bar.
/// - **iOS**: Uses platform channel to show UNUserNotification with progress.
/// - **Desktop** (Windows/macOS/Linux): Uses platform channel for system
///   notification (toast with progress on Windows, NSUserNotification on macOS).
/// - **Web**: No-op — not supported.
///
/// All methods are static and safe to call on any platform; unsupported
/// platforms are handled gracefully.
class NotificationService {
  NotificationService._();

  static const _channel = MethodChannel('com.runthru/notifications');
  static const String _tag = 'notification_service';

  /// Show or update a persistent progress notification.
  ///
  /// [title] — e.g. "Processing 3 of 10 PDFs".
  /// [progress] — 0.0 to 1.0.
  static Future<void> showProgress({
    required String title,
    required double progress,
  }) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('showProgress', {
        'title': title,
        'progress': (progress * 100).round().clamp(0, 100),
      });
    } on MissingPluginException {
      // Platform channel not implemented — log once and move on.
      dev.log('showProgress: platform channel not available', name: _tag);
    } on PlatformException catch (e) {
      dev.log('showProgress failed: $e', name: _tag);
    }
  }

  /// Dismiss the progress notification.
  static Future<void> dismiss() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('dismiss');
    } on MissingPluginException {
      // Not implemented on this platform — silently ignore.
    } on PlatformException catch (e) {
      dev.log('dismiss failed: $e', name: _tag);
    }
  }

  /// Request notification permissions (iOS / Android 13+).
  static Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    try {
      final result =
          await _channel.invokeMethod<bool>('requestPermission') ?? false;
      return result;
    } on MissingPluginException {
      return _isDesktop;
    } on PlatformException catch (e) {
      dev.log('requestPermission failed: $e', name: _tag);
      return false;
    }
  }

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
}
