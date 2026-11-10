/// Formats a reading time the same way everywhere:
/// "< 1 min", "12 min", "2 h", "7 h 40 min".
String formatMinutes(int minutes) {
  if (minutes <= 1) return '< 1 min';
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Formats reading time left the same way everywhere in the reader:
/// "< 1 min left", "12 min left", "2 h left", "7 h 40 min left".
String formatTimeLeft(int minutes) => '${formatMinutes(minutes)} left';
