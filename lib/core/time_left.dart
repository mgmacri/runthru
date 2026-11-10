/// Formats reading time left the same way everywhere in the reader:
/// "< 1 min left", "12 min left", "2 h left", "7 h 40 min left".
String formatTimeLeft(int minutes) {
  if (minutes <= 1) return '< 1 min left';
  if (minutes < 60) return '$minutes min left';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h left' : '$h h $m min left';
}
