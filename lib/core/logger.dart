import 'dart:developer' as dev;
import 'dart:io';

/// Simple file + DevTools logger for Windows desktop debugging.
///
/// On Windows, debugPrint() goes to a GUI process with no console attached,
/// so nothing appears in `flutter run` terminal output.
///
/// Usage: appLog('MyTag', 'message here');
///
/// Read while the app runs (PowerShell):
///   gc $env:TEMP\speedy_boy_debug.log -Wait
/// Or after the run:
///   type %TEMP%\speedy_boy_debug.log
class AppLogger {
  AppLogger._();

  static IOSink? _sink;
  static String? _path;

  static void init() {
    if (_sink != null) return;
    final path = '${Platform.environment['TEMP'] ?? '.'}/speedy_boy_debug.log';
    _path = path;
    _sink = File(path).openWrite(); // overwrites on every launch
    log('AppLogger', 'log file: $path');
  }

  static void log(String tag, String msg) {
    final line = '[${DateTime.now().toIso8601String()}] [$tag] $msg\n';
    _sink?.write(line);
    dev.log(msg, name: tag);
  }

  static String? get logPath => _path;
}

/// Convenience top-level function — same as AppLogger.log().
void appLog(String tag, String msg) => AppLogger.log(tag, msg);
