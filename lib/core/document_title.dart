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
