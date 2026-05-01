import 'dart:collection';
import 'dart:developer' as dev;
import 'dart:io';

/// Simple file + DevTools logger with an in-memory ring buffer.
///
/// On Windows, writes to %TEMP%\runthru_debug.log.
/// On all platforms, keeps the last [_maxEntries] lines in memory
/// so they can be shown in an in-app log viewer.
///
/// Read while running on desktop (PowerShell):
///   gc $env:TEMP\runthru_debug.log -Wait
class AppLogger {
  AppLogger._();

  static IOSink? _sink;
  static String? _path;

  static const int _maxEntries = 200;
  static final Queue<String> _buffer = Queue<String>();

  static void init() {
    if (_sink != null) return;
    try {
      // On iOS/Android, TEMP is not set and '.' is not writable.
      // Only open file logging on desktop where TEMP exists.
      final temp =
          Platform.environment['TEMP'] ?? Platform.environment['TMPDIR'];
      if (temp == null || temp.isEmpty) {
        // Mobile platform — skip file logging, use in-memory + DevTools only.
        log('AppLogger', 'init — platform=${Platform.operatingSystem}');
        return;
      }
      final path = '$temp/runthru_debug.log';
      _path = path;
      _sink = File(path).openWrite(); // overwrites on every launch
    } on Object {
      // Sandboxed platforms may not have writable TEMP
    }
    log('AppLogger', 'init — platform=${Platform.operatingSystem}');
  }

  static void log(String tag, String msg) {
    final line = '[${DateTime.now().toIso8601String()}] [$tag] $msg';
    _sink?.writeln(line);
    dev.log(msg, name: tag);
    _buffer.addLast(line);
    while (_buffer.length > _maxEntries) {
      _buffer.removeFirst();
    }
  }

  static String? get logPath => _path;

  /// Returns all buffered log lines (most recent last).
  static List<String> get entries => _buffer.toList();

  /// Clears the in-memory buffer.
  static void clear() => _buffer.clear();
}

/// Convenience top-level function — same as AppLogger.log().
void appLog(String tag, String msg) => AppLogger.log(tag, msg);
