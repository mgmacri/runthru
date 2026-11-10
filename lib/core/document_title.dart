/// A readable title from a file name: no extension, no " (1)" copy suffix,
/// underscores as spaces. "my_notes (1).pdf" → "my notes".
String prettyFileTitle(String fileName) {
  var name = fileName.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  name = name
      .replaceAll(RegExp(r'\s*\(\d+\)$'), '')
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return name.isEmpty ? fileName : name;
}

/// A title for pasted or shared text: its first line when that line is
/// short enough to be a heading, otherwise its first few words with an
/// ellipsis. Null for empty text or a bare link.
String? titleFromText(String text) {
  final firstLine = text
      .split('\n')
      // A Markdown heading is read as a heading: its "#" marks are not part
      // of the title ("# Morning Notes" used to be titled "# Morning Notes").
      .map((l) => l.trim().replaceFirst(_markdownHeadingMarks, '').trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (firstLine.isEmpty || RegExp(r'^https?://').hasMatch(firstLine)) {
    return null;
  }
  final words = firstLine.split(RegExp(r'\s+'));
  if (firstLine.length <= 60 && words.length <= 10) return firstLine;
  return '${words.take(6).join(' ')}…';
}

/// Leading "#" marks of a Markdown heading line (and the space after them).
final RegExp _markdownHeadingMarks = RegExp(r'^#{1,6}(\s+|$)');
