/// Turning the bytes of a fetched web page into text, within limits.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The largest page a shared link may bring in. Articles are a few hundred
/// kilobytes; this leaves room for heavy pages and stops a link to a huge
/// file, or to a stream that never ends, from filling memory.
const int kMaxWebPageBytes = 8 * 1024 * 1024;

/// A page body went past the size allowed.
class WebPageTooLarge implements Exception {
  /// Creates the exception.
  const WebPageTooLarge();
}

/// Collects [body], giving up with [WebPageTooLarge] as soon as it has
/// grown past [maxBytes]: the rest is not read.
Future<Uint8List> readWebPage(
  Stream<List<int>> body, {
  int maxBytes = kMaxWebPageBytes,
}) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in body) {
    bytes.add(chunk);
    if (bytes.length > maxBytes) throw const WebPageTooLarge();
  }
  return bytes.takeBytes();
}

/// The text of a web page, or null when it is in an encoding this app
/// cannot read (Shift_JIS, GBK and the like: there is no decoder for them
/// here, and showing their bytes as something else would be gibberish).
///
/// [charset] is what the response's `Content-Type` header named, if it
/// named one. Without it the page's own `<meta charset>` counts. Without
/// either the page is UTF-8 if its bytes are, and Windows-1252 otherwise,
/// which is what the web has always meant by an old page that does not say.
String? decodeWebPage(List<int> bytes, {String? charset}) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
          (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
    return null; // UTF-16
  }
  final hasBom =
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  final content = hasBom ? bytes.sublist(3) : bytes;
  if (hasBom) return utf8.decode(content, allowMalformed: true);

  switch (_family(charset) ?? _family(_metaCharset(content))) {
    case _Family.utf8:
      return utf8.decode(content, allowMalformed: true);
    case _Family.windows1252:
      return _decodeWindows1252(content);
    case _Family.other:
      return null;
    case null:
      try {
        return utf8.decode(content);
      } on FormatException {
        return _decodeWindows1252(content);
      }
  }
}

enum _Family { utf8, windows1252, other }

/// Which decoder a charset label calls for; null when there is no label.
_Family? _family(String? label) {
  if (label == null) return null;
  final name = label.trim().toLowerCase().replaceAll(RegExp('["\']'), '');
  if (name.isEmpty) return null;
  if (name == 'utf-8' || name == 'utf8') return _Family.utf8;
  // Latin-1 and its relatives. Browsers read all of these as Windows-1252;
  // ISO-8859-15 differs from it in eight rarely used characters.
  const latin = {
    'windows-1252',
    'cp1252',
    'x-cp1252',
    'iso-8859-1',
    'iso8859-1',
    'iso_8859-1',
    'latin1',
    'l1',
    'us-ascii',
    'ascii',
    'iso-8859-15',
  };
  return latin.contains(name) ? _Family.windows1252 : _Family.other;
}

/// The charset a page declares for itself in its first two kilobytes.
String? _metaCharset(List<int> bytes) {
  final head = latin1.decode(
    bytes.length > 2048 ? bytes.sublist(0, 2048) : bytes,
    allowInvalid: true,
  );
  return RegExp(
    r'''<meta[^>]+charset\s*=\s*["']?\s*([A-Za-z0-9_\-]+)''',
    caseSensitive: false,
  ).firstMatch(head)?.group(1);
}

/// Windows-1252: Latin-1, with printable characters (curly quotes, dashes,
/// the euro sign) where Latin-1 has control codes.
String _decodeWindows1252(List<int> bytes) {
  final out = StringBuffer();
  for (final byte in bytes) {
    final b = byte & 0xFF;
    out.writeCharCode(b >= 0x80 && b <= 0x9F ? _c1[b - 0x80] : b);
  }
  return out.toString();
}

/// Code points for bytes 0x80 to 0x9F. The five bytes Windows-1252 leaves
/// undefined map to themselves, as browsers do.
const List<int> _c1 = [
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F, //
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178, //
];
